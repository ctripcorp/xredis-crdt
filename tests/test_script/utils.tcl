proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}

proc print_log_file {log} {
    set content [read_file $log]
    puts $content
}

proc wait_sync { client index type log}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            assert_equal [$client ping] PONG
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        assert_equal [$client ping] PONG
        # if {$log != ""} {
        #     print_log_file $log
        # }
        error $log
    }
}

#create six redis  
proc create_crdts {type arrange} {
    start_server {tags {"repl"} overrides {crdt-gid 3} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_log [srv 0 stdout]
        set peer2_gid 3
        $peer2 config set repl-diskless-sync yes
        $peer2 config set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-diskless-sync-delay 1
        start_server {overrides {crdt-gid 3} module {crdt.so}} {
            set peer2_slave [srv 0 client]
            set peer2_slave_host [srv 0 host]
            set peer2_slave_port [srv 0 port]
            set peer2_slave_log [srv 0 stdout]
            set peer2_slave_gid 3
            $peer2_slave config set repl-diskless-sync yes
            $peer2_slave config set repl-diskless-sync-delay 1
            $peer2_slave config crdt.set repl-diskless-sync-delay 1
            start_server {overrides {crdt-gid 2} module {crdt.so}} {
                set peer [srv 0 client]
                set peer_host [srv 0 host]
                set peer_port [srv 0 port]
                set peer_log [srv 0 stdout]
                set peer_gid 2
                $peer config set repl-diskless-sync yes
                $peer config set repl-diskless-sync-delay 1
                $peer config crdt.set repl-diskless-sync-delay 1

                start_server {overrides {crdt-gid 2} module {crdt.so}} {
                    set peer_slave [srv 0 client]
                    set peer_slave_host [srv 0 host]
                    set peer_slave_port [srv 0 port]
                    set peer_slave_log [srv 0 stdout]
                    set peer_slave_gid 2
                    $peer_slave config set repl-diskless-sync yes
                    $peer_slave config set repl-diskless-sync-delay 1
                    $peer_slave config crdt.set repl-diskless-sync-delay 1
    
                    start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
                        set master [srv 0 client]
                        set master_host [srv 0 host]
                        set master_port [srv 0 port]
                        set master_log [srv 0 stdout]
                        set master_gid 1
                        $master config set repl-diskless-sync yes
                        $master config set repl-diskless-sync-delay 1
                        $master config crdt.set repl-diskless-sync-delay 1
                        start_server {overrides {crdt-gid 1} module {crdt.so}} {
                            set slave [srv 0 client]
                            set slave_host [srv 0 host]
                            set slave_port [srv 0 port]
                            set slave_log [srv 0 stdout]
                            set slave_gid 1
                            $slave config set repl-diskless-sync yes
                            $slave config set repl-diskless-sync-delay 1
                            $slave config crdt.set repl-diskless-sync-delay 1
                            

                            $peer_slave slaveof $peer_host $peer_port
                            $peer2_slave slaveof $peer2_host $peer2_port
                            $slave slaveof $master_host $master_port 
                            $master peerof $peer_gid $peer_host $peer_port 
                            $master peerof $peer2_gid $peer2_host $peer2_port 
                            $peer  peerof $peer2_gid $peer2_host $peer2_port 
                            $peer  peerof $master_gid $master_host $master_port
                            $peer2 peerof $master_gid $master_host $master_port
                            $peer2 peerof $peer_gid $peer_host $peer_port
                            wait_sync $master 0 crdt.info $master_log
                            wait_sync $master 1 crdt.info $master_log
                            wait_sync $peer 0 crdt.info $peer_log
                            wait_sync $peer 1 crdt.info $peer_log
                            wait_sync $peer2 0 crdt.info $peer2_log
                            wait_sync $peer2 1 crdt.info $peer2_log
                            wait_sync $master 0 info $slave_log
                            wait_sync $peer 0 info $peer_slave_log
                            wait_sync $peer2 0 info $peer2_slave_log
                            after 5000
                            test $type {
                                if {[catch [uplevel 0 $arrange ] result]} {
                                    puts $result
                                }
                                exec cp $master_log ./m.log
                                exec cp $peer_log ./p.log
                                exec cp $peer2_log ./p2.log
                            }
                        }
                    }
                }
            } 
        }
    }
}

 
proc start_local {port dir gid} {
    if { [file exists $dir] != 1} {  
       puts [file mkdir $dir]
    }
    exec "./src/redis-server" "--crdt-gid" "default" $gid "--loadmodule" "../../crdt-module/crdt.so" "--port" $port "--logfile" "redis.log" "--daemonize" "yes" "--dir" $dir "--protected-mode" "no" 
}

