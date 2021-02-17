proc stop_local {host port} {
    catch {exec "./src/redis-cli" "-p" $port "-h" $host "shutdown"} error
    puts $error
}

proc start_local_no_config {port dir gid} {
    if { [file exists $dir] != 1} {  
       puts [file mkdir $dir]
    }
    exec "./src/redis-server" "--crdt-gid" "default" $gid "--loadmodule" "../../crdt-module/crdt.so" "--port" $port "--logfile" "redis.log" "--daemonize" "yes" "--dir" $dir "--protected-mode" "no" 
}

proc create_config {port dir gid} {
    set f [open [format "%s/redis.conf" $dir] w+]
    puts $f [format "crdt-gid default %s \n" $gid]
    puts $f "loadmodule ../../crdt-module/crdt.so \n"
    puts $f "logfile redis.log \n"
    puts $f "daemonize yes \n"
    puts $f [format "dir %s \n" $dir]
    puts $f "protected-mode no \n"
    puts $f [format "port %s \n" $port]
    puts $f "repl-diskless-sync yes \n"
    puts $f "repl-diskless-sync-delay 1 \n"
    close $f
}


proc start_local {port dir gid} {
    if { [file exists $dir] != 1} {  
       puts [file mkdir $dir]
    }
    create_config $port $dir $gid
    set redis_conf [format "%s/redis.conf" $dir]
    exec "./src/redis-server" $redis_conf
}

proc stop_stand_alone_three_master {port1 port2 port3} {
    set local_host "127.0.0.1"
    stop_local $local_host $port1
    stop_local $local_host $port2
    stop_local $local_host $port3
    
}

proc start_stand_alone_three_master {port1 port2 port3} {
    set local_host "127.0.0.1"
    set dir "./local_crdt/"
    start_local  $port1 [format "%s/%s" $dir $port1] 1
    start_local  $port2 [format "%s/%s" $dir $port2] 2 
    start_local  $port3 [format "%s/%s" $dir $port3] 3
}

proc stop_stand_alone_one_slave {port} {
    set local_host "127.0.0.1"
    stop_local $local_host $port
}

proc start_stand_alone_one_slave {port} {
    set local_host "127.0.0.1"
    set dir "./local_crdt/"
    start_local  $port [format "%s/%s" $dir $port] 1
}

proc del_local_crdt_dir {port} {
    set dir [exec "pwd"]
    catch {exec [format "rm -rf '%s/local_crdt/%s'" $dir $port]} error
    puts $error
}

proc write_all_api {host port time} {
    return [start_write_script $host $port $time {
        $r set k v 
    }]
}

proc check_ttl {key client1 client2 log} {
    if {[expr [$client1 ttl $key] - [$client2 ttl $key]] < 5} {
        return 1
    }
    if {$log} {
        puts [format "ttl diff %s %s" [$client1 ttl $key] [$client2 ttl $key]]
    }
    return 0
}

proc check_kv {key client1 client2 log} {
    if {[check_ttl $key $client1 $client2 $log] == 0} {
        return 0
    }
    if {[$client1 crdt.datainfo $key ] != [$client2 crdt.datainfo $key]} {
        if {$log} {
            puts [format "check kv diff:\n  %s \n %s " [$client1 crdt.datainfo $key] [$client2 crdt.datainfo $key]]
        }
        return 0
    }
    return 1
}


proc try_check_kv {key client1 client2 num} {

    while {$num} {
        if {[check_kv $key $client1 $client2 0] == 1} {
            break
        }
        after 100
        incr num -1
    }
    if {$num == 0} {
        check_kv $key $client1 $client2 1
        return 0
    }
    return 1

}

proc check_hash {key client1 client2 log} {
    if {[check_ttl $key $client1 $client2 $log] == 0} {
        return 0
    }
    if {[$client1 hlen $key] != [$client2 hlen $key]} {
        if {$log == 1} {
            puts [format "check hash size: %s, %s" [$client1 hlen $key] [$client2 hlen $key]]
        }
        return 0
    }
    set cur 0
    set keys {}
    while 1 {
        set res [$client1 hscan $key $cur]
        set cur [lindex $res 0]
        set k [lindex $res 1]
        # lappend keys {*}$k
        set klen [llength $k]
        for {set kindex 0} {$kindex < $klen} {incr kindex 2} {
            lappend keys [lindex $k $kindex]
        }
        if {$cur == 0} break
    }
    set keys [lsort -unique $keys]
    set len [llength $keys]
    for {set i 0} {$i < $len} {incr i} {
        set $k [lindex $keys $i]
        if {[$client1 crdt.hget $key $k] != [$client2 crdt.hget $key $k]} {
            if {$log == 1} {
                puts [format "check hash fail key:%s, field: %s, value: [%s], diff [%s]" $key $k [$client1 hget $key $k] [$client2 hget $key $k]]
            }
            return 0
        }
    }
    return 1
}

proc try_check_hash {key client1 client2 num} {
    while {$num} {
        if {[check_hash $key $client1 $client2 0] == 1} {
            break
        }
        after 100
        incr num -1
    }
    if {$num == 0} {
        check_hash $key $client1 $client2 1
        return 0
    }
    return 1
}

