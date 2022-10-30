

proc start_bg_hash_data {host port db ops} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/bg_hash_data.tcl $host $port $db $ops &
}

proc stop_bg_hash_data {handle} {
    catch {exec /bin/kill -9 $handle}
}

proc encode_binary_str {str size} {
    append type "H" $size
    binary format $type $str
}
proc decode_binary_str {binary_str size} {
    append type "H" $size
    binary scan $binary_str $type result
    return $result
}
start_server {tags {"crdt-hash"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    proc params_error {script} {
        catch {[uplevel 1 $script ]} result opts
        # puts $result
        assert_match "*ERR wrong number of arguments for '*' command*" $result
    }
    test "params_error" {
        params_error {
            $master hset k 
        }
        params_error {
            $master hdel k 
        }
        params_error {
            $master hscan k 
        }
        params_error {
            $master hmset k 
        }
        params_error {
            $master hget k 
        }
        params_error {
            $master hmget k 
        }
        params_error {
            $master del 
        }
        params_error {
            $master HGETALL
        }
        params_error {
            $master hkeys
        }
        params_error {
            $master hvals
        }
        params_error {
            $master hlen
        }
        params_error {
            $master hscan
        }
    }
    proc type_error {script} {
        catch {[uplevel 1 $script ]} result opts
        assert_match "*WRONGTYPE Operation against a key holding the wrong kind of value*" $result
    }
    test "type_error" {
        r set hash a 
        type_error {
            $master hset hash k v 
        }
        type_error {
            $master hdel hash k v 
        }
        type_error {
            $master hscan  hash 0
        }
        type_error {
            $master hmset hash k v k1 v2 
        }
        type_error {
            $master hget hash k 
        }
        type_error {
            $master hmget hash k 
        }
        type_error {
            $master hgetall hash  
        }
        type_error {
            $master hkeys hash  
        }
        type_error {
            $master hvals hash  
        }
        type_error {
            $master hscan hash 0  
        }
        type_error {
            $master hlen hash  
        }
        assert_equal [r get hash] a 
    }
}

start_server {tags {"crdt-hash"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {

    set redis_host [srv 0 host]
    set redis_port [srv 0 port]

    test {"[crdt_hash.tcl]basic hset and hget"} {
        r hset k-hash f1 v1
        set info [r crdt.dataInfo k-hash]
        # puts [lindex $info 0]
        assert_equal [string match  "*type: lww_hash,  last-vc: 1:1*" [lindex $info 0]] 1
        r hget k-hash f1
    } {v1}

    test {"[crdt_hash.tcl]hset and hget an empty item"} {
        r hset k-hash-1 k1 {}
        r hget k-hash-1 k1
    } {}

    test {"[crdt_hash.tcl]Very big payload in HGET/HMSET"} {
        set buf [string repeat "abcd" 1000000]
        r hmset k-hash-2 field $buf
        r hget k-hash-2 field
    } [string repeat "abcd" 1000000]

    test {"over write key"} {
        r hmset k-hash-3 f v f1 v1 f2 v2
        r hset k-hash-3 f3 v2
        r hset k-hash-3 f v2
        r hget k-hash-3 f
    } {v2}

    test {"[crdt_hash.tcl]basic hdel"} {
        r hmset k-hash-4 f v f1 v1 f2 v2
        r hdel k-hash-4 f f1
        r hget k-hash-4 f1
    } {}


    test {"[crdt_hash.tcl]big hash map"} {
        set load_handle0 [start_bg_hash_data $redis_host $redis_port 9 100000]
        after 1000
        stop_bg_hash_data $load_handle0
    }

    test {"[crdt_hash.tcl]big hash map - 2"} {
        set load_handle0 [start_write_load $redis_host $redis_port 3]
        set load_handle1 [start_write_load $redis_host $redis_port 5]
        after 1000
        stop_write_load $load_handle0
        stop_write_load $load_handle1
    }
    test {"[crdt_hash.tcl]binary hash map "} {
        r hset hash binary [encode_binary_str abcdef 6]
        decode_binary_str [ r hget hash binary ] 6
    } {abcdef}
}

start_server {tags {"crdt-hash-more"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {

    set redis_host [srv 0 host]
    set redis_port [srv 0 port]

    test {"[crdt-hash.tcl]Test Concurrent-1"} {
        r CRDT.HSET k-hash-1 1 [clock milliseconds] "1:100" 4 f v f1 v1
        after 1
        r CRDT.HSET k-hash-1 1 [clock milliseconds] "1:101" 4 f v2
        set info [r crdt.dataInfo k-hash-1]
        assert_equal [string match  "*type: lww_hash,  last-vc: 1:101*" [lindex $info 0]] 1
        r hget k-hash-1 f
    } {v2}

    test {"[crdt_hash.tcl]Test Concurrent-2"} {
        r CRDT.HSET k-hash-2 1 [clock milliseconds] "1:101;2:100" 6 f v f1 v1 f2 v2
        r CRDT.HSET k-hash-2 2 [expr [clock milliseconds] - 2000] "1:101;2:101" 2 f1 v3
        r hget k-hash-2 f1
    } {v3}

    test {"[crdt_hash.tcl]Test Concurrent-3"} {
        r CRDT.HSET k-hash-3 1 [clock milliseconds] "1:101;2:100" 6 f v f1 v1 f2 v2
        r CRDT.HSET k-hash-3 2 [expr [clock milliseconds] + 2000] "1:100;2:101" 2 f1 v3
        r hget k-hash-3 f1
    } {v3}


    # del concurrent conflict with set, set wins
    test {"[crdt_hash.tcl]Test Concurrent DEL-1"} {
        r CRDT.HSET k-hash-5 1 [clock milliseconds] "1:101;2:100" 6 f v f1 v1 f2 v2
        after 1
        r CRDT.DEL_HASH k-hash-5 2 [expr [clock milliseconds] - 2000] "1:100;2:100" "1:99:2:100"
        r hget k-hash-5 f
    } {v}

    # del concurrent with del
    test {"[crdt_hash.tcl]Test Concurrent DEL-2"} {
        r CRDT.HSET k-hash-6 1 [clock milliseconds] "1:100;2:100" 6 f v f1 v1 f2 v2
        r CRDT.DEL_HASH k-hash-6 2 [clock milliseconds] "1:101;2:101" "1:101;2:100"
        r CRDT.DEL_HASH k-hash-6 1 [clock milliseconds] "1:101;2:100" "1:101;2:100"
        set info [r crdt.dataInfo k-hash-6]
        assert_equal [string match  "type: lww_hash_tombstone,  last-vc: 1:101;2:101, max-del-gid: 2, max-del-time: *, max-del-vc: 1:101;2:101\n" [lindex $info 0]] 1
        # puts $info
        r hget k-hash-6 f
    } {}

    # del concurrent with del
    # test {"[crdt_hash.tcl]Test Concurrent Tombstone"} {
    #     set time [clock milliseconds]
    #     r CRDT.HSET k-hash-7 1 $time "1:110;2:110" 6 f v f1 v1 f2 v2
    #     r CRDT.DEL_HASH k-hash-7 1 $time "1:111;2:111" "1:101;2:100"
    #     r CRDT.HSET k-hash-7 2 $time "1:109;2:112" 4 f v f3 v3 
    #     assert_equal [r hget k-hash-7 f] v
    #     r hget k-hash-7 f3
    # } {v3}

    test {"[crdt_hash.tcl]crdt hash lot"} {
        set hash_handle0 [start_crdt_hash_load $redis_host $redis_port 3]
        set hash_handle1 [start_crdt_hash_load $redis_host $redis_port 5]
        after 1000
        stop_crdt_hash_load $hash_handle0
        stop_crdt_hash_load $hash_handle1
    }

    # del normal
    test {"[crdt_hash.tcl]Test Normal DEL"} {
        r CRDT.HSET k-hash-7 1 [clock milliseconds] "1:200;2:200" 6 f v f1 v1 f2 v2
        r del k-hash-7
        r hget k-hash-7 f
    } {}

    # hdel normal
    test {"[crdt_hash.tcl]Test Normal H-DEL"} {
        r CRDT.HSET k-hash-8 1 [clock milliseconds] "1:201;2:200" 6 f v f1 v1 f2 v2
        r hdel k-hash-8 f
        r hget k-hash-8 f
    } {}
    # hdel binary
    test {"[crdt_hash.tcl]Test Normal H-DEL-2"} {
        r CRDT.HSET k-hash-9 1 [clock milliseconds] "1:202;2:200" 6 f [encode_binary_str abcdef 6] f1 v1 f2 v2
        r hdel k-hash-9 f
        r hget k-hash-9 f
    } {}
    test {"[crdt_hash.tcl]Test Normal CRDT-HGET"} {
        r crdt.hget k-hash-10 field 
    } {}
    test {"[crdt_hash.tcl]Test Normal CRDT-HGET-2"} {
        set time [clock milliseconds]
        r hset k-hash-10 field value
        set result [r crdt.hget k-hash-10 field]
        assert {[lindex $result 0] == {value}}
        assert {[lindex $result 1] == {1}}
        assert {[lindex $result 2] >= $time}
        r hdel k-hash-10 field 
        assert {[r crdt.hget k-hash-10 field] == {}}
    } 
    test {"[crdt_hash.tcl]Test Normal CRDT-HGET-3"} {
        set time [clock milliseconds]
        r CRDT.HSET k-hash-11 1 $time "1:203;2:200" 6 f v f1 v1 
        set result [r crdt.hget k-hash-11 f]
        assert {[lindex $result 0] == {v}}
        assert {[lindex $result 1] == {1}}
        assert {[lindex $result 2] == $time}
        assert {[lindex $result 3] == {1:203;2:200}}
        set result1 [r crdt.hget k-hash-11 f1]
        assert {[lindex $result1 0] == {v1}}
        assert {[lindex $result1 1] == {1}}
        assert {[lindex $result1 2] == $time}
        assert {[lindex $result1 3] == {1:203;2:200}}
        r hdel k-hash-11 f
        assert {[r crdt.hget k-hash-11 f] == {}} 
        assert {[llength [r crdt.hget k-hash-11 f1]] == 4} 
        r del k-hash-11
        assert {[r crdt.hget k-hash-11 f1] == {}} 
    }

}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set slaves {}
    $master config set repl-diskless-sync-delay 1

    # set load_handle0 [start_write_load $master_host $master_port 3]
    # set load_handle1 [start_write_load $master_host $master_port 5]

    $master hmset k-hash-101 f v

    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        lappend slaves [srv 0 client]

        # stop_write_load $load_handle0
        # stop_write_load $load_handle1
        # after 1000
        test "Connect multiple slaves at the same time " {
            # Send SLAVEOF commands to slaves
            [lindex $slaves 0] slaveof $master_host $master_port

            # Wait for all the three slaves to reach the "online"
            # state from the POV of the master.
            set retry 500
            while {$retry} {
                set info [r -1 info]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion:Slaves not correctly synchronized"
            }
        }

        # Make sure that slaves and master have same
        # number of keys
        wait_for_condition 500 100 {
            [$master dbsize] == [[lindex $slaves 0] dbsize]
        } else {
            fail "Different number of keys between masted and slave after too long time."
        }

        test "master-set-slave-get" {
            $master hmset k-hash-10 f v f1 v1 f2 v2 f3 v3 f4 v4
            after 100
            [lindex $slaves 0] hget k-hash-10 f4
        } {v4}
        test "master-set-slave-crdt.hget" {
            $master hmset k-hash-10 f v f1 v1 f2 v2 f3 v3 f4 v4
            after 100
            set result [[lindex $slaves 0] crdt.hget k-hash-10 f4]
            lindex $result 0
        } {v4}

        test "huge hset/hmset between master and slave" {
            set load_handle2 [start_write_load $master_host $master_port 3]
            set load_handle3 [start_write_load $master_host $master_port 5]
            after 100
            stop_write_load $load_handle2
            stop_write_load $load_handle3
        }

        # Make sure that slaves and master have same
        # number of keys
        wait_for_condition 500 100 {
            [$master dbsize] == [[lindex $slaves 0] dbsize]
        } else {
            fail "Different number of keys between masted and slave after too long time."
        }
    }
}


start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids 1

    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
    
        
        test "full-sync-hash-merge test1" {
            [lindex $peers 0] hset key field v0
            after 10
            [lindex $peers 1] hset key field v1
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            # [lindex $peers 1] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
            set retry 50
            while {$retry} {
                set info [[lindex $peers 0] crdt.info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion: Master-Slave not correctly synchronized"
            }
            assert {[[lindex $peers 1] hget key field] eq {v1} }
            assert {[[lindex $peers 0] hget key field] eq {v0} }
            # [lindex $peers 1] slaveof no one
            
        }
        test "full-sync-hash-merge test2" {
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one  
            after 100          
            [lindex $peers 0] hset key field v2
            after 100
            [lindex $peers 1] hset key field v3
            assert {[[lindex $peers 0] hget key field] eq {v2}}
            assert {[[lindex $peers 1] hget key field] eq {v3}}
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            set retry 50
            while {$retry} {
                set info [[lindex $peers 1] crdt.info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion: Master-Slave not correctly synchronized"
            }
            assert {[[lindex $peers 0] hget key field] eq {v3} }
            assert {[[lindex $peers 1] hget key field] eq {v3} }            
        }
        test "full-sync-hash-merge test3" {
            [lindex $peers 0] peerof [lindex $peer_gids 1] no one
            after 100
            [lindex $peers 0] hset key field v4
            after 100
            [lindex $peers 1] hset key field v5
            assert {[[lindex $peers 0] hget key field] eq {v4}}
            assert {[[lindex $peers 1] hget key field] eq {v5}}
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            set retry 50
            while {$retry} {
                set info [[lindex $peers 0] crdt.info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion: Master-Slave not correctly synchronized"
            }
            set retry 50
            while {$retry} {
                set info [[lindex $peers 1] crdt.info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion: Master-Slave not correctly synchronized"
            }
            assert {[[lindex $peers 0] hget key field] eq {v5} }
            assert {[[lindex $peers 1] hget key field] eq {v5} }
            [lindex $peers 0] peerof [lindex $peer_gids 1] no one
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
            [lindex $peers 0] hset key field v0
            [lindex $peers 1] hset key field v1
            assert {[[lindex $peers 0] hget key field] eq {v0}}
            assert {[[lindex $peers 1] hget key field] eq {v1}}
        }
    }
}




start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        start_server {config {crdt.conf} overrides {crdt-gid 3 repl-diskless-sync-delay 1} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 3
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            test "merge" {
                [lindex $peers 0] hset key field v1
                [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                set retry 50
                while {$retry} {
                    set info [[lindex $peers 0] crdt.info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    error "assertion: Master-Slave not correctly synchronized"
                }
                [lindex $peers 1] hdel key field
                [lindex $peers 1] hset key field1 v1
                [lindex $peers 2] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                set retry 50
                while {$retry} {
                    set info [[lindex $peers 1] crdt.info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    error "assertion: Master-Slave not correctly synchronized"
                }
                after 3000
                assert {[[lindex $peers 2] hget key field] eq {}}
                assert {[[lindex $peers 2] hget key field1] eq {v1}}
            }
        }
    }
    
}


