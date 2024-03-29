proc randstring {min max {type binary}} {
    set len [expr {$min+int(rand()*($max-$min+1))}]
    set output {}
    if {$type eq {binary}} {
        set minval 0
        set maxval 255
    } elseif {$type eq {alpha}} {
        set minval 48
        set maxval 122
    } elseif {$type eq {compr}} {
        set minval 48
        set maxval 52
    }
    while {$len} {
        append output [format "%c" [expr {$minval+int(rand()*($maxval-$minval+1))}]]
        incr len -1
    }
    return $output
}

# Useful for some test
proc zlistAlikeSort {a b} {
    if {[lindex $a 0] > [lindex $b 0]} {return 1}
    if {[lindex $a 0] < [lindex $b 0]} {return -1}
    string compare [lindex $a 1] [lindex $b 1]
}

# Return all log lines starting with the first line that contains a warning.
# Generally, this will be an assertion error with a stack trace.
proc warnings_from_file {filename} {
    set lines [split [exec cat $filename] "\n"]
    set matched 0
    set logall 0
    set result {}
    foreach line $lines {
        if {[string match {*REDIS BUG REPORT START*} $line]} {
            set logall 1
        }
        if {[regexp {^\[\d+\]\s+\d+\s+\w+\s+\d{2}:\d{2}:\d{2} \#} $line]} {
            set matched 1
        }
        if {$logall || $matched} {
            lappend result $line
        }
    }
    join $result "\n"
}

# Return value for INFO property
proc status {r property} {
    if {[regexp "\r\n$property:(.*?)\r\n" [{*}$r info] _ value]} {
        set _ $value
    }
}

proc crdt_status {r property} {
    if {[regexp "\r\n$property:(.*?)\r\n" [{*}$r crdt.info replication] _ value]} {
        set _ $value
    }
}

proc crdt_stats {r property} {
    if {[regexp "\r\n$property:(.*?)\r\n" [{*}$r crdt.info stats] _ value]} {
        set _ $value
    }
}

proc crdt_conflict {r type} {
        if {[regexp "$type=(\\d+)" [{*}$r crdt.info stats] _ value]} {
        set _ $value
    }
}

proc crdt_repl { client property } {
    set info [ $client crdt.info replication]
    if {[regexp "\r\n$property:(.*?)\r\n" $info _ value]} {
        set _ $value
    }
}

proc waitForBgsave r {
    while 1 {
        if {[status r rdb_bgsave_in_progress] eq 1} {
            if {$::verbose} {
                puts -nonewline "\nWaiting for background save to finish... "
                flush stdout
            }
            after 1000
        } else {
            break
        }
    }
}

proc waitForBgrewriteaof r {
    while 1 {
        if {[status r aof_rewrite_in_progress] eq 1} {
            if {$::verbose} {
                puts -nonewline "\nWaiting for background AOF rewrite to finish... "
                flush stdout
            }
            after 1000
        } else {
            break
        }
    }
}

proc wait_for_sync r {
    # while 1 {
    #     if {[status $r master_link_status] eq "down"} {
    #         after 10
    #     } else {         
    #         break
    #     }
    # }
    set trycount 0
    while 1 {
        if {[status $r master_link_status] eq "up"} {
            break
        } else {
            incr trycount +1
            if {$trycount > 6000} {
                puts [$r info ]
                fail "wait_for_sync"
            }
            after 10
        }
    }
}

proc wait_for_peer_sync r {
    set trycount 0
    while 1 {
        if {[crdt_status $r peer0_link_status] eq "up"} {
            break
        } else {
            incr trycount +1
            if {$trycount > 6000} {
                puts [$r info ]
                puts [$r crdt.info replication]
                fail "wait_for_peer_sync"
            }
            after 10
        }
    }
}

proc wait_for_peers_sync {i r} {
    set index 0
    set trycount 0
    while 1 {
        set s [format "peer%s_link_status" $index]
        if {[crdt_status $r $s] eq "up"} {
            if {$index == $i} {
                break
            } else {
                incr index
            }
        } else {
            incr trycount +1
            if {$trycount > 6000} {
                puts [$r info ]
                puts [$r crdt.info replication]
                fail [format "wait_for_peers_sync %s" $i]
            }
            after 10
        }
    }
}

# Random integer between 0 and max (excluded).
proc randomInt {max} {
    expr {int(rand()*$max)}
}

proc randomFloat { min max } {
    set rd [expr rand()]
    set result [expr $rd * ($max - $min) + $min]
    return $result
}

# Random signed integer between -max and max (both extremes excluded).
proc randomSignedInt {max} {
    set i [randomInt $max]
    if {rand() > 0.5} {
        set i -$i
    }
    return $i
}

proc randpath args {
    set path [expr {int(rand()*[llength $args])}]
    uplevel 1 [lindex $args $path]
}

proc randomValue {} {
    randpath {
        # Small enough to likely collide
        randomSignedInt 1000
    } {
        # 32 bit compressible signed/unsigned
        randpath {randomSignedInt 2000000000} {randomSignedInt 4000000000}
    } {
        # 64 bit
        randpath {randomSignedInt 1000000000000}
    } {
        # Random string
        randpath {randstring 0 256 alpha} \
                {randstring 0 256 compr} \
                {randstring 0 256 binary}
    } {
        #float 
        randomFloat -1 1
    }
}

proc randomString {} {
    randpath {randstring 0 256 alpha} \
                {randstring 0 256 compr} \
                {randstring 0 256 binary}
}

proc randomKey {} {
    randpath {
        # Small enough to likely collide
        randomInt 1000
    } {
        # 32 bit compressible signed/unsigned
        randpath {randomInt 2000000000} {randomInt 4000000000}
    } {
        # 64 bit
        randpath {randomInt 1000000000000}
    } {
        # Random string
        randpath {randstring 1 256 alpha} \
                {randstring 1 256 compr}
    }
}

proc findKeyWithType {r type} {
    for {set j 0} {$j < 20} {incr j} {
        set k [{*}$r randomkey]
        if {$k eq {}} {
            return {}
        }
        if {[{*}$r type $k] eq $type} {
            return $k
        }
    }
    return {}
}

proc createComplexDataset {r ops {opt {}}} {
    for {set j 0} {$j < $ops} {incr j} {
        set k [randomKey]
        set k2 [randomKey]
        set f [randomValue]
        set v [randomValue]

        if {[lsearch -exact $opt useexpire] != -1} {
            if {rand() < 0.1} {
                {*}$r expire [randomKey] [randomInt 2]
            }
        }

        randpath {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            randpath {set d +inf} {set d -inf}
        }
        set t [{*}$r type $k]

        if {$t eq {none}} {
            randpath {
                {*}$r set $k $v
            } {
                {*}$r lpush $k $v
            } {
                {*}$r sadd $k $v
            } {
                {*}$r zadd $k $d $v
            } {
                {*}$r hset $k $f $v
            } {
                {*}$r del $k
            }
            set t [{*}$r type $k]
        }

        switch $t {
            {string} {
                # Nothing to do
            }
            {list} {
                randpath {{*}$r lpush $k $v} \
                        {{*}$r rpush $k $v} \
                        {{*}$r lrem $k 0 $v} \
                        {{*}$r rpop $k} \
                        {{*}$r lpop $k}
            }
            {set} {
                randpath {{*}$r sadd $k $v} \
                        {{*}$r srem $k $v} \
                        {
                            set otherset [findKeyWithType {*}$r set]
                            if {$otherset ne {}} {
                                randpath {
                                    {*}$r sunionstore $k2 $k $otherset
                                } {
                                    {*}$r sinterstore $k2 $k $otherset
                                } {
                                    {*}$r sdiffstore $k2 $k $otherset
                                }
                            }
                        }
            }
            {zset} {
                randpath {{*}$r zadd $k $d $v} \
                        {{*}$r zrem $k $v} \
                        {
                            set otherzset [findKeyWithType {*}$r zset]
                            if {$otherzset ne {}} {
                                randpath {
                                    {*}$r zunionstore $k2 2 $k $otherzset
                                } {
                                    {*}$r zinterstore $k2 2 $k $otherzset
                                }
                            }
                        }
            }
            {hash} {
                randpath {{*}$r hset $k $f $v} \
                        {{*}$r hdel $k $f}
            }
        }
    }
}

proc createAllStringDataset {r ops {opt {}}} {
    for {set j 0} {$j < $ops} {incr j} {
        set k [randomKey]
        set k2 [randomKey]
        set f [randomValue]
        set v [randomValue]

        if {[lsearch -exact $opt useexpire] != -1} {
            if {rand() < 0.1} {
                {*}$r expire [randomKey] [randomInt 2]
            }
        }

        randpath {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            randpath {set d +inf} {set d -inf}
        }
        {*}$r set $k $v
    }
}

proc createAllHashDataset {r ops {opt {}}} {
    for {set j 0} {$j < $ops} {incr j} {
        set k [randomKey]
        set k2 [randomKey]
        set f [randomValue]
        set v [randomValue]

        if {[lsearch -exact $opt useexpire] != -1} {
            if {rand() < 0.1} {
                {*}$r expire [randomKey] [randomInt 2]
            }
        }

        randpath {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            set d [expr {rand()}]
        } {
            randpath {set d +inf} {set d -inf}
        }
        for {set y 0} {$y < $ops} {incr y} {
            set f [randomValue]
            set v [randomValue]
            {*}$r hset $k $f $v
        }
    }
}

proc formatCommand {args} {
    set cmd "*[llength $args]\r\n"
    foreach a $args {
        append cmd "$[string length $a]\r\n$a\r\n"
    }
    set _ $cmd
}

proc csvdump r {
    set o {}
    for {set db 0} {$db < 16} {incr db} {
        {*}$r select $db
        foreach k [lsort [{*}$r keys *]] {
            set type [{*}$r type $k]
            append o [csvstring $db] , [csvstring $k] , [csvstring $type] ,
            switch $type {
                string {
                    append o [csvstring [{*}$r get $k]] "\n"
                }
                list {
                    foreach e [{*}$r lrange $k 0 -1] {
                        append o [csvstring $e] ,
                    }
                    append o "\n"
                }
                set {
                    foreach e [lsort [{*}$r smembers $k]] {
                        append o [csvstring $e] ,
                    }
                    append o "\n"
                }
                zset {
                    foreach e [{*}$r zrange $k 0 -1 withscores] {
                        append o [csvstring $e] ,
                    }
                    append o "\n"
                }
                hash {
                    set fields [{*}$r hgetall $k]
                    set newfields {}
                    foreach {k v} $fields {
                        lappend newfields [list $k $v]
                    }
                    set fields [lsort -index 0 $newfields]
                    foreach kv $fields {
                        append o [csvstring [lindex $kv 0]] ,
                        append o [csvstring [lindex $kv 1]] ,
                    }
                    append o "\n"
                }
            }
        }
    }
    {*}$r select 9
    return $o
}

proc csvstring s {
    return "\"$s\""
}

proc roundFloat f {
    format "%.10g" $f
}

set ::disabled_port [dict create]
proc add_disabled_port port {
    dict set ::disabled_port $port 1
}

proc remove_disabled_port port {
    set ::disabled_port [dict remove $::disabled_port $port]
}

proc is_disabled_port port {
    set _ [dict exists $::disabled_port $port]
}

set ::last_port_attempted 0
#625 = 10000/16(clients)
proc find_available_server_port {start} {
    set trycount 3
    for {set j 0} {$j <$trycount} {incr j} {
        set port $start
        for {set i 0} {$i < 625} {incr i} {
            if {[is_disabled_port $port]} {
                incr port
                continue
            }
            if {[catch {set fd1 [socket 127.0.0.1 $port]}] &&
                [catch {set fd2 [socket 127.0.0.1 [expr $port+10000]]}]} {
                set ::last_port_attempted $port
                return $port
            } else {
                catch {
                    close $fd1
                    close $fd2
                }
            }
            incr port
        }
    }
    error "Can't find a non busy port in the $start-[expr {$start+$count-1}] range."
}
proc find_available_port start {
    for {set j $start} {$j < $start+1024} {incr j} {
        if {[is_disabled_port $j]} {
            continue
        }
        if {[catch {set fd1 [socket 127.0.0.1 $j]}] &&
            [catch {set fd2 [socket 127.0.0.1 [expr $j+10000]]}]} {
            return $j
        } else {
            catch {
                close $fd1
                close $fd2
            }
        }
    }
    if {$j == $start+1024} {
        error "Can't find a non busy port in the $start-[expr {$start+1023}] range."
    }
}

# Test if TERM looks like to support colors
proc color_term {} {
    expr {[info exists ::env(TERM)] && [string match *xterm* $::env(TERM)]}
}

proc colorstr {color str} {
    if {[color_term]} {
        set b 0
        if {[string range $color 0 4] eq {bold-}} {
            set b 1
            set color [string range $color 5 end]
        }
        switch $color {
            red {set colorcode {31}}
            green {set colorcode {32}}
            yellow {set colorcode {33}}
            blue {set colorcode {34}}
            magenta {set colorcode {35}}
            cyan {set colorcode {36}}
            white {set colorcode {37}}
            default {set colorcode {37}}
        }
        if {$colorcode ne {}} {
            return "\033\[$b;${colorcode};49m$str\033\[0m"
        }
    } else {
        return $str
    }
}

# Execute a background process writing random data for the specified number
# of seconds to the specified Redis instance.
proc start_write_load {host port seconds} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/gen_write_load.tcl $host $port $seconds &
}

# Execute a background process writing random data for the specified number
# of seconds to the specified Redis instance.
proc start_write_expire_load {host port seconds type} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/gen_write_expire_load.tcl $host $port $seconds $type &
}

