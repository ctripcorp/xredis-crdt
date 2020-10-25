proc log_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait { client index type log}  {
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
        log_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
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
    # test "kv expire" {
    #     [lindex $peers 0] set key1 value;
    #     [lindex $peers 0] expire key1 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key1] value
    #     after 2100;
    #     assert_equal [[lindex $peers 0] get key1] {}
        
    # }
    #  test "kv expireAt" {
    #     [lindex $peers 0] set key1 value;
    #     [lindex $peers 0] expireAt key1 100000;
    #     assert_equal [[lindex $peers 0] get key1] {}
    #  }
    #  test "kv expireAt2" {
    #      set time [clock milliseconds]
    #     [lindex $peers 0] set key1 value;
    #     [lindex $peers 0] expireAt key1 [incr time 4000];
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key1] value
    #     after 2000;
    #     assert_equal [[lindex $peers 0] get key1] {}
    #     assert_equal [[lindex $peers 0] ttl key1] -2
    #  }
    # test "hash expire" {
    #     [lindex $peers 0] hset hash1 key value;
    #     [lindex $peers 0] expire hash1 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget hash1 key] value
    #     [lindex $peers 0] hset hash1 key1 value1;
    #     after 2000;
    #     assert_equal [[lindex $peers 0] hget hash1 key] {}
    #     assert_equal [[lindex $peers 0] hget hash1 key1] {}  
    #     assert_equal [[lindex $peers 0] ttl hash1 ] -2 
    # }
    # test "reset kv" {
    #     [lindex $peers 0] set key2 value;
    #     [lindex $peers 0] expire key2 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get  key2] value
    #     [lindex $peers 0] expire key2 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key2] value
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key2] {}
        
    # }
    # test "reset hash" {
    #     [lindex $peers 0] hset hash2 key value;
    #     [lindex $peers 0] expire hash2 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget hash2 key] value
    #     [lindex $peers 0] expire hash2 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget hash2 key] value
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget hash2 key] {}
    #     after 10000
    #     assert_equal [[lindex $peers 0] ttl hash2] -2
    # }
    # test "persist" {
    #     [lindex $peers 0] set key3 value;
    #     [lindex $peers 0] expire key3 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key3] value
    #     [lindex $peers 0] persist key3;
    #     assert_equal [[lindex $peers 0] ttl key3] -1
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key3] value
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key3] value 
        
    # }
    # test "set after del" {
    #     [lindex $peers 0] set key4 value;
    #     [lindex $peers 0] expire key4 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get key4] value
    #     [lindex $peers 0] del key4;
    #     assert_equal [[lindex $peers 0] ttl key4] -2
    # }
    # test "hset after del" {
    #     [lindex $peers 0] hset hash3 k v ;
    #     [lindex $peers 0] expire hash3 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget hash3 k] v
    #     [lindex $peers 0] del hash3;
    #     assert_equal [[lindex $peers 0] ttl hash3] -2
    # }
    # test "hset after hdel" {
    #     [lindex $peers 0] hset hash4 k v ;
    #     [lindex $peers 0] expire hash4 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget hash4 k] v
    #     [lindex $peers 0] hdel hash4 k;
    #     assert_equal [[lindex $peers 0] ttl hash4] -2
    # }
    # test "crdt.persist" {
    #     set time [clock milliseconds]
    #     [lindex $peers 0] "CRDT.SET" "k1" "value" "2" $time "2:1"
    #     [lindex $peers 0] "CRDT.persist" "k1" "3" "0"
    #     assert_equal [[lindex $peers 0] ttl k1] -1
    #     [lindex $peers 0] "CRDT.expire" "k1" "2" [incr time -1]  [incr time 100000000] "0"
    #     set ttl [[lindex $peers 0] ttl k1]
    # }
    # test "crdt.set" {
    #     set time [clock milliseconds]
    #     [lindex $peers 0] "CRDT.SET" "k2" "value" "2" $time "2:2;3:1" 1000
    #     [lindex $peers 0] "CRDT.expire" "k2" "3" [incr time -1] [incr time 100000000] "0"
    #     if {[[lindex $peers 0] ttl k2] > 1000 } {
    #         error "crdt.set  expire conflict error"
    #     }
    # }
    # test "crdt.del" {
    #     set time [clock milliseconds]
    #     [lindex $peers 0] "CRDT.DEL_REG" k4 "2" $time "2:101;3:100" "2:101;3:100"
    #     [lindex $peers 0] "CRDT.expire" k4 "3" [incr time -1] [incr time 2000000] "0"
    #     assert_equal [[lindex $peers 0] ttl k4] -2
    # }
    
    # test "crdt.del2" {
    #     set time [clock milliseconds]
    #     [lindex $peers 0] "CRDT.DEL_REG" k5 2 $time "2:111;1:110" "2:111;1:110"
    #     [lindex $peers 0] "CRDT.expire" k5 1 [incr time 100] [incr time 1000] "0"
    #     [lindex $peers 0] hset k5 key value
    #     after 2000
    #     assert_equal [[lindex $peers 0] hget k5 key] value
    #     # log_file_matches [lindex $peer_stdouts 0]
    # }
    # test "crdt.del3" {
    #     set size [[lindex $peers 0] expiresize]
    #     [lindex $peers 0] debug set-crdt-ovc 0
    #     set time [clock milliseconds]
    #     [lindex $peers 0] "CRDT.DEL_REG" k6 2 $time "2:121;1:120" "2:111;1:120"
    #     [lindex $peers 0] "CRDT.expire" k6 1 [incr time 100] [incr time 1000] "0"
    #     [lindex $peers 0] hset k6 key value
    #     after 5000
    #     assert_equal [[lindex $peers 0] hget k6 key] value
    #     # log_file_matches [lindex $peer_stdouts 0]
    # }
    # test "set nx" {
    #     [lindex $peers 0] SET not-exists-key value NX;
    #     assert_equal [[lindex $peers 0] get not-exists-key]  value;
    #     [lindex $peers 0] SET not-exists-key value1 NX;
    #     assert_equal [[lindex $peers 0] get not-exists-key]  value;
    #     [lindex $peers 0] del not-exists-key;
    # }
    # test "set xx" {
    #     [lindex $peers 0] SET exists-key value xx;
    #     assert_equal [[lindex $peers 0] get exists-key]  {};
    #     [lindex $peers 0] SET exists-key value;
    #     assert_equal [[lindex $peers 0] get exists-key]  value;
    #     [lindex $peers 0] SET exists-key value2 xx;
    #     assert_equal [[lindex $peers 0] get exists-key]  value2;
    #     [lindex $peers 0] del exists-key;
    # }
    # test "set ex" {
    #     [lindex $peers 0] SET ex-key value EX 4;
    #     after 2000
    #     set t [[lindex $peers 0] ttl ex-key]
    #     if {$t <= 0} {
    #         error "set ex function error"
    #     }  
    #     assert_equal [[lindex $peers 0] get ex-key] value
    #     after 2500;
    #     assert_equal [[lindex $peers 0] ttl ex-key] -2
    #     assert_equal [[lindex $peers 0] get ex-key] {}
    # }
    
    # test "set ex after set" {
    #     [lindex $peers 0] SET ex-key2 value EX 4;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get ex-key2] value
    #     [lindex $peers 0] set ex-key2 value2
    #     after 2500;
    #     assert_equal [[lindex $peers 0] ttl ex-key2] -1
    #     assert_equal [[lindex $peers 0] get ex-key2] value2
    # }
    # test "setex" {
    #     [lindex $peers 0] SETex ex-key3   4 value;
    #     after 2000
    #     set t [[lindex $peers 0] ttl ex-key3]
    #     if {$t <= 0} {
    #         error "set ex function error"
    #     }  
    #     assert_equal [[lindex $peers 0] get ex-key3] value
    #     after 2500;
    #     assert_equal [[lindex $peers 0] ttl ex-key3] -2
    #     assert_equal [[lindex $peers 0] get ex-key3] {}
    # }
    # test "setex after set" {
    #     [lindex $peers 0] SETex ex-key4   4 value;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get ex-key4] value
    #     [lindex $peers 0] set ex-key4 value2
    #     after 2500;
    #     assert_equal [[lindex $peers 0] ttl ex-key4] -1
    #     assert_equal [[lindex $peers 0] get ex-key4] value2
    # }
    # test "set px" {
    #     [lindex $peers 0] SET px-key value PX 4000;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get px-key] value
    #     after 2000;
    #     assert_equal [[lindex $peers 0] ttl px-key] -2
    #     assert_equal [[lindex $peers 0] get px-key] {}
    # }
    # test "set px after set" {
    #     [lindex $peers 0] SET px-key2 value px 4000;
    #     after 2000
    #     assert_equal [[lindex $peers 0] get px-key2] value
    #     [lindex $peers 0] set px-key2 value2
    #     after 2000;
    #     assert_equal [[lindex $peers 0] ttl px-key2] -1
    #     assert_equal [[lindex $peers 0] get px-key2] value2
    # }


    
    start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2 
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
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