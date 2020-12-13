proc print_log_file {log} {
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
        print_log_file $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    # set master [redis "127.0.0.1" 6379]
    # $master select 9
    # set master_gid 1
    # set master_host "127.0.0.1"
    # set master_port 6379
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set repl-diskless-sync-delay 1
    $master crdt.debug_gc set 0


        
        wait_for_peer_sync $master
        test "sadd" {
            test {SADD, SCARD, SISMEMBER, SMEMBERS basics - intset} {
                assert_equal 1 [$master sadd myset1 16]
                assert_equal 0 [$master sadd myset1 16]
                assert_equal 2 [$master sadd myset1 17 18]
                assert_equal 3 [$master scard myset1]
                assert_equal 1 [$master sismember myset1 16]
                assert_equal 1 [$master sismember myset1 17]
                assert_equal 1 [$master sismember myset1 18]
                assert_equal 0 [$master sismember myset1 19]
                assert_equal {16 17 18} [lsort [$master smembers myset1]]
                assert_equal [$master crdt.sismember myset1 17] [$master crdt.sismember myset1 18]
                assert_equal 3 [$master srem myset1 16 17 18]
                assert_equal 3 [$master sadd myset1 16 17 18]
                assert_equal [$master crdt.sismember myset1 16] [$master crdt.sismember myset1 17]
                assert_equal [$master crdt.sismember myset1 16] [$master crdt.sismember myset1 18]
                assert_equal {16 17 18} [lsort [$master smembers myset1]]
            }
            test {crdt.sadd1} {
                
                $master crdt.sadd myset2 1 10 1:1 16 17
                assert_equal 2 [$master scard myset2]
                assert_equal 1 [$master sismember myset2 16]
                assert_equal 1 [$master sismember myset2 17]
                assert_equal {16 17} [lsort [$master smembers myset2]]
                puts [$master crdt.sismember myset2 16]
            }

            test {crdt.sadd2} {
                $master sadd myset3 16 
                $master crdt.sadd myset3 2 10 2:1 16 
                assert_equal 1 [$master scard myset3]
                assert_equal 1 [$master sismember myset3 16]
                assert_equal {16} [lsort [$master smembers myset3]]
            }
            test {crdt.sadd - crdt.sadd} {
                $master crdt.sadd myset4 3 10 3:1 16
                $master crdt.sadd myset4 2 10 2:1 16 
                assert_equal 1 [$master scard myset4]
                assert_equal 1 [$master sismember myset4 16]
                assert_equal {16} [lsort [$master smembers myset4]]
            }
            test {sadd - srem -sadd } {
                $master sadd myset5 16
                $master srem myset5 16 
                $master sadd myset5 16
                assert_equal 1 [$master scard myset5]
                assert_equal 1 [$master sismember myset5 16]
                assert_equal {16} [lsort [$master smembers myset5]]
            }
            
            test {sadd - srem -crdt.sadd } {
                $master sadd myset6 16
                $master srem myset6 16 
                $master crdt.sadd myset6 1 1000 1:10 16
                
                assert_equal 1 [$master scard myset6]
                assert_equal 1 [$master sismember myset6 16]
                assert_equal {16} [lsort [$master smembers myset6]]

            }
            test {sadd - del - crdt.sadd } {
                $master sadd myset7 16
                $master del myset7  
                $master crdt.sadd myset7 1 1000 1:14 16
                puts [$master crdt.datainfo myset7]
                assert_equal 1 [$master scard myset7]
                assert_equal 1 [$master sismember myset7 16]
                assert_equal {16} [lsort [$master smembers myset7]]

            }
            
        }
        test "rem" {
            test {rem1} {
                assert_equal 2 [$master sadd myset11 16 17]
                assert_equal 2 [$master srem myset11 16 17]
                assert_equal 1 [$master sadd myset11 16]
                assert_equal 1 [$master srem myset11 16]
                assert_equal 0 [$master sismember myset11 16]
                puts [$master crdt.sismember myset11 16]
            }
            test {rem2} {
                assert_equal 1 [$master sadd myset12 16]
                puts [$master crdt.sismember myset12 16]
                assert_equal OK [$master crdt.srem myset12 1 1000 1:100 16]
                assert_equal 0 [$master sismember myset12 16]
            }
            test {rem - sadd} {
                assert_equal 2 [$master sadd myset13 16 17]
                puts [$master crdt.sismember myset13 16 ]
                assert_equal OK [$master crdt.srem myset13 1 1000 {1:102} 16]
                assert_equal 1 [$master sadd myset13 16]
                assert_equal 1 [$master sismember myset13 16]
                puts [$master crdt.datainfo myset13]
                puts [$master crdt.sismember myset13 16]
            }
            test {crdt.rem - sadd conflict} {
                assert_equal 1 [$master sadd myset14 16]
                puts [$master crdt.sismember myset14 16]
                assert_equal OK [$master crdt.srem myset14 2 1000 {1:102;2:1} 16]
                assert_equal 1 [$master sismember myset14 16]
                puts [$master crdt.datainfo myset14]
                puts [$master crdt.sismember myset14 16]
                # print_log_file $master_log
            }
            test {crdt.rem > sadd } {
                $master crdt.sadd myset15 1 10 1:104 16 
                # assert_equal 1 [$master sadd myset14 16]
                puts [$master crdt.sismember myset15 16]
                assert_equal OK [$master crdt.srem myset15 2 1000 {1:104;2:2} 16]
                assert_equal OK [$master crdt.srem myset15 1 1000 {1:105;2:1} 16]
                assert_equal 0 [$master sismember myset15 16]
                puts [$master crdt.datainfo myset15]
                puts [$master crdt.sismember myset15 16]
                # print_log_file $master_log
            }

            test {rem1 will peer} {
                assert_equal 1 [$master sadd myset16 16]
                assert_equal 1 [$master srem myset16 16]
                assert_equal 0 [$master sismember myset16 16]
            }
            test {rem2 will peer} {
                $master crdt.srem myset17 1 1000 {1:108;2:10} 16
                puts [$master crdt.sismember myset17 16]
            }
            test {rem3 will peer} {
                $master crdt.srem myset18 1 1000 {1:109;2:10} 16
                puts [$master crdt.sismember myset18 16]
            }
            test {rem3 will peer} {
                $master crdt.srem myset19 1 1000 {1:109;2:10} 16
                puts [$master crdt.sismember myset18 16]
            }
        }
        test "del" {
            test {sadd - del} {
                
                # assert_equal 1 [$master sadd myset14 16]
                assert_equal 1 [$master sadd myset21 16 ]
                assert_equal 1 [$master del myset21 ]
                assert_equal 0 [$master sismember myset21 16]
                puts [$master crdt.datainfo myset21]
                puts [$master crdt.sismember myset21 16]
                # print_log_file $master_log
            }
            test {sadd srem - del} {
                
                # assert_equal 1 [$master sadd myset14 16]
                assert_equal 2 [$master sadd myset22 16 17]
                assert_equal 1 [$master srem myset22 17]
                assert_equal 1 [$master del myset22 ]
                assert_equal 0 [$master sismember myset22 16]
                # print_log_file $master_log
            }

            test {crdt.sadd srem} {
                $master crdt.sadd myset23 1 20 {1:2;3:1} 16
                $master del myset23 
                $master crdt.sadd myset23 3 20 3:1 16
                assert_equal 1 [$master sismember myset23 16]
            }
        }
        test "spop" {
            test {spop} {
                
                # assert_equal 1 [$master sadd myset14 16]
                assert_equal 3 [$master sadd myset25 16 17 18]
                set k [$master spop myset25 ]
                assert_equal 0 [$master sismember myset25 $k]
                puts [$master crdt.datainfo myset25]
                puts [$master crdt.sismember myset25 16]
                # print_log_file $master_log
            }
            
            test {spop2} {
                
                # assert_equal 1 [$master sadd myset14 16]
                assert_equal 3 [$master sadd myset26 16 17 18]
                set k [$master spop myset26 10]
                assert_equal 3 [llength $k]
                assert_equal 0 [$master scard myset26]
                puts [$master crdt.datainfo myset26]
                puts [$master crdt.sismember myset26 16]
                # print_log_file $master_log
            }
        }
       
        start_server {tags {"master-slave"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_log [srv 0 stdout]
            $slave crdt.debug_gc set 0
            $slave slaveof $master_host $master_port
            wait $master 0 info $master_log
            # print_log_file $slave_log
            test "master-slave-sadd" {
                assert_equal {16 17 18} [lsort [$slave smembers myset1]]
                assert_equal {16 17} [lsort [$slave smembers myset2]]
                assert_equal {16} [lsort [$slave smembers myset3]]
            }
            test "master-slave-srem" {
                assert_equal [string length [$master crdt.datainfo myset11]] [string length [$slave crdt.datainfo myset11]]
                assert_equal [$master crdt.datainfo myset12] [$slave crdt.datainfo myset12]
                assert_equal [string length [$master crdt.datainfo myset13]] [string length [$slave crdt.datainfo myset13]]
                assert_equal [$master crdt.datainfo myset14] [$slave crdt.datainfo myset14]
                assert_equal [$master crdt.datainfo myset15] [$slave crdt.datainfo myset15]
                assert_equal [$master crdt.datainfo myset16] [$slave crdt.datainfo myset16]
                assert_equal [$master crdt.datainfo myset17] [$slave crdt.datainfo myset17]
                assert_equal [$master crdt.datainfo myset18] [$slave crdt.datainfo myset18]
                assert_equal [string length [$master crdt.datainfo myset19]] [string length [$slave crdt.datainfo myset19]]
            }
            test "master-slave-del" {
                assert_equal [$master crdt.datainfo myset21] [$slave crdt.datainfo myset21]
                assert_equal [$master crdt.datainfo myset22] [$slave crdt.datainfo myset22]
            }
            test "master-slave-spop" {
                assert_equal [string length [$master crdt.datainfo myset25]] [string length [$slave crdt.datainfo myset25]]
                assert_equal [string length [$master crdt.datainfo myset26]] [string length [$slave crdt.datainfo myset26]]
            }
            
            start_server {tags {"set3"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
                set peer [srv 0 client]
                # set peer [redis "127.0.0.1" 6379]
                # $peer select 9
                # set master_gid 1
                # set master_host "127.0.0.1"
                # set master_port 6379
                set peer_log [srv 0 stdout]
                $peer crdt.debug_gc set 0
                test "before-master-master" {
                    test "add " {
                        test "will be merge add-add" {
                            $peer sadd myset2 16
                            puts [$peer crdt.sismember myset2 16]
                        }
                        test "will be merge add-tombstone => tombstone win" {
                            $peer crdt.srem myset3 3 1000 {1:100;2:1;3:10} 16
                        }
                        test "will be merge add-tombstone => add win" {
                            $peer crdt.srem myset5 3 1000 {1:1;3:10} 16
                        }
                        test "will be merge add-add-tombstone => add wins" {
                            $peer crdt.sadd myset6 2 1000 {2:2;3:11} 16
                            $peer crdt.sadd myset6 3 1000 {2:2;3:11} 16
                            $peer crdt.srem myset6 3 1000 {1:1;2:1;3:10} 16
                        }
                    }
                    test "rem " {
                        test "will be merge rem-rem" {
                            $peer crdt.srem myset12 3 1000 {1:1;2:1;3:10} 16
                            assert_equal "{type: orset_set_tombstone, vector-clock: 1:1;2:1;3:10}" [$peer crdt.sismember myset12 16]
                        }
                        test "will be merge rem-add => add wins" {
                            $peer sadd myset16 16
                            puts [$peer crdt.sismember myset16 16] 
                        }
                        test "will be merge rem-add => rem wins " {
                            $peer sadd myset17 16
                            puts [$peer crdt.sismember myset17 16] 
                        }
                        test "will be merge rem - rem - purge add => add wins " {
                            $peer sadd myset18 16
                            $peer srem myset18 16
                            $peer crdt.sadd myset18 3 1000 3:1 16
                            puts [$peer crdt.sismember myset18 16] 
                        }
                        test "will be merge rem - rem - purge add => rem wins " {
                            $peer sadd myset19 16
                            $peer srem myset19 16
                            $peer crdt.sadd myset19 1 1000 1:1 16
                            puts [$peer crdt.sismember myset19 16] 
                        }
                    }
                }
                $peer peerof $master_gid $master_host $master_port
                wait $master 0 crdt.info $peer_log
                # print_log_file $master_log
                test "master-master-sadd" {
                    test "only add" {
                        assert_equal {16 17 18} [lsort [$peer smembers myset1]]
                    }
                    test "merge add-add" {
                        puts [$peer crdt.sismember myset2 16]
                        puts [$peer crdt.sismember myset2 17]
                        assert_equal {16 17} [lsort [$peer smembers myset2]]
                    }
                    
                    test "merge  add-tombstone => tombstone wins" {
                        assert_equal {} [lsort [$peer smembers myset3]]
                    }

                    test "merge  add-tombstone => add wins" {
                        assert_equal {16} [lsort [$peer smembers myset5]]
                    }
                    
                    test "merge  add-add-purgetombstone => add wins" {
                        assert_equal {16} [lsort [$peer smembers myset6]]
                        #delete tombstone
                        assert_equal "{type: orset_set, vector-clock: 1:10;2:2;3:11}" [$peer crdt.sismember myset6 16]
                    }
                    test "merge  add-add-purgetombstone => only save tombstone wins" {

                    }

                }
                test "master-master-srem" {
                    test "only srem" {
                        assert_equal [$master crdt.datainfo myset11] [$peer crdt.datainfo myset11]
                        assert_equal [$master crdt.sismember myset11 16] [$peer crdt.sismember myset11 16]
                    }
                    test "srem - srem" {
                        assert_equal "{type: orset_set_tombstone, vector-clock: 1:100;2:1;3:10}" [$peer crdt.sismember myset12 16]
                    }
                    
                    test "srem - add => add wins" {
                        assert_equal {16} [lsort [$peer smembers myset16]]
                        assert_equal "{type: orset_set, vector-clock: 2:3} {type: orset_set_tombstone, vector-clock: 1:107}" [$peer crdt.sismember myset16 16]
                    }
                    test "srem - add => srem wins" {
                        puts [$peer crdt.sismember myset17 16]
                        assert_equal {} [lsort [$peer smembers myset17]]
                        
                    }
                    test "srem - srem - purge add  => add wins" {
                        assert_equal {16} [lsort [$peer smembers myset18]]
                        puts [$peer crdt.sismember myset18 16]
                    }
                    test "srem - srem - purge add  => srem wins" {
                        assert_equal {} [lsort [$peer smembers myset19]]
                        puts [$peer crdt.sismember myset19 16]
                    }
                    # assert_equal [$master crdt.datainfo myset13] [$peer crdt.datainfo myset13]
                    assert_equal [$master smembers myset14] [$peer smembers myset14]
                    assert_equal [$master crdt.datainfo myset15] [$peer crdt.datainfo myset15]
                }
                test "master-master-del" {
                    assert_equal [$master crdt.datainfo myset21] [$peer crdt.datainfo myset21]
                    assert_equal [$master crdt.datainfo myset22] [$peer crdt.datainfo myset22]
                }
                test "add_sync" {
                    test "sadd" {
                        $master sadd myset31 17 18
                        after 1000
                        assert_equal {17 18} [lsort [$master smembers myset31]] 
                        assert_equal {17 18} [lsort [$peer smembers myset31]] 
                        assert_equal {17 18} [lsort [$slave smembers myset31]] 
                        assert_equal [$master crdt.datainfo myset31] [$slave crdt.datainfo myset31]
                        assert_equal [$master crdt.datainfo myset31] [$peer crdt.datainfo myset31]
                    }
                    test "srem" {
                        $master sadd myset41 17 18
                        $master srem myset41 17 
                        after 1000
                        assert_equal {18} [lsort [$master smembers myset41]] 
                        assert_equal {18} [lsort [$peer smembers myset41]] 
                        assert_equal {18} [lsort [$slave smembers myset41]] 
                        assert_equal [$master crdt.datainfo myset41] [$slave crdt.datainfo myset41]
                        assert_equal [$master crdt.datainfo myset41] [$peer crdt.datainfo myset41]
                        
                    }
                    test "del" {
                        $master sadd myset51 17 18
                        $master del myset51 
                        after 1000
                        assert_equal {} [lsort [$master smembers myset51]] 
                        assert_equal {} [lsort [$peer smembers myset51]] 
                        assert_equal {} [lsort [$slave smembers myset51]] 
                        assert_equal [$master crdt.datainfo myset51] [$slave crdt.datainfo myset51]
                        assert_equal [$master crdt.datainfo myset51] [$peer crdt.datainfo myset51]
                    }
                    test "spop" {
                        test "spop argc == 2" {
                            $master sadd myset61 17 18 
                            set k [$master spop myset61] 
                            after 1000
                            assert_equal 0 [$master sismember myset61 $k]
                            assert_equal 0 [$peer sismember myset61 $k]
                            assert_equal 0 [$slave sismember myset61 $k]
                            assert_equal [$master crdt.datainfo myset61] [$slave crdt.datainfo myset61]
                            assert_equal [$master crdt.datainfo myset61] [$peer crdt.datainfo myset61]
                        }
                        test "spop argc == 3 size = 2" {
                            $master sadd myset62 17 18 
                            set r [$master spop myset62 2] 
                            puts [lindex $r 0]
                            puts [lindex $r 1]
                            assert_equal 2 [llength $r]
                            after 1000
                            for {set i 0} {$i < 2} {incr i} {
                                assert_equal 0 [$master sismember myset62 [lindex $r $i]]
                                assert_equal 0 [$peer sismember myset62 [lindex $r $i]]
                                assert_equal 0 [$slave sismember myset62 [lindex $r $i]]
                                assert_equal [$master crdt.sismember myset63 [lindex $r $i]] [$slave crdt.sismember  myset63 [lindex $r $i]]
                                assert_equal [$master crdt.sismember myset63 [lindex $r $i]] [$peer crdt.sismember  myset63 [lindex $r $i]]
                            }
                            assert_equal [$master crdt.datainfo myset62] [$slave crdt.datainfo myset62]
                            assert_equal [$master crdt.datainfo myset62] [$peer crdt.datainfo myset62]
                        }
                        test "spop argc == 3  size < 3" {
                            $master sadd myset63 17 18 19
                            set r [$master spop myset63 2] 
                            assert_equal 2 [llength $r]
                            after 1000
                            for {set i 0} {$i < 2} {incr i} {
                                assert_equal 0 [$master sismember myset63 [lindex $r $i]]
                                assert_equal 0 [$peer sismember myset63 [lindex $r $i]]
                                assert_equal 0 [$slave sismember myset63 [lindex $r $i]]
                                assert_equal [$master crdt.sismember myset63 [lindex $r $i]] [$slave crdt.sismember  myset63 [lindex $r $i]]
                                assert_equal [$master crdt.sismember myset63 [lindex $r $i]] [$peer crdt.sismember  myset63 [lindex $r $i]]
                            }
                            set r [$master smembers myset63] 
                            for {set i 0} {$i < [llength $r]} {incr i} {
                                assert_equal 1 [$master sismember myset63 [lindex $r $i]]
                                assert_equal 1 [$peer sismember myset63 [lindex $r $i]]
                                assert_equal 1 [$slave sismember myset63 [lindex $r $i]]
                                assert_equal [$master crdt.sismember myset63 [lindex $r $i]] [$slave crdt.sismember  myset63 [lindex $r $i]]
                                assert_equal [$master crdt.sismember myset63 [lindex $r $i]] [$peer crdt.sismember   myset63 [lindex $r $i]]
                            }
                            assert_equal [$master crdt.datainfo myset63] [$slave crdt.datainfo myset63]
                            assert_equal [$master crdt.datainfo myset63] [$peer crdt.datainfo myset63]
                            puts "abc"
                        }

                    }
                }

                
            }
        }
    
}