proc start_local_by_file {port dir gid} {
    if { [file exists $dir] != 1} {  
    puts [file mkdir $dir]
    }
    set redis_conf [format "%s/redis.conf" $dir]
    if { [file exists $redis_conf] != 1} {
        set f [open $redis_conf w+]
        puts $f [format "crdt-gid default %s " $gid ]
        puts $f "loadmodule ../../crdt-module/crdt.so" 
        puts $f [format "port %s" $port ]
        puts $f "logfile redis.log"
        puts $f "daemonize yes"
        puts $f [format "dir %s" $dir]
        puts $f "protected-mode no"
    }
    puts $redis_conf
    exec "./src/redis-server" $redis_conf
}

proc stop_local {host port} {
    catch {exec "./src/redis-cli" "-p" $port "-h" $host "shutdown"} error
}

proc set_crdt_config {client} {
    $client config set repl-diskless-sync yes
    $client config set repl-diskless-sync-delay 1
    $client config crdt.set repl-diskless-sync-delay 1
                        
}

proc start_local_master_redis3 {type arrange close} {
    set sport 7000
    set log_file "/redis.log"
    set local_host "127.0.0.1"

    set master_dir "./local_crdt/master"
    set master_port [incr sport]
    set master_host "127.0.0.1"
    set master_gid 1
    set master_log "$master_dir/$log_file"

    set peer_dir "./local_crdt/peer"
    set peer_host "127.0.0.1"
    set peer_port [incr sport]
    
    set peer_gid 2
    set peer_log "$peer_dir/$log_file"; 

    set peer2_dir "./local_crdt/peer2"
    set peer2_host "127.0.0.1"
    set peer2_port [incr sport]
    
    set peer2_gid 3
    set peer2_log "$peer2_dir/$log_file"

    stop_local $master_host $master_port
    stop_local $peer_host $peer_port
    stop_local $peer2_host $peer2_port
    start_local  $master_port $master_dir $master_gid
    start_local  $peer_port $peer_dir $peer_gid 
    start_local  $peer2_port $peer2_dir $peer2_gid
    after 1000

    set master [redis $master_host $master_port]
    set peer [redis $peer_host $peer_port]
    set peer2 [redis $peer2_host $peer2_port]

    set_crdt_config $master 
    set_crdt_config $peer
    set_crdt_config $peer2
   
    $master peerof $peer_gid $peer_host $peer_port 
    $master peerof $peer2_gid $peer2_host $peer2_port 
    $peer  peerof $peer2_gid $peer2_host $peer2_port 
    $peer  peerof $master_gid $master_host $master_port
    $peer2 peerof $master_gid $master_host $master_port
    $peer2 peerof $peer_gid $peer_host $peer_port
    wait_sync $master 0 crdt.info $master_log
    wait_sync $master 1 crdt.info $master_log
    wait_sync $peer 0 crdt.info $peer_log
    wait_sync $peer 1 crdt.info $peer_log
    wait_sync $peer2 0 crdt.info $peer2_log
    wait_sync $peer2 1 crdt.info $peer2_log
    test $type {
        if {[catch [uplevel 0 $arrange ] result]} {
            puts $result
        }
        if {$close} {
            stop_local $master_host $master_port
            stop_local $peer_host $peer_port
            stop_local $peer2_host $peer2_port
        }
        
    }
}


