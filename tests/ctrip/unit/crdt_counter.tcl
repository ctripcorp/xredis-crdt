proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

start_server {tags {"master"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    set master_gid  1
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    test "base" {
        $master set k 10
        assert_equal [$master get k ] 10
        $master incrby k 1
        assert_equal [$master get k] 11
        $master incr k 
        assert_equal [$master get k] 12
        $master decr k 
        assert_equal [$master get k] 11
        $master del k 
        assert_equal [$master get k] {}
    }
    
    test "base float" {
        $master set k2 1
        assert_equal [$master get k2] 1
        $master set k2 1.1
        assert_equal [$master get k2] 1.100000
        $master incrbyfloat k2 1
        assert_equal [$master get k2] 2.100000
        $master set k2 1
        assert_equal [$master get k2] 1.000000
    }

    test "base int -> incrbyfloat" {
        $master set k3 1
        assert_equal [$master get k3] 1
        $master incrbyfloat k3 1
        assert_equal [$master get k3] 2.000000
        
    }
    test "only incrby" {
        $master incrby k4 1
        $master incrbyfloat k4 1
        assert_equal [$master get k4] 2.000000
        $master incrbyfloat k5 1
        assert_equal [$master get k5] 1.000000
    }
    
    start_server {tags {"Simulation peer"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        set peer_gid  1
        
        test "Simulation peer" {
            proc rc { client key } {
                $client CRDT.Rc $key 10 3 1602828439439 {2:1;3:10001} -1
            }
            proc incrby { client key } {
                $client CRDT.COUNTER $key 3 1602828447252 {2:1;3:10002} 10002 10002 20
            }
            proc del { client key } {
                $client  CRDT.DEL_Rc $key 3 1602828460001 {2:1;3:10003} {3:10002:10002:20}
            }
            
            

            test "incrby - set - del" {
                
                rc $master test
                incrby $master test
                del $master test

                incrby $peer test
                rc $peer test
                del $peer test


                assert_equal [$master crdt.datainfo test] [$peer crdt.datainfo test]
                
            }
            test "del - set - incrby" {
                
                rc $master test1
                incrby $master test1
                del $master test1

                del $peer test1
                rc $peer test1
                incrby $peer test1
                
                assert_equal [$master crdt.datainfo test1] [$peer crdt.datainfo test1]
            }
            test "del - incrby  - set" {
                
                rc $master test2
                incrby $master test2
                del $master test2

                del $peer test2
                incrby $peer test2
                rc $peer test2

                assert_equal [$master crdt.datainfo test2] [$peer crdt.datainfo test2]
            }
            test "incrby - del  - set" {
                
                rc $master test3
                incrby $master test3
                del $master test3

                incrby $peer test3
                del $peer test3
                rc $peer test3

                assert_equal [$master crdt.datainfo test3] [$peer crdt.datainfo test3]
            }

            test "set - del  - incrbyty" {
                
                rc $master test4
                incrby $master test4
                del $master test4

                incrby $peer test4
                del $peer test4
                rc $peer test4

                assert_equal [$master crdt.datainfo test4] [$peer crdt.datainfo test4]
            }

            test "incrby - set " {
                rc $master test5
                incrby $master test5
                

                incrby $peer test5
                rc $peer test5
                
                assert_equal [$master crdt.datainfo test5] [$peer crdt.datainfo test5]
            }

            test "incrby - del " {
                
                incrby $master test6
                del $master test6

                del $peer test6
                incrby $peer test6
        
                assert_equal [$master crdt.datainfo test6] [$peer crdt.datainfo test6]
            }

            test "set - del " {
                
                rc $master test7
                del $master test7

                del $peer test7
                rc $peer test7
                
                assert_equal [$master crdt.datainfo test7] [$peer crdt.datainfo test7]
            }

        }
    }
    
    start_server {tags {"slave"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_log [srv 0 stdout]
        set slave_gid 1
        test "before" {
            test "set " {
                $master set test100 10
            }
            test "set + incrby" {
                $master set test101 3
                $master incrby test101 5
            }
        }
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        test "slaveof  over" {
            test "set " {
                assert_equal [$master crdt.datainfo test100] [$slave crdt.datainfo test100] 
            }
            test "set + incrby" {
                assert_equal [$master crdt.datainfo test101] [$slave crdt.datainfo test101] 
            }
            test "set + del" {
                assert {[$master tombstonesize] != 0}
                assert_equal [$master crdt.datainfo test6] [$slave crdt.datainfo test6] 
            }
            test "incryby + del" {
                assert {[$master tombstonesize] != 0}
                assert_equal [$master crdt.datainfo test7] [$slave crdt.datainfo test7]
            }
            test "set + incryby + del" {
                assert {[$master tombstonesize] != 0}
                assert_equal [$master crdt.datainfo test13] [$slave crdt.datainfo test13]
            }
        }


        test "slave after" {
            $master set test110 12345
            after 1000
            # print_log_file $slave_log
            assert_equal [$slave get test110] 12345 
        }

    }
    start_server {tags {"peer"} overrides {crdt-gid 4} config {crdt.conf} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_log [srv 0 stdout]
        set peer2_gid 4
        $peer2 config crdt.set repl-diskless-sync-delay 1
        test "before" {
            test "set  + null" {
                $master set test200 10
            }
            test "set  + set " {
                $master set test201 10
                $peer2 set test201 5
            }
            test "set  + set (incrby) " {
                $master set test202 10
                $peer2 set test202 5
                $peer2 incrby test202 7
            }
            test "set (incrby)  + set " {
                $master set test203 10
                $master incrby test203 6
                $peer2 set test203 5
            }
            test "set(incrby)  + set (incrby) " {
                $master set test204 10
                $master incrby test204 1
                $peer2 set test204 5
                $peer2 incrby test204 4
            }
            test "set + tombstone" {
                $master set test205 10
                $peer2 CRDT.DEL_Rc test205 4 1602828460001 {2:1;4:10003} {4:10002:10002:20}
            }
            test "set (incrby) + tombstone" {
                $master set test206 10
                $master incrby test206 3
                $peer2 CRDT.DEL_Rc test206 4 1602828460001 {2:1;4:10003} {4:10002:10002:20}
            }
            test "tombstone (set) + null" {
                $master CRDT.DEL_Rc test207 1 1602828460001 {1:3;2:1;3:10003} {3:10002:10002:20}
            }
            test "tombstone + set" {
                $master CRDT.DEL_Rc test208 1 1602828460001 {1:3;2:1;3:10003} {3:10002:10002:20}
                $peer2 set test208 3
            }
            test "tombstone + set(incrby)" {
                $master CRDT.DEL_Rc test209 1 1602828460001 {1:3;2:1;3:10003} {3:10002:10002:20}
                $peer2 set test209 3
                $peer2 incrby test209 7
            }
            test "tombstone + tombstone" {
                $master CRDT.DEL_Rc test210 1 1602828460003 {1:4;2:1;3:10003} {3:10002:10002:20}
                $master CRDT.DEL_Rc test210 3 1602828460002 {1:3;2:2;3:10005} {3:10004:10004:30}
            }
        }
        $peer2 peerof $master_gid $master_host $master_port
        $master peerof $peer2_gid $peer2_host $peer2_port
        # wait_for_peer_sync $master 
        # wait_for_peer_sync $peer2
        after 5000
        # print_log_file $peer2_log
        # print_log_file $master_log
        test "peer  over" {
            assert_equal [$master crdt.datainfo test200] [$peer2 crdt.datainfo test200] 
            assert_equal [$master crdt.datainfo test201] [$peer2 crdt.datainfo test201] 
            assert_equal [$master crdt.datainfo test202] [$peer2 crdt.datainfo test202] 
            assert_equal [$master crdt.datainfo test203] [$peer2 crdt.datainfo test203] 
            assert_equal [$master crdt.datainfo test204] [$peer2 crdt.datainfo test204]
            assert_equal [$master crdt.datainfo test205] [$peer2 crdt.datainfo test205] 
            assert_equal [$master crdt.datainfo test206] [$peer2 crdt.datainfo test206] 
            assert_equal [$master crdt.datainfo test207] [$peer2 crdt.datainfo test207] 
            assert_equal [$master crdt.datainfo test208] [$peer2 crdt.datainfo test208] 
            assert_equal [$master crdt.datainfo test209] [$peer2 crdt.datainfo test209]
            assert_equal [$master crdt.datainfo test210] [$peer2 crdt.datainfo test210]  

        }

        test "peer after" {
            test "set + set" {
                $peer2 set test220 2
                $master set test220 3
                after 1000
                assert_equal [$master crdt.datainfo test220] [$peer2 crdt.datainfo test220]
            }
            test "set + del" {
                $peer2 set test221 2
                $master del test221
                after 1000
                assert_equal [$master crdt.datainfo test221] [$peer2 crdt.datainfo test221]
            }
            test "crdt.rc + crdt.rc" {
                $peer2 crdt.rc test223 2 4 10000 {4:1} -1
                $master crdt.rc test223 3 1 10000 {1:2} -1
                $master crdt.rc test223 2 4 10000 {4:1} -1
                $peer2 crdt.rc test223 3 1 10000 {1:2} -1
                assert_equal [$master crdt.datainfo test223] [$peer2 crdt.datainfo test223]
                assert_equal [$master get test223 ] 3
                # assert_equal [$master get test220 ] 3
            }
            test "crdt.rc + crdt.incrby" {
                $peer2 crdt.rc test224 2 4 10000 {4:1} -1
                $master crdt.counter test224 3 10000 {4:1;3:2} 2 2 10
                $master crdt.rc test224 2 4 10000 {4:1} -1
                $peer2 crdt.counter test224 3 10000 {4:1;3:2} 2 2 10
                assert_equal [$master crdt.datainfo test224] [$peer2 crdt.datainfo test224]
                assert_equal [$master get test224 ] 12
            }
            test "crdt.incrby + crdt.incrby" {
                $peer2 crdt.counter test225 2  10000 {2:3} 3 3 4
                $master crdt.counter test225 3 10000 {3:2} 2 2 10
                $master crdt.counter test225 2  10000 {2:3} 3 3 4
                $peer2 crdt.counter test225 3 10000 {3:2} 2 2 10
                assert_equal [$master crdt.datainfo test225] [$peer2 crdt.datainfo test225]
                assert_equal [$master get test225 ] 14
            }
            test "crdt.rc + crdt.del_rc" {
                $peer2 crdt.rc test226 2 2 10000 {2:1} -1
                $master crdt.rc test226 2 2 10000 {2:1} -1

                $peer2 crdt.rc test226 3 4 10000 {4:1;2:1} -1
                $master crdt.del_rc test226 3 10000 {3:1;2:1}
                $master crdt.rc test226 3 4 10000 {4:1;2:1} -1
                $peer2 crdt.del_rc test226 3 10000 {3:1;2:1}
                assert_equal [$master crdt.datainfo test226] [$peer2 crdt.datainfo test226]
                assert_equal [$master get test226 ] 3
            }

            test "crdt.incrby + crdt.del_rc" {
                $peer2 crdt.rc test227 2 2 10000 {2:1} -1
                $master crdt.rc test227 2 2 10000 {2:1} -1

                $peer2 crdt.counter test227 4 10000 {2:2} 2 2 10
                $master crdt.del_rc test227 3 10000 {3:1;2:1}
                $master crdt.counter test227 4 10000 {2:2} 2 2 10
                $peer2 crdt.del_rc test227 3 10000 {3:1;2:1}
                assert_equal [$master crdt.datainfo test227] [$peer2 crdt.datainfo test227]
                assert_equal [$master get test227 ] 10
            }
        }

        test "expire" {
            $master set expire 1 
            $master expire expire 10
            after 1000
            assert_equal [$master get expire] 1
            after 10000
            assert_equal [$master get expire] {}
            assert_equal [$peer2 get expire] {}
        }

        test "gc" {
            $master set gc 100
            after 1000
            assert_equal [$master get gc] 100
            $master del gc
            after 1000
            assert_equal [ $master get gc ] {}
        }

        test "base" {
            $master set p1 10
            assert_equal [$master get p1 ] 10
            after 500
            assert_equal [$peer2 get p1 ] 10
            $master incrby p1 1
            assert_equal [$master get p1] 11
            after 500
            assert_equal [$peer2 get p1 ] 11
            $master del p1
            assert_equal [$master get p1] {}
            after 500
            assert_equal [$peer2 get p1 ] {}
            $master set p1 1
            after 500
            assert_equal [$peer2 get p1] 1
            # print_log_file $master_log
        }
        
        test "base float 2" {
            $master set p2 1.1
            assert_equal [$master get p2] 1.100000
            after 500
            assert_equal [$peer2 get p2 ] 1.100000
            $master incrbyfloat p2 1
            assert_equal [$master get p2] 2.100000
            after 500
            assert_equal [$peer2 get p2 ] 2.100000
            $master set p2 1
            assert_equal [$master get p2] 1.000000
            after 500
            assert_equal [$peer2 get p2] 1.000000
            $master incrbyfloat p2 1.1
            $master del p2 
            assert_equal [$master get p2] {}
            after 500
            assert_equal [$peer2 get p2] {}
            # print_log_file $master_log
            assert_equal [$peer2 crdt.datainfo p2] [$master crdt.datainfo p2]
        }

        test "base int -> incrbyfloat" {
            $master set p3 1
            assert_equal [$master get p3] 1
            after 500
            assert_equal [$peer2 get p3 ] 1
            $master incrbyfloat p3 1
            assert_equal [$master get p3] 2.000000
            after 500
            assert_equal [$peer2 get p3 ] 2.000000
        }
        test "only incrby2" {
            $master incrby p4 1
            $master incrbyfloat p4 1
            assert_equal [$master get p4] 2.000000
            after 500
            assert_equal [$peer2 get p4 ] 2.000000
            $master incrbyfloat p5 1
            assert_equal [$master get p5] 1.000000
            after 500
            # print_log_file $peer2_log
            assert_equal [$peer2 get p5 ] 1.000000
        }
        test "expire" {
            $master set p6 100
            $master expire p6 100
            after 500
            assert {[ $peer2 ttl p6] > 0}
            $master incrby p6 10
            after 500
            assert {[ $peer2 ttl p6] > 0}
            $master set p6 10
            after 500
            assert_equal [$peer2 ttl p6] -1
        }

        test "multi" {
            test {"multi - exec"} {
                $master multi
                $master set m1 10
                $master incrby m1 2
                $master incr m1  
                $master decr m1 
                $master incrbyfloat m1 3.0
                $master exec
                assert_equal [$master get m1] 15.000000
                assert_equal [$peer2 get m1] 15.000000
            } 
            test {"watch"} {
                $master set m2 1
                $master watch m2
                $master incrby m2 1
                $master multi
                $master set m2 3
                $master exec
                assert_equal [$master get m2] 2
                assert_equal [$peer2 get m2] 2
            } 
            test {"watch2"} {
                $master set m3 1
                after 500
                $peer2 watch m3
                $peer2 multi
                $peer2 set m3 3
                $master incrby m3 10
                after 500
                $peer2 exec
                assert_equal [$peer2 get m3] 11
            } 
        }


        test "type error" {
            test "set int -> set sds" {
                $master set err1 100
                set _ [catch {
                    $master set err1 a
                } retval]
                assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
            }
            test "set float -> set sds" {
                $master set err2 1.1
                set _ [catch {
                    $master set err1 a
                } retval]
                assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
            }
            test "set float -> set sds" {
                $master set err3 a
                set _ [catch {
                    $master incrby err3 1
                } retval]
                assert_equal $retval "ERR value is not an integer or out of range"
            }
            test "set float -> incrby" {
                $master set err4 1.1
                set _ [catch {
                    $master incrby err4 1
                } retval]
                assert_equal $retval "ERR value is not an integer or out of range"
            }
        }

    }
}