proc check_set {key client1 client2 log} {
    if {[check_ttl $key $client1 $client2 $log] == 0} {
        return 0
    }
    if {[$client1 scard $key] != [$client2 scard $key]} {
        if {$log == 1} {
            puts [format "check set size: %s, %s" [$client1 scard $key] [$client2 scard $key]]
        }
        return 0
    }
    set cur 0
    set keys {}
    while 1 {
        set res [$client1 sscan $key $cur]
        set cur [lindex $res 0]
        set k [lindex $res 1]
        lappend keys {*}$k
        if {$cur == 0} break
    }
    set keys [lsort -unique $keys]
    set len [llength $keys]
    for {set i 0} {$i < $len} {incr i} {
        set $k [lindex $keys $i]
        if {[$client1 crdt.sismember $key $k] != [$client2 crdt.sismember $key $k]} {
            if {$p == 1} {
                puts [format "check set fail key:%s, field: %s, value: [%s], diff [%s]" $key $k [$client1 crdt.sismember $key $k] [$client2 crdt.sismember $key $k]]
            }
            return 0
        }
    }
    return 1
}


proc try_check_set {key client1 client2 num} {
    while {$num} {
        if {[check_set $key $client1 $client2 0] == 1} {
            break
        }
        after 100
        incr num -1
    }
    if {$num == 0} {
        check_set $key $client1 $client2 1
        return 0
    }
    return 1
}

proc check_zset {key client1 client2 log} {
    if {[check_ttl $key $client1 $client2 $log] == 0} {
        return 0
    }
    if {[$client1 zcard $key] != [$client2 zcard $key]} {
        if {$log == 1} {
            puts [format "check set size: %s, %s" [$client1 zcard $key] [$client2 zcard $key]]
        }
        return 0
    }
    set cur 0
    set keys {}
    while 1 {
        set res [$client1 zscan $key $cur]
        set cur [lindex $res 0]
        set k [lindex $res 1]
        # lappend keys {*}$k
        set klen [llength $k]
        for {set kindex 0} {$kindex < $klen} {incr kindex 2} {
            lappend keys [lindex $k $kindex]
        }
        if {$cur == 0} break
    }
    set keys [lsort -unique $keys]
    set len [llength $keys]
    for {set i 0} {$i < $len} {incr i} {
        set $k [lindex $keys $i]
        if {[$client1 crdt.zscore $key $k] != [$client2 crdt.zscore $key $k]} {
            if {$p == 1} {
                puts [format "check zset fail key:%s, field: %s, value: [%s], diff [%s]" $key $k [$client1 zscore $key $k] [$client2 zscore $key $k]]
            }
            return 0
        }
    }
    return 1
}


proc try_check_zset {key client1 client2 num} {
    while {$num} {
        if {[check_zset $key $client1 $client2 0] == 1} {
            break
        }
        after 100
        incr num -1
    }
    if {$num == 0} {
        check_zset $key $client1 $client2 1
        return 0
    }
    return 1
}

proc check_rc {key client1 client2 log} {
    if {[check_ttl $key $client1 $client2 $log] == 0} {
        return 0
    }
    if {[$client1 crdt.datainfo $key ] != [$client2 crdt.datainfo $key]} {
        if {$log} {
            puts [format "check rc diff:\n  %s \n %s " [$client1 crdt.datainfo $key] [$client2 crdt.datainfo $key]]
        }
        return 0
    }
    return 1
}

proc try_check_rc {key client1 client2 num} {
    while {$num} {
        if {[check_rc $key $client1 $client2 0] == 1} {
            break
        }
        after 100
        incr num -1
    }
    if {$num == 0} {
        check_rc $key $client1 $client2 1
        return 0
    }
    return 1
}

proc try_check {client1 client2 num} {
    set cur 0
    set keys {}
    while 1 {
        set res [$client1 scan $cur]
        set cur [lindex $res 0]
        set k [lindex $res 1]
        lappend keys {*}$k
        if {$cur == 0} break
    }
    set keys [lsort -unique $keys]
    set len [llength $keys]
    for {set i 0} {$i < $len} {incr i} {
        set key [lindex $keys $i]
        set type [$client1 type $key]
        # puts [format "check key: %s, %s" $key $type]
        switch $type {
            "crdt_regr" {
                if {[try_check_kv $key $client1 $client2 $num] == 0} {
                    puts [format "check kv fail, key: %s ,type: %s" $key $type]
                    return 0
                }
            }
            "crdt_hash" {
                if {[try_check_hash $key $client1 $client2 $num] == 0} {
                    puts [format "check hash fail, key: %s" $key ]
                    return 0
                }
            }
            "crdt_setr" {
                if {[try_check_set $key $client1 $client2 $num] == 0} {
                    puts [format "check set fail, key: %s" $key ]
                    return 0
                }
            }
            "crdt_ss_v" {
                if {[try_check_zset $key $client1 $client2 $num] == 0} {
                    puts [format "check zset fail, key: %s" $key ]
                    return 0
                }
            }
            "crdt_rc_v" {
                if {[try_check_rc $key $client1 $client2 $num] == 0} {
                    puts [format "check rc fail, key: %s" $key ]
                    return 0
                }
            }
        }
        
    }
    return 1
}

proc try_check_all {comment client1 client2 num} {
    
    if {[try_check $client1 $client2 $num] == 1} {
        return 1
    }
    puts [format "try_check_all fail: %s" $comment]
    return 0
}