proc start_local_slave_redis3 {type arrange} {
    after 5000
    set sport 8000
    set log_file "/redis.log"
    set local_host "127.0.0.1"

    set slave_dir "./local_crdt/slave"
    set slave_port [incr sport]
    set slave_host "127.0.0.1"
    set slave_gid 1
    set slave_log "$slave_dir/$log_file"

    set peer_slave_dir "./local_crdt/peer_slave"
    set peer_slave_host "127.0.0.1"
    set peer_slave_port [incr sport] 
    
    set peer_slave_gid 2
    set peer_slave_log "$peer_slave_dir/$log_file"; 

    set peer2_slave_dir "./local_crdt/peer2_slave"
    set peer2_slave_host "127.0.0.1"
    set peer2_slave_port [incr sport] 
    
    set peer2_slave_gid 3
    set peer2_slave_log "$peer2_slave_dir/$log_file"

    stop_local $slave_host $slave_port
    stop_local $peer_slave_host $peer_slave_port
    stop_local $peer2_slave_host $peer2_slave_port
    start_local  $slave_port $slave_dir $slave_gid
    start_local  $peer_slave_port $peer_slave_dir $peer_slave_gid 
    start_local  $peer2_slave_port $peer2_slave_dir $peer2_slave_gid
    after 1000

    set slave [redis $slave_host $slave_port]
    set peer_slave [redis $peer_slave_host $peer_slave_port]
    set peer2_slave [redis $peer2_slave_host $peer2_slave_port]

    set_crdt_config $slave 
    set_crdt_config $peer_slave
    set_crdt_config $peer2_slave
   
    test $type {
        if {[catch [uplevel 0 $arrange ] result]} {
            puts $result
        }
        # stop_local $slave_host $slave_port
        # stop_local $peer_slave_host $peer_slave_port
        # stop_local $peer2_slave_host $peer2_slave_port
    }
}

# proc slaveof_master {slave master_host master_port master} {
#     $slave slaveof $master_host $master_port 
#     wait $master 0 info ""
     
# }


proc check3 {name current peer peer2 k} {
    set m_info [$current crdt.datainfo $k]
    set p_info [$peer crdt.datainfo $k]
    set p2_info [$peer2 crdt.datainfo $k]
    if { $m_info != $p_info }  {
        puts [format "%s master and peer diff" $name]
        puts $k
        puts $m_info
        puts $p_info
        if {[string length $m_info] != [string length $p_info]} {
            set run 0
        }
    }
    if { $m_info != $p2_info }  {
        puts [format "%s master and peer2 diff" $name]
        puts $k
        puts $m_info
        puts $p2_info
        if {[string length $m_info] != [string length $p2_info]} {
            set run 0
        }
    }
}

proc check_offset {name master slave} {
    set num 10
    while {$num} {
        set master_offset [get_info_replication_attr_value $master info master_repl_offset]
        set slave_offset [get_info_replication_attr_value $slave info master_repl_offset]
        if { $master_offset == $slave_offset } {    
            break;
        } else {
            after 200
            incr num -1
        }
    }
    if {$num == 0} {
        puts [format "%s check_offset diff" $name]
        puts [get_info_replication_attr_value $master info master_repl_offset]
        puts [get_info_replication_attr_value $slave info master_repl_offset]
    }
    
}

proc check_peer_offset {name master peer index} {
    # puts [$master info replication]
    set attr [format "peer%d_repl_offset" $index]
    set num 10
    while {$num} {
        set master_offset [get_info_replication_attr_value $master crdt.info master_repl_offset]
        set peer_offset [get_info_replication_attr_value $peer crdt.info $attr]
        if { $master_offset == $peer_offset } {
            break;
        } else {
            after 200
            incr num -1
        }
    }
    if {$num == 0} {
        puts [format "%s check_peer_offset diff" $name]
        puts [get_info_replication_attr_value $master crdt.info master_repl_offset]
        puts [get_info_replication_attr_value $peer crdt.info $attr]
    }
}

proc stop_ovc {client} {
    $client debug set-crdt-ovc 0

}

proc start_ovc {client} {
    $client debug set-crdt-ovc 1
}

#about check


