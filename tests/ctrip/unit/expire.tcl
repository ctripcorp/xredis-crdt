proc log_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait { client index type log}  {
    set retry 100
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
        log_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}

start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set slave [srv 0 client]
        set slave_gid 2
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_log [srv 0 stdout]
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        set load_handle2 [start_write_load $master_host $master_port 3]
        $master setex k 1 v 
        after 1100
        assert_equal [$slave exists k] 0
        assert_equal [$slave get k]  ""
        stop_write_load $load_handle2

    }
}


start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    test {EXPIRE - set timeouts multiple times} {
        r set x foobar
        set v1 [r expire x 5]
        set v2 [r ttl x]
        set v3 [r expire x 10]
        set v4 [r ttl x]
        r expire x 2
        list $v1 $v2 $v3 $v4
    } {1 [45] 1 10}

    test {EXPIRE - It should be still possible to read 'x'} {
        r get x
    } {foobar}

    tags {"slow"} {
        test {EXPIRE - After 2.1 seconds the key should no longer be here} {
            after 2100
            list [r get x] [r exists x]
        } {{} 0}
    }

    # test {EXPIRE - write on expire should work} {
    #     r del x
    #     r lpush x foo
    #     r expire x 1000
    #     r lpush x bar
    #     r lrange x 0 -1
    # } {bar foo}

    test {EXPIREAT - Check for EXPIRE alike behavior} {
        r del x
        r set x foo
        r expireat x [expr [clock seconds]+15]
        r ttl x
    } {1[345]}

    test {SETEX - Set + Expire combo operation. Check for TTL} {
        r setex x 12 test
        r ttl x
    } {1[012]}

    test {SETEX - Check value} {
        r get x
    } {test}

    test {SETEX - Overwrite old key} {
        r setex y 1 foo
        r get y
    } {foo}

    tags {"slow"} {
        test {SETEX - Wait for the key to expire} {
            after 1100
            r get y
        } {}
    }

    test {SETEX - Wrong time parameter} {
        catch {r setex z -10 foo} e
        set _ $e
    } {*invalid expire*}

    test {PERSIST can undo an EXPIRE} {
        r set x foo
        r expire x 50
        list [r ttl x] [r persist x] [r ttl x] [r get x]
    } {50 1 -1 foo}

    test {PERSIST returns 0 against non existing or non volatile keys} {
        r set x foo
        list [r persist foo] [r persist nokeyatall]
    } {0 0}

    test {EXPIRE pricision is now the millisecond} {
        # This test is very likely to do a false positive if the
        # server is under pressure, so if it does not work give it a few more
        # chances.
        for {set j 0} {$j < 3} {incr j} {
            r del x
            r setex x 1 somevalue
            after 900
            set a [r get x]
            after 1100
            set b [r get x]
            if {$a eq {somevalue} && $b eq {}} break
        }
        list $a $b
    } {somevalue {}}

    test {PEXPIRE/PSETEX/PEXPIREAT can set sub-second expires} {
        # This test is very likely to do a false positive if the
        # server is under pressure, so if it does not work give it a few more
        # chances.
        for {set j 0} {$j < 3} {incr j} {
            r del x y z
            r psetex x 100 somevalue
            after 80
            set a [r get x]
            after 120
            set b [r get x]

            r set x somevalue
            r pexpire x 100
            after 80
            set c [r get x]
            after 120
            set d [r get x]

            r set x somevalue
            r pexpireat x [expr ([clock seconds]*1000)+100]
            after 80
            set e [r get x]
            after 120
            set f [r get x]

            if {$a eq {somevalue} && $b eq {} &&
                $c eq {somevalue} && $d eq {} &&
                $e eq {somevalue} && $f eq {}} break
        }
        list $a $b
    } {somevalue {}}

    test {TTL returns tiem to live in seconds} {
        r del x
        r setex x 10 somevalue
        set ttl [r ttl x]
        assert {$ttl > 8 && $ttl <= 10}
    }

    test {PTTL returns time to live in milliseconds} {
        r del x
        r setex x 1 somevalue
        set ttl [r pttl x]
        assert {$ttl > 900 && $ttl <= 1000}
    }

    test {TTL / PTTL return -1 if key has no expire} {
        r del x
        r set x hello
        list [r ttl x] [r pttl x]
    } {-1 -1}

    test {TTL / PTTL return -2 if key does not exit} {
        r del x
        list [r ttl x] [r pttl x]
    } {-2 -2}

    test {Redis should actively expire keys incrementally} {
        r flushdb
        r psetex key1 500 a
        r psetex key2 500 a
        r psetex key3 500 a
        set size1 [r dbsize]
        # Redis expires random keys ten times every second so we are
        # fairly sure that all the three keys should be evicted after
        # one second.
        after 1000
        set size2 [r dbsize]
        list $size1 $size2
    } {3 0}

    test {Redis should lazy expire keys} {
        r flushdb
        r debug set-active-expire 0
        r psetex key1 500 a
        r psetex key2 500 a
        r psetex key3 500 a
        set size1 [r dbsize]
        # Redis expires random keys ten times every second so we are
        # fairly sure that all the three keys should be evicted after
        # one second.
        after 1000
        set size2 [r dbsize]
        r mget key1 key2 key3
        set size3 [r dbsize]
        r debug set-active-expire 1
        list $size1 $size2 $size3
    } {3 3 0}

    test {EXPIRE should not resurrect keys (issue #1026)} {
        r debug set-active-expire 0
        r set foo bar
        r pexpire foo 500
        after 1000
        r expire foo 10
        r debug set-active-expire 1
        r exists foo
    } {0}

    test {5 keys in, 5 keys out} {
        r flushdb
        r set a c
        r expire a 5
        r set t c
        r set e c
        r set s c
        r set foo b
        lsort [r keys *]
    } {a e foo s t}

    test {EXPIRE with empty string as TTL should report an error} {
        r set foo bar
        catch {r expire foo ""} e
        set e
    } {*not an integer*}

    # test {SET - use EX/PX option, TTL should not be reseted after loadaof} {
    #     r config set appendonly yes
    #     r set foo bar EX 100
    #     after 2000
    #     r debug loadaof
    #     set ttl [r ttl foo]
    #     assert {$ttl <= 100 && $ttl > 90}

    #     r set foo bar PX 100000
    #     after 2000
    #     r debug loadaof
    #     set ttl [r ttl foo]
    #     assert {$ttl <= 98 && $ttl > 90}
    # }



    test "kv expire" {
        [lindex $peers 0] set key1 value;
        [lindex $peers 0] expire key1 4;
        after 2000
        assert_equal [[lindex $peers 0] get key1] value
        after 2100;
        assert_equal [[lindex $peers 0] get key1] {}
        
    }
     test "kv expireAt" {
        [lindex $peers 0] set key1 value;
        [lindex $peers 0] expireAt key1 100000;
        assert_equal [[lindex $peers 0] get key1] {}
     }
     test "kv expireAt2" {
         set time [clock seconds]
        [lindex $peers 0] set key1 value;
        [lindex $peers 0] expireAt key1 [incr time 4];
        after 2000
        assert_equal [[lindex $peers 0] get key1] value
        after 2000;
        assert_equal [[lindex $peers 0] get key1] {}
        assert_equal [[lindex $peers 0] ttl key1] -2
     }
    test "hash expire" {
        [lindex $peers 0] hset hash1 key value;
        [lindex $peers 0] expire hash1 4;
        after 2000
        assert_equal [[lindex $peers 0] hget hash1 key] value
        [lindex $peers 0] hset hash1 key1 value1;
        after 2000;
        assert_equal [[lindex $peers 0] hget hash1 key] {}
        assert_equal [[lindex $peers 0] hget hash1 key1] {}  
        assert_equal [[lindex $peers 0] ttl hash1 ] -2 
    }
    test "reset kv" {
        [lindex $peers 0] set key2 value;
        [lindex $peers 0] expire key2 4;
        after 2000
        assert_equal [[lindex $peers 0] get  key2] value
        [lindex $peers 0] expire key2 4;
        after 2000
        assert_equal [[lindex $peers 0] get key2] value
        after 2000
        assert_equal [[lindex $peers 0] get key2] {}
        
    }
    test "reset hash" {
        [lindex $peers 0] hset hash2 key value;
        [lindex $peers 0] expire hash2 4;
        after 2000
        assert_equal [[lindex $peers 0] hget hash2 key] value
        [lindex $peers 0] expire hash2 4;
        after 2000
        assert_equal [[lindex $peers 0] hget hash2 key] value
        after 2000
        assert_equal [[lindex $peers 0] hget hash2 key] {}
        after 10000
        assert_equal [[lindex $peers 0] ttl hash2] -2
    }
    test "persist" {
        [lindex $peers 0] set key3 value;
        [lindex $peers 0] expire key3 4;
        after 2000
        assert_equal [[lindex $peers 0] get key3] value
        [lindex $peers 0] persist key3;
        assert_equal [[lindex $peers 0] ttl key3] -1
        after 2000
        assert_equal [[lindex $peers 0] get key3] value
        after 2000
        assert_equal [[lindex $peers 0] get key3] value 
        
    }
    test "set after del" {
        [lindex $peers 0] set key4 value;
        [lindex $peers 0] expire key4 4;
        after 2000
        assert_equal [[lindex $peers 0] get key4] value
        [lindex $peers 0] del key4;
        assert_equal [[lindex $peers 0] ttl key4] -2
    }
    test "hset after del" {
        [lindex $peers 0] hset hash3 k v ;
        [lindex $peers 0] expire hash3 4;
        after 2000
        assert_equal [[lindex $peers 0] hget hash3 k] v
        [lindex $peers 0] del hash3;
        assert_equal [[lindex $peers 0] ttl hash3] -2
    }
    test "hset after hdel" {
        [lindex $peers 0] hset hash4 k v ;
        [lindex $peers 0] expire hash4 4;
        after 2000
        assert_equal [[lindex $peers 0] hget hash4 k] v
        [lindex $peers 0] hdel hash4 k;
        assert_equal [[lindex $peers 0] ttl hash4] -2
    }
    test "crdt.persist" {
        set time [clock milliseconds]
        [lindex $peers 0] "CRDT.SET" "k1" "value" "2" $time "2:1"
        [lindex $peers 0] "CRDT.persist" "k1" "3" "0"
        assert_equal [[lindex $peers 0] ttl k1] -1
        [lindex $peers 0] "CRDT.expire" "k1" "2" [incr time -1]  [incr time 100000000] "0"
        set ttl [[lindex $peers 0] ttl k1]
    }
    test "crdt.set" {
        set time [clock milliseconds]
        [lindex $peers 0] "CRDT.SET" "k2" "value" "2" $time "2:2;3:1" 1000
        [lindex $peers 0] "CRDT.expire" "k2" "3" [incr time -1] [incr time 100000000] "0"
        if {[[lindex $peers 0] ttl k2] > 1000 } {
            error "crdt.set  expire conflict error"
        }
    }
    test "crdt.del" {
        set time [clock milliseconds]
        [lindex $peers 0] "CRDT.DEL_REG" k4 "2" $time "2:101;3:100" "2:101;3:100"
        [lindex $peers 0] "CRDT.expire" k4 "3" [incr time -1] [incr time 2000000] "0"
        assert_equal [[lindex $peers 0] ttl k4] -2
    }
    
    test "crdt.del2" {
        set time [clock milliseconds]
        [lindex $peers 0] "CRDT.DEL_REG" k5 2 $time "2:111;1:110" "2:111;1:110"
        [lindex $peers 0] "CRDT.expire" k5 1 [incr time 100] [incr time 1000] "0"
        [lindex $peers 0] hset k5 key value
        after 2000
        assert_equal [[lindex $peers 0] hget k5 key] value
        # log_file_matches [lindex $peer_stdouts 0]
    }
    test "crdt.del3" {
        set size [[lindex $peers 0] expiresize]
        [lindex $peers 0] debug set-crdt-ovc 0
        set time [clock milliseconds]
        [lindex $peers 0] "CRDT.DEL_REG" k6 2 $time "2:121;1:120" "2:111;1:120"
        [lindex $peers 0] "CRDT.expire" k6 1 [incr time 100] [incr time 1000] "0"
        [lindex $peers 0] hset k6 key value
        after 5000
        assert_equal [[lindex $peers 0] hget k6 key] value
        # log_file_matches [lindex $peer_stdouts 0]
    }
    test "set nx" {
        [lindex $peers 0] SET not-exists-key value NX;
        assert_equal [[lindex $peers 0] get not-exists-key]  value;
        [lindex $peers 0] SET not-exists-key value1 NX;
        assert_equal [[lindex $peers 0] get not-exists-key]  value;
        [lindex $peers 0] del not-exists-key;
    }
    test "set xx" {
        [lindex $peers 0] SET exists-key value xx;
        assert_equal [[lindex $peers 0] get exists-key]  {};
        [lindex $peers 0] SET exists-key value;
        assert_equal [[lindex $peers 0] get exists-key]  value;
        [lindex $peers 0] SET exists-key value2 xx;
        assert_equal [[lindex $peers 0] get exists-key]  value2;
        [lindex $peers 0] del exists-key;
    }
    test "set ex" {
        [lindex $peers 0] SET ex-key value EX 4;
        after 2000
        set t [[lindex $peers 0] ttl ex-key]
        if {$t <= 0} {
            error "set ex function error"
        }  
        assert_equal [[lindex $peers 0] get ex-key] value
        after 2500;
        assert_equal [[lindex $peers 0] ttl ex-key] -2
        assert_equal [[lindex $peers 0] get ex-key] {}
    }
    
    test "set ex after set" {
        [lindex $peers 0] SET ex-key2 value EX 4;
        after 2000
        assert_equal [[lindex $peers 0] get ex-key2] value
        [lindex $peers 0] set ex-key2 value2
        after 2500;
        assert_equal [[lindex $peers 0] ttl ex-key2] -1
        assert_equal [[lindex $peers 0] get ex-key2] value2
    }
    test "setex" {
        [lindex $peers 0] SETex ex-key3   4 value;
        after 2000
        set t [[lindex $peers 0] ttl ex-key3]
        if {$t <= 0} {
            error "set ex function error"
        }  
        assert_equal [[lindex $peers 0] get ex-key3] value
        after 2500;
        assert_equal [[lindex $peers 0] ttl ex-key3] -2
        assert_equal [[lindex $peers 0] get ex-key3] {}
    }
    test "setex after set" {
        [lindex $peers 0] SETex ex-key4   4 value;
        after 2000
        assert_equal [[lindex $peers 0] get ex-key4] value
        [lindex $peers 0] set ex-key4 value2
        after 2500;
        assert_equal [[lindex $peers 0] ttl ex-key4] -1
        assert_equal [[lindex $peers 0] get ex-key4] value2
    }
    test "set px" {
        [lindex $peers 0] SET px-key value PX 4000;
        after 2000
        assert_equal [[lindex $peers 0] get px-key] value
        after 2000;
        assert_equal [[lindex $peers 0] ttl px-key] -2
        assert_equal [[lindex $peers 0] get px-key] {}
    }
    test "set px after set" {
        [lindex $peers 0] SET px-key2 value px 4000;
        after 2000
        assert_equal [[lindex $peers 0] get px-key2] value
        [lindex $peers 0] set px-key2 value2
        after 2000;
        assert_equal [[lindex $peers 0] ttl px-key2] -1
        assert_equal [[lindex $peers 0] get px-key2] value2
    }

    


    
    start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1 local-clock 10000} module {crdt.so}} {

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2 
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 1] crdt.set set_vcu vcu 2 1000 2:100000
        [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0] 
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        
        wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
        wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
        test "k expire" {
            set c [crdt_stats [lindex $peers 1] crdt_non_type_conflict]
            [lindex $peers 0] set pk1 value
            [lindex $peers 0] expire pk1 4
            after 2000
            assert_equal [[lindex $peers 1] get pk1] value
            after 2100
            assert_equal [[lindex $peers 1] get pk1] {}            
            assert_equal [[lindex $peers 0] ttl pk1] -2
            assert_equal [[lindex $peers 1] ttl pk1] -2
            assert_equal [[lindex $peers 0] get pk1] {}
        }
        test "peer persist" {
            [lindex $peers 0] set pk2 value;
            [lindex $peers 0] expire pk2 10;
            after 2000
            assert_equal [[lindex $peers 1] get pk2] value
            [lindex $peers 0] persist pk2
            after 1000
            assert_equal [[lindex $peers 0] ttl pk2] -1
            assert_equal [[lindex $peers 1] ttl pk2] -1
            after 2000
            assert_equal [[lindex $peers 0] get pk2] value
        }
        test "reset expire" {
            [lindex $peers 0] set pk3 value
            [lindex $peers 0] expire pk3 10000
            after 500
            [lindex $peers 1] expire pk3 20000
            after 500
            set t [[lindex $peers 0] ttl pk3]
            if {$t < 10000} {
                error "expire no reset"
            }
        }
        
        test "peer del kv expire" {
            [lindex $peers 0] set pk4 value;
            [lindex $peers 0] expire pk4 10;
            after 1000
            set t [[lindex $peers 1] ttl pk4]
            if {$t < 0} {
                error "peer expire error"
            }
            [lindex $peers 0] del pk4;
            assert_equal [[lindex $peers 0] ttl pk4] -2;
            after 1000
            assert_equal [[lindex $peers 1] ttl pk4] -2;
            # assert_equal [[lindex $peers 1] crdt.ttl pk4] [[lindex $peers 0] crdt.ttl pk4]
        }
        test "peer set ex" {
            [lindex $peers 0] set pk5 value ex 10
            after 1000
            set t [[lindex $peers 1] ttl pk5]
            if {$t < 0} {
                error "peer set ex error"
            }
            [lindex $peers 0] set pk5 value2
            assert_equal [[lindex $peers 0] ttl pk5] -1;
            assert_equal [[lindex $peers 0] get pk5] value2;
            after 200
            assert_equal [[lindex $peers 1] ttl pk5] -1;
            assert_equal [[lindex $peers 1] get pk5] value2;
        }
        test "peer set ex2" {
            [lindex $peers 0] set pk6 value ex 10
            after 1000
            set t [[lindex $peers 1] ttl pk6]
            if {$t < 0} {
                error "peer set ex error"
            }
            [lindex $peers 1] set pk6 value2
            assert_equal [[lindex $peers 1] ttl pk6] -1;
            assert_equal [[lindex $peers 1] get pk6] value2;
            after 200
            assert_equal [[lindex $peers 0] ttl pk6] -1;
            assert_equal [[lindex $peers 0] get pk6] value2;
            
        }
        
        test "peer set ex3" {
            [lindex $peers 0] set pk7 value ex 10
            after 1000
            set t [[lindex $peers 1] ttl pk7]
            if {$t < 0} {
                error "peer set ex error"
            }
            [lindex $peers 1] set pk7 value2 ex 100
            assert_equal [[lindex $peers 1] get pk7] value2;
            after 200
            # assert_equal [[lindex $peers 1] crdt.ttl pk7] [[lindex $peers 0] crdt.ttl pk7];
            assert_equal [[lindex $peers 0] get pk7] value2;
            if {[[lindex $peers 1] ttl pk7] < 10} {
                error "reset ex error"
            }
            
        }
        test "peer del kv expire2" {
            [lindex $peers 0] set pk8 value;
            [lindex $peers 0] expire pk8 10;
            after 1000
            set t [[lindex $peers 1] ttl pk8]
            if {$t < 0} {
                error "peer expire error"
            }
            [lindex $peers 1] del pk8;
            assert_equal [[lindex $peers 1] ttl pk8] -2;
            after 1000
            assert_equal [[lindex $peers 0] ttl pk8] -2;
            # assert_equal [[lindex $peers 0] crdt.ttl pk8] [[lindex $peers 0] crdt.ttl pk8]
        }
        test "peer set kv after persist" {
            [lindex $peers 0] set pk9 value ex 100;
            after 1000
            assert_equal [[lindex $peers 1] get pk9] value;
            set t [[lindex $peers 1] ttl pk9]
            if {$t < 0} {
                error "peer expire error"
            }
            [lindex $peers 1] persist pk9;
            # assert_equal [[lindex $peers 1] ttl pk9] -1;
            # assert_equal [[lindex $peers 1] get pk9] value;
            after 1000
            assert_equal [[lindex $peers 0] ttl pk9] -1;
            # assert_equal [[lindex $peers 0] crdt.ttl pk9] [[lindex $peers 0] crdt.ttl pk9]
            assert_equal [[lindex $peers 0] get pk9] value;
        }
        test "peer setex" {
            [lindex $peers 0] setex pex 10 value 
            after 1000
            set t [[lindex $peers 1] ttl pex]
            if {$t < 0} {
                error "peer set ex error"
            }
            assert_equal [[lindex $peers 1] get pex] value;
            [lindex $peers 0] set pex value2
            assert_equal [[lindex $peers 0] ttl pex] -1;
            assert_equal [[lindex $peers 0] get pex] value2;
            after 200
            assert_equal [[lindex $peers 1] ttl pex] -1;
            assert_equal [[lindex $peers 1] get pex] value2;
        }
        
        
        
        test "peer del hash expire" {
            [lindex $peers 0] hset ph1 key value;
            [lindex $peers 0] expire ph1 10;
            [lindex $peers 0] del ph1;
            assert_equal [[lindex $peers 0] ttl ph1] -2;
            after 1000
            assert_equal [[lindex $peers 1] ttl ph1] -2;
            # assert_equal [[lindex $peers 1] crdt.ttl ph1] [[lindex $peers 0] crdt.ttl ph1]
        }
        test "peer hdel hash expire" {
            [lindex $peers 0] hset ph2 key value;
            [lindex $peers 0] expire ph2 10;
            [lindex $peers 0] hdel ph2 key;
            assert_equal [[lindex $peers 0] ttl ph2] -2
            # after 1000
            # assert_equal [[lindex $peers 1] crdt.ttl ph2] [[lindex $peers 0] crdt.ttl ph2]
        }
        
    }

}