proc start_write_load_with_interval {host port seconds interval} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/gen_write_load_with_interval.tcl $host $port $seconds $interval &
}

proc start_write_db_load {host port seconds db} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/gen_write_db_load.tcl $host $port $seconds $db &
}

proc start_write_script {host port seconds script} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/gen_write_load_script.tcl $host $port $seconds $script &
}

# Stop a process generating write load executed with start_write_load.
proc stop_write_load {handle} {
    catch {exec /bin/kill -9 $handle}
}

# Execute a background process writing random data for the specified number
# of seconds to the specified Redis instance.
proc start_crdt_hash_load {host port seconds} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/gen_crdt_hash_load.tcl $host $port $seconds &
}

# Stop a process generating write load executed with start_write_load.
proc stop_crdt_hash_load {handle} {
    catch {exec /bin/kill -9 $handle}
}

proc gen_key_set {length} {
    set key_set {}
    while {$length > 0} {
        incr length -1
        lappend key_set [randstring 10 256 alpha]
    }
    return $key_set
}
proc wait_script {script err} {
    set retry 100
    while {$retry} {
        set conditionCmd [list expr $script] 
        if {[uplevel 1 $conditionCmd]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        catch [uplevel 1 $err] error
    }
}

proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}

proc check_peer_info {peerMaster  peerSlave masteindex} {
    set attr [format "peer%d_repl_offset" $masteindex]
    set replid [format "peer%d_replid" $masteindex]
    $peerMaster debug set-crdt-ovc 0
    after 1000
    wait_script {
        [ get_info_replication_attr_value  $peerMaster crdt.info master_repl_offset] 
        ==
        [ get_info_replication_attr_value $peerSlave crdt.info $attr]
    } {
        puts [ get_info_replication_attr_value  $peerMaster crdt.info master_repl_offset] 
        puts [ get_info_replication_attr_value $peerSlave crdt.info $attr]
        fail "check_peer_info offset diff"
    }
    wait_script {
        [ get_info_replication_attr_value  $peerMaster crdt.info master_replid] 
        ==
        [ get_info_replication_attr_value $peerSlave crdt.info $replid]
    } {
        
        puts [ get_info_replication_attr_value  $peerMaster crdt.info master_repl_offset] 
        puts [ get_info_replication_attr_value $peerSlave crdt.info $attr]
        fail "check_peer_info replid diff"
    }
    $peerMaster debug set-crdt-ovc 1
}


proc d2b {d} {
    set b ""
    while {$d!=0} {
        set b "[expr $d%2]$b"
        set d [expr $d/2]
    }
    return $b
}

proc i2b {i} {
    return [binary format B* [d2b $i]]
}