proc check_set4 {key master peer peer2 slave} {
    set size [$master scard $key]
    proc check_scard {name key c1 size} {
        test [format $name $key] {
            assert_equal $size [$c1 scard $key]
        }
    }
    check_scard "master-peer-scard key %s" $key $peer $size
    check_scard "master-peer2-scard key %s" $key $peer2 $size
    check_scard "master-slave-scard key %s" $key $slave $size
    set cur 0
    # set keys {}
    while 1 {
        set res [$master sscan $key $cur]
        set cur [lindex $res 0]
        set ks [lindex $res 1]
        # lappend keys {*}$k
        set len [llength $ks]
        for {set kindex 0} {$kindex < $len} {incr kindex 1} {
            set k [lindex $ks $kindex]
            set master_set_field_value [$master crdt.sismember $key $k]
            puts $master_set_field_value
            test [format "master-peer-%s-%s" $key $k] {
                assert_equal $master_set_field_value [$peer crdt.sismember $key $k]
            }
            test [format "master-peer2-%s-%s" $key $k] {
                assert_equal $master_set_field_value [$peer2 crdt.sismember $key $k]
            }
            test [format "master-slave-%s-%s" $key $k] {
                assert_equal $master_set_field_value [$slave crdt.sismember $key $k]
            }
        }
        if {$cur == 0} break
    }
}

proc check_hash4 {key master peer peer2 slave} {
    set size [$master hlen $key]
    proc check_hlen {name key c1 size} {
        test [format $name $key] {
            assert_equal $size [$c1 hlen $key]
        }
    }
    check_hlen "master-peer-hlen key %s" $key $peer $size
    check_hlen "master-peer-hlen key %s" $key $peer2 $size
    check_hlen "master-peer-hlen key %s" $key $slave $size
    set cur 0
    # set keys {}
    while 1 {
        set res [$master hscan $key $cur]
        set cur [lindex $res 0]
        set kvs [lindex $res 1]
        set len [llength $kvs]
        for {set kindex 0} {$kindex < $len} {incr kindex 2} {
            set k [lindex $kvs $kindex]
            set v [$master crdt.hdatainfo $key $k]
            puts $v
            test [format "master-peer-%s-%s" $key $k] {
                assert_equal $v [$peer crdt.hdatainfo $key $k]
            }
            test [format "master-peer2-%s-%s" $key $k] {
                assert_equal $v [$peer2 crdt.hdatainfo $key $k]
            }
            test [format "master-slave-%s-%s" $key $k] {
                assert_equal $v [$slave crdt.hdatainfo $key $k]
            }
        }
        
        if {$cur == 0} break
    }
}

proc check_zset4 {key master peer peer2 slave} {
    set size [$master zcard $key]
    proc check_zcard {name key c1 size} {
        test [format $name $key] {
            assert_equal $size [$c1 zcard $key]
        }
    }
    check_zcard "master-peer-zcard key %s" $key $peer $size
    check_zcard "master-peer-zcard key %s" $key $peer2 $size
    check_zcard "master-peer-zcard key %s" $key $slave $size
    set cur 0
    # set keys {}
    while 1 {
        set res [$master zscan $key $cur]
        set cur [lindex $res 0]
        set kvs [lindex $res 1]
        set len [llength $kvs]
        for {set kindex 0} {$kindex < $len} {incr kindex 2} {
            set k [lindex $kvs $kindex]
            set v [$master crdt.zscore $key $k]
            test [format "master-peer-%s-%s" $key $k] {
                assert_equal $v [$peer crdt.zscore $key $k]
            }
            test [format "master-peer2-%s-%s" $key $k] {
                assert_equal $v [$peer2 crdt.zscore $key $k]
            }
            test [format "master-slave-%s-%s" $key $k] {
                assert_equal $v [$slave crdt.zscore $key $k]
            }
        }
        
        if {$cur == 0} break
    }
}

proc check_kv4 {key master peer peer2 slave} {
    test [format "master-peer-%s" $key] {
        assert_equal [$master crdt.datainfo $key] [$peer crdt.datainfo $key]
    }
    test [format "master-peer2-%s" $key] {
        assert_equal [$master crdt.datainfo $key] [$peer2 crdt.datainfo $key]
    }
    test [format "master-slave-%s" $key] {
        assert_equal [$master crdt.datainfo $key] [$slave crdt.datainfo $key]
    }
}