start_server {tags {"full"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2 
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        test "peerof expire" {
            [lindex $peers 0] set key1 value 
            [lindex $peers 0] expire key1 1000 
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
            assert_equal [[lindex $peers 1] get key1] value;
            # assert_equal [[lindex $peers 1] crdt.ttl key1] [[lindex $peers 0] crdt.ttl key1];
            [lindex $peers 0] expire key1 4
            [lindex $peers 1] del key1
            after 4000
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
        }
        test "peerof expire2" {
            [lindex $peers 0] set key2 value1
            after 100
            [lindex $peers 1] set key2 value2
            [lindex $peers 0] expire key2 1000
            after 100 
            [lindex $peers 1] expire key2 2000 
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
            assert_equal [[lindex $peers 0] get key2] value2
            assert_equal [[lindex $peers 1] get key2] value2
            assert_equal [[lindex $peers 0] ttl key2] [[lindex $peers 1] ttl key2] 
            set t [[lindex $peers 0] ttl key2]
            if {$t < 1000} {
                error "err"
            }
            [lindex $peers 0] expire key2 4
            after 1000
            [lindex $peers 1] set key2 v2
            assert_equal [[lindex $peers 1] get key2] v2
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
            [lindex $peers 0] peerof [lindex $peer_gids 1] no one
        }
        
        test "peerof expire tombstone" {
            [lindex $peers 0] set key3 value1
            after 100
            [lindex $peers 1] set key3 value2
            [lindex $peers 0] expire key3 1000
            after 100 
            [lindex $peers 1] expire key3 2000 
            set time [clock milliseconds]
            [lindex $peers 0] "CRDT.SET" "key3" "value3" "1" $time  "1:999;2:999"  "-1"
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
             wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
            assert_equal [[lindex $peers 0] get key3] value3
            assert_equal [[lindex $peers 1] get key3] value3
            # log_file_matches [lindex $peer_stdouts 1]
            assert_equal [[lindex $peers 0] ttl key3] [[lindex $peers 1] ttl key3] 
            set t [[lindex $peers 0] ttl key3]
            assert {$t > 1000} 
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
            [lindex $peers 0] peerof [lindex $peer_gids 1] no one
        }

        test "peerof ex nx" {
            [lindex $peers 0] set key4 value1 ex 1000
            after 100
            [lindex $peers 1] set key4 value2 px 2000000
            after 100 
            [lindex $peers 0] set key4 value3
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
             wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
            
            assert_equal [[lindex $peers 0] get key4] value3
            assert_equal [[lindex $peers 1] get key4] value3
            assert_equal [[lindex $peers 0] ttl key4] [[lindex $peers 1] ttl key4] 
            set t [[lindex $peers 0] ttl key4]
            # log_file_matches [lindex $peer_stdouts 0]
            assert {$t > 1000} 
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
            [lindex $peers 0] peerof [lindex $peer_gids 1] no one
        }
    }

}

