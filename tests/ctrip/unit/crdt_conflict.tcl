
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

proc log_content {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}
proc wait { client index type log }  {
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
        log_content $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}

start_server {tags {"crdt-del"}  overrides {crdt-gid 1 loglevel {debug}} config {crdt.conf} module {crdt.so}  } {

    set peers {}
    set hosts {}
    set ports {}
    set gids {}
    set stdouts {}
    lappend peers [srv 0 client]
    lappend hosts [srv 0 host]
    lappend ports [srv 0 port]
    lappend gids 1
    lappend stdouts [srv 0 stdout]
    set server_log [srv 0 stdout]
    set redis_server [srv 0 client]
    test {conflict is record} {
        r CRDT.SET key-1 val2 3 [expr [clock milliseconds] - 10]  "1:10;2:99;3:100" 
        r CRDT.SET key-1 val1 2 [clock milliseconds]  "1:10;2:100;3:99" 

        set conflict [crdt_conflict $redis_server set]
        assert {$conflict >= 1}
        assert {[crdt_conflict $redis_server modify] == 1}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*CONFLICT*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    
    test {conflict dropped is record} {
        r CRDT.SET key-2 val2 3 [clock milliseconds] "1:10;2:99;3:100"  
        r CRDT.SET key-2 val1 2 [expr [clock milliseconds] - 10]   "1:10;2:100;3:99"  

        set redis_server [srv 0 client]
        assert {[crdt_conflict $redis_server set] == 2}
        assert {[crdt_conflict $redis_server modify] == 2}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }
     
    test {different type modify} {
        $redis_server CRDT.SET key-3 val2 3 [clock milliseconds] "1:10;2:99;3:101"  
        catch {$redis_server CRDT.HSET key-3 2 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k v}
        
        set conflict [crdt_conflict $redis_server type]
        assert {[crdt_conflict $redis_server type] == 1}
        assert {[crdt_conflict $redis_server modify] == 3}

        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    
    test {conflict is record} {
        $redis_server CRDT.HSET key-4 2 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k v 
        catch {r CRDT.SET key-4 val1 2 [clock milliseconds]  "1:10;2:100;3:99" }

        set conflict [crdt_conflict $redis_server type]
        assert {[crdt_conflict $redis_server type] == 2}
        assert {[crdt_conflict $redis_server modify] == 4}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*CONFLICT*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {different type modify} {
        $redis_server CRDT.HSET key-5 2  [clock milliseconds]  "1:10;2:99;3:101" 2 k val1
        $redis_server CRDT.HSET key-5 3 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k val2
    
        assert {[crdt_conflict $redis_server set] == 3}
        assert {[crdt_conflict $redis_server modify] == 5}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {different type modify} {
        $redis_server CRDT.HSET key-6 3 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k val2
        $redis_server CRDT.HSET key-6 2  [clock milliseconds]  "1:10;2:99;3:101" 2 k val1
        
    
        assert {[crdt_conflict $redis_server set] == 4}
        assert {[crdt_conflict $redis_server modify] == 6}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }

    test {crdt.set and crdt.del_reg} {
        $redis_server CRDT.SET key-7 val2 3 [clock milliseconds] "1:10;2:103;3:105"  
        $redis_server CRDT.del_reg key-7 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"  

        
        assert {[crdt_conflict $redis_server modify] == 7}
        assert {[crdt_conflict $redis_server set_del] == 1}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }

    test {crdt.del_reg and crdt.set} {
        $redis_server CRDT.del_reg key-8 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"  
        $redis_server CRDT.SET key-8 val2 3 [clock milliseconds] "1:10;2:103;3:105"  
        
        
        assert {[crdt_conflict $redis_server modify] == 8}
        assert {[crdt_conflict $redis_server set_del] == 2}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }
    
    test {crdt.del and crdt.del_reg} {
        $redis_server CRDT.del_reg key-9 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"  
        $redis_server CRDT.del_reg key-9 3 [clock milliseconds] "1:10;2:103;3:105"  
        
        
        assert {[crdt_conflict $redis_server modify] == 9}
        assert {[crdt_conflict $redis_server del] == 1}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }

    test { crdt.del_hash and crdt.hset} {
        $redis_server CRDT.del_hash key-10 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"   "1:10;2:105;3:103" 
        $redis_server CRDT.HSET key-10 3  [clock milliseconds] "1:10;2:103;3:105" 2 k val2
        
        assert {[crdt_conflict $redis_server modify] == 10}
        assert {[crdt_conflict $redis_server set_del] == 3}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }
    test {crdt.hset and crdt.del_hash} {
        $redis_server CRDT.HSET key-11 3  [clock milliseconds] "1:10;2:103;3:105" 2 k val2
        $redis_server CRDT.del_hash key-11 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"   "1:10;2:105;3:103" 
        assert {[crdt_conflict $redis_server modify] == 11}
        assert {[crdt_conflict $redis_server set_del] == 4}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {crdt.REM_HASH and crdt.hset} {
        $redis_server CRDT.REM_HASH key-12 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"   k
        $redis_server CRDT.HSET key-12 3  [clock milliseconds] "1:10;2:103;3:105" 2 k val2
        
        assert {[crdt_conflict $redis_server modify] == 12}
        assert {[crdt_conflict $redis_server set_del] == 5}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {crdt.hset and crdt.REM_HASH} {
        $redis_server CRDT.HSET key-13 3  [clock milliseconds] "1:10;2:103;3:105" 2 k val2
        $redis_server CRDT.REM_HASH key-13 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"   k
        assert {[crdt_conflict $redis_server modify] == 13}
        assert {[crdt_conflict $redis_server set_del] == 6}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {crdt.del_hash and crdt.del_hash} {
        $redis_server CRDT.del_hash key-14 3  [clock milliseconds] "1:10;2:103;3:105" "1:10;2:103;3:105"
        $redis_server CRDT.del_hash key-14 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"   "1:10;2:105;3:103" 
        # puts [crdt_stats $redis_server crdt_tombstone_isomrphic_conflict]
        # puts [crdt_stats $redis_server crdt_modify_conflict]
        assert {[crdt_conflict $redis_server modify] == 14}
        assert {[crdt_conflict $redis_server del] == 2}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }
    test {crdt.rem_hash and crdt.rem_hash} {
        $redis_server CRDT.rem_hash key-15 3  [clock milliseconds] "1:10;2:103;3:105"   k
        $redis_server CRDT.rem_hash key-15 2 [expr [clock milliseconds] - 10]   "1:10;2:105;3:103"  k
        assert {[crdt_conflict $redis_server modify] == 15}
        assert {[crdt_conflict $redis_server del] == 3}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }
    start_server {tags {"crdt-del"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend hosts [srv 0 host]
        lappend ports [srv 0 port]
        lappend stdouts [srv 0 stdout]
        lappend gids 2
        test "peer" {
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            [lindex $peers 1] CRDT.SET key-1 v25 2 [clock milliseconds]  "1:1;2:201;3:99"
            [lindex $peers 1] CRDT.HSET key-3 2 [expr [clock milliseconds]-10]  "1:2;2:202;3:99" 2 k v
            [lindex $peers 0] peerof [lindex $gids 1] [lindex $hosts 1] [lindex $ports 1]
            wait [lindex $peers 1] 0 crdt.info [lindex $stdouts 1]
            assert_equal [crdt_conflict [lindex $peers 0] type] 3
            assert_equal [crdt_conflict [lindex $peers 0] modify] 15
            assert_equal [crdt_conflict [lindex $peers 0] merge] 2
            assert_equal [crdt_conflict [lindex $peers 0] set] 5

            set before1 [crdt_conflict [lindex $peers 1] del]
            set before0 [crdt_conflict [lindex $peers 0] del]

            set num 30

            for {set j 0} {$j < $num} {incr j} {
                [lindex $peers 1] set $j $j
                [lindex $peers 1] expire $j 5
            } 
            after 6000
            assert_equal [crdt_conflict [lindex $peers 0] del]  $before0
            assert_equal [crdt_conflict [lindex $peers 1] del]  $before1
        }
    }
}




proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}

proc read_from_all_stream {s} {
    fconfigure $s -blocking 0
    set attempt 0
    while {[gets $s count] == -1} {
        if {[incr attempt] == 10} return ""
        after 100
    }
    fconfigure $s -blocking 1
    set count [string range $count 1 end]

    # Return a list of arguments for the command.
    set res {}
    for {set j 0} {$j < $count} {incr j} {
        read $s 1
        set arg [::redis::redis_bulk_read $s]
        if {$j == 0} {set arg [string tolower $arg]}
        puts $arg
        lappend res $arg
    }
    return $res
}
proc attach_to_replication_stream {host port} {
    set s [socket $host $port]
    fconfigure $s -translation binary
    puts -nonewline $s "SYNC\r\n"
    flush $s

    # Get the count
    while 1 {
        set count [gets $s]
        set prefix [string range $count 0 0]
        if {$prefix ne {}} break; # Newlines are allowed as PINGs.
    }
    if {$prefix ne {$}} {
        error "attach_to_replication_stream error. Received '$count' as count."
    }
    set count [string range $count 1 end]

    # Consume the bulk payload
    while {$count} {
        set buf [read $s $count]
        set count [expr {$count-[string length $buf]}]
    }
    return $s
}
start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1

        start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            $slave slaveof $master_host $master_port 
            
            start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
                set peer_slave [srv 0 client]
                set peer_slave_gid 2
                set peer_slave_host [srv 0 host]
                set peer_slave_port [srv 0 port]
                set peer_slave_log [srv 0 stdout]
                
                $peer_slave slaveof $peer_host $peer_port 

                $master peerof $peer_gid $peer_host $peer_port
                $peer peerof $master_gid $master_host $master_port
                wait_for_peer_sync $master
                wait_for_peer_sync $peer
                wait_for_sync $slave 
                wait_for_sync $peer_slave
                test "run two process create conflict" {
                    set load_handle0 [start_write_script $master_host $master_port 1000  { 
                        $r set k [randomValue]
                        $r set k1 1
                        $r set k2 a
                        $r mset k1 [randomValue] k2 [randomValue]
                        $r hset h k [randomValue] k1 [randomValue]
                        $r hdel h k 
                        $r del h
                        $r del k 
                    } ]
                    set load_handle1 [start_write_script $peer_host $peer_port 1000  { 
                        $r set k [randomValue]
                        $r set k1 1
                        $r set k2 a
                        $r mset k1 [randomValue] k2 [randomValue]
                        $r hset h k v k1 [randomValue]
                        $r hdel h k 
                        $r del h
                        $r del k 
                    } ]
                    after 1000
                    stop_write_load $load_handle0
                    stop_write_load $load_handle1
                    after 3000
                    test "1" {
                        assert_equal [$master get k] [$peer get k]
                        assert_equal [$slave get k] [$peer_slave get k]
                        assert_equal [$master get k] [$slave get k]
                    }
                    
                    test "2" {
                        assert_equal [$master hget h k] [$peer hget h k]
                        assert_equal [$slave hget h k] [$peer_slave hget h k]
                        assert_equal [$master hget h k] [$slave hget h k]
                    }
                    
                    test "3" {
                        assert_equal [$master hget h k1] [$peer hget h k1]
                        assert_equal [$slave hget h k1] [$peer_slave hget h k1]
                        assert_equal [$master hget h k1] [$slave hget h k1]
                    }
                    test "4" {
                        assert_equal [$master get k1]  [$peer get k1] 
                        assert_equal [$slave get k1] [$peer_slave get k1]
                        assert_equal [$master get k1]  [$slave get k1] 
                    }
                    
                    test "5" {
                        assert_equal [$master get k2] [$peer get k2]
                        assert_equal [$slave get k2] [$peer_slave get k2]
                        assert_equal [$master get k2] [$slave get k2]
                    }
                    test "6" {
                        assert_equal [$master mget k1 k2] [$peer mget k1 k2]
                        assert_equal [$slave mget k1 k2] [$peer_slave mget k1 k2]
                        assert_equal [$master mget k1 k2] [$slave mget k1 k2]
                    }
                    
                }
            }
        }
    }
}