proc get_expired_keys {redis command} {
    set info [$redis $command stats]
    set regstr [format "\r\n%s:(.*?)\r\n" "expired_keys"]
    regexp $regstr $info match value 
    set _ $value
} 
start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    
    test "setex" {
        set before_expired_keys [get_expired_keys $master info]
        set before_crdt_expired_keys [get_expired_keys $master crdt.info]
        $master setex k 1 v 
        after 1100
        assert_equal [$master get k] ""
        set after_expired_keys [get_expired_keys $master info]
        set after_crdt_expired_keys [get_expired_keys $master crdt.info]
        assert_equal [expr {$after_expired_keys - $before_expired_keys}] 1
        assert_equal [expr {$after_crdt_expired_keys - $before_crdt_expired_keys}] 1
    }

    test "expire" {
        set before_expired_keys [get_expired_keys $master info]
        set before_crdt_expired_keys [get_expired_keys $master crdt.info]
        $master setex k 1 v 
        $master expire k 1
        after 1100
        assert_equal [$master get k] ""
        set after_expired_keys [get_expired_keys $master info]
        set after_crdt_expired_keys [get_expired_keys $master crdt.info]
        assert_equal [expr {$after_expired_keys - $before_expired_keys}] 1
        assert_equal [expr {$after_crdt_expired_keys - $before_crdt_expired_keys}] 1
    }
}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set peer1 [srv 0 client]
    set peer1_gid 1
    set peer1_host [srv 0 host]
    set peer1_port [srv 0 port]
    $peer1 config set non-last-write-delay-expire-time 500
    assert_equal [$peer1 config get non-last-write-delay-expire-time] "non-last-write-delay-expire-time 500"
    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_gid 2
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        $peer2 config set non-last-write-delay-expire-time 500
        assert_equal [$peer2 config get non-last-write-delay-expire-time] "non-last-write-delay-expire-time 500"
        
        $peer1 peerof $peer2_gid $peer2_host $peer2_port
        $peer2 peerof $peer1_gid $peer1_host $peer1_port

        wait_for_peer_sync $peer1 
        wait_for_peer_sync $peer2

        test "miss1" {
            test "string miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 set key v 
                $peer1 expire key 2
                wait_for_condition 21 100 {
                    [$peer1 get key] == {}
                } else {
                    fail "string expire error"
                }
                $peer1 set key v1
                after 500
                assert_equal [$peer1 get key] v1
                assert_equal [$peer2 get key] v1 
            }

            test "string2 miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 setex key 2 v 
                wait_for_condition 21 100 {
                    [$peer1 get key] == {}
                } else {
                    fail "string2 expire error"
                }
                assert_equal [$peer1 get key] {}
                $peer1 set key v1
                after 500
                assert_equal [$peer1 get key] v1
                assert_equal [$peer2 get key] v1 
            }

            test "hash miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 hset key k v 
                $peer1 expire key 2
                wait_for_condition 21 100 {
                    [$peer1 hget key k] == {}
                } else {
                    fail "hash expire error"
                }
                $peer1 hset key k v1 
                after 500
                assert_equal [$peer1 hget key k] v1 
                assert_equal [$peer2 hget key k] v1 
            }

            test "set miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 sadd key k  
                $peer1 expire key 2
                wait_for_condition 21 100 {
                    [$peer1 SISMEMBER key k] == 0
                } else {
                    fail "set expire error"
                }
                $peer1 sadd key k1
                after 500
                assert_equal [$peer1 SISMEMBER key k1] 1
                assert_equal [$peer2 SISMEMBER key k1] 1
            }

            test "zset miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 zadd key 10 k  
                $peer1 expire key 2
                wait_for_condition 21 100 {
                    [$peer1 zscore key k] == {}
                } else {
                    fail "zset expire error"
                }
                $peer1 zadd key 10 k1
                after 500
                assert_equal [$peer1 zscore key k1] 10
                assert_equal [$peer2 zscore key k1] 10
            }

            test "count miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 set key 10  
                $peer1 expire key 2
                wait_for_condition 21 100 {
                    [$peer1 get key] == {}
                } else {
                    fail "count expire error"
                }
                $peer1 set key 20
                after 500
                assert_equal [$peer1 get key] 20
                assert_equal [$peer2 get key] 20
            }

            test "count2 miss data" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 setex key 2 10  
                wait_for_condition 21 100 {
                    [$peer1 get key] == {}
                } else {
                    fail "count2 expire error"
                }
                $peer1 set key 20
                after 500
                assert_equal [$peer1 get key] 20
                assert_equal [$peer2 get key] 20
            }
        }

        test "expire and add" {
            test "string expire and add" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 set key v 
                $peer1 expire key 2
                $peer1 peerof $peer2_gid 127.0.0.1 1 
                $peer2 peerof $peer1_gid 127.0.0.1 1
                after 2000
                $peer2 set key v1 
                assert_equal [$peer1 get key] {}
                $peer1 peerof $peer2_gid $peer2_host $peer2_port
                $peer2 peerof $peer1_gid $peer1_host $peer1_port
                wait_for_peer_sync $peer1 
                wait_for_peer_sync $peer2 
                assert_equal [$peer1 get key] v1
            }

            test "count expire and add" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 incr key 
                $peer1 expire key 2
                $peer1 peerof $peer2_gid 127.0.0.1 1 
                $peer2 peerof $peer1_gid 127.0.0.1 1
                after 2000
                $peer2 incrby key 3 
                assert_equal [$peer1 get key] {}
                $peer1 peerof $peer2_gid $peer2_host $peer2_port
                $peer2 peerof $peer1_gid $peer1_host $peer1_port
                wait_for_peer_sync $peer1 
                wait_for_peer_sync $peer2 
                assert_equal [$peer1 get key] 3
            }

            test "hash expire and add" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 hset key k1 v1 
                $peer1 expire key 2
                $peer1 peerof $peer2_gid 127.0.0.1 1 
                $peer2 peerof $peer1_gid 127.0.0.1 1
                after 2000
                $peer2 hset key k2 v2 
                assert_equal [$peer1 hget key k1] {}
                assert_equal [$peer1 hget key k2] {}
                $peer1 peerof $peer2_gid $peer2_host $peer2_port
                $peer2 peerof $peer1_gid $peer1_host $peer1_port
                wait_for_peer_sync $peer1 
                wait_for_peer_sync $peer2 
                assert_equal [$peer1 hget key k2] v2
            }

            test "set expire and add" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 sadd key k1  
                $peer1 expire key 2
                $peer1 peerof $peer2_gid 127.0.0.1 1 
                $peer2 peerof $peer1_gid 127.0.0.1 1
                after 2000
                $peer2 sadd key k2  
                assert_equal [$peer1 SISMEMBER key k1] 0
                assert_equal [$peer1 SISMEMBER key k2] 0
                $peer1 peerof $peer2_gid $peer2_host $peer2_port
                $peer2 peerof $peer1_gid $peer1_host $peer1_port
                wait_for_peer_sync $peer1 
                wait_for_peer_sync $peer2 
                assert_equal [$peer1 SISMEMBER key k2] 1
            }

            test "zset expire and add" {
                $peer1 del key 
                after 500
                assert_equal [$peer1 type key] none
                assert_equal [$peer2 type key] none
                $peer1 zadd key 10 k1  
                $peer1 expire key 2
                $peer1 peerof $peer2_gid 127.0.0.1 1 
                $peer2 peerof $peer1_gid 127.0.0.1 1
                after 2000
                $peer2 zadd key 20 k2  
                assert_equal [$peer1 zscore key k1] {}
                assert_equal [$peer1 zscore key k2] {}
                $peer1 peerof $peer2_gid $peer2_host $peer2_port
                $peer2 peerof $peer1_gid $peer1_host $peer1_port
                wait_for_peer_sync $peer1 
                wait_for_peer_sync $peer2 
                assert_equal [$peer1 zscore key k2] 20
            }
        }

    }
}


start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]

        test "expire" {
            $master peerof $peer_gid $peer_host $peer_port
            $peer peerof $master_gid $master_host $master_port

            wait_for_peer_sync $master 
            wait_for_peer_sync $peer 

            $master set k v 
            $master expire  k 1000
            $master expire  k 100
            wait_for_condition 10 100 {
                [$peer get k] == "v"
            } else {
                fail "sync fail"
            }
            assert {[$peer ttl k] > 100}
        }

        test "PERSIST" {
            $master PERSIST asdasdasd 
        }
    }
}