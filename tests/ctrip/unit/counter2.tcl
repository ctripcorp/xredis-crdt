proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master crdt.debug_gc rc 0
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
        $peer crdt.debug_gc rc 0
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        test "before command" {
            test "set " {
                test "set + set" {
                    $master set k1000 10
                    $peer set k1000 11
                }
                test "set + incrby" {
                    $master set k1010 2
                    $peer incrby k1010 1
                }
                test "set + incrbyfloat" {
                    $master set k1020 2
                    $peer incrbyfloat k1020 1
                }
                test "set + del" {
                    test "set + del(base) step1" {
                        $master set k1030 1
                    }
                    test "set + del(add)" {
                        test "set + del(add-int) step1" {
                            $master incrby k1031 1
                        }
                        test "set + del(add-float) step1" {
                            $master incrbyfloat k1032 1.0 
                        }
                    }
                    test "set + del(base + add)" {
                        test "set + del(base + add-int) step1" {
                            $master set k1033 1
                            $master incrby k1033 1
                        }
                        test "set + del(base + add-float) step1" {
                            $master set k1034 1
                            $master incrby k1034 1
                        }
                    }
                    
                }
            }
            test "incrby" {
                test "incrby + set" {
                    $master set k1100 2
                    $peer incrby k1100 1
                }
                test "incrby + incrby" {
                    $master incrby k1101 2
                    $peer incrby k1101 1
                }
                test "incrby + incrbyfloat" {
                    $master incrby k1102 2
                    $peer incrbyfloat k1102 1
                }
                test "incrby + del" {
                    $master incrby k1103 1
                    after 1000
                    $master incrby k1102 2
                    $peer del k1102 1
                }
            }
            test "incrbyfloat" {

            }
            test "del" {

            }
        }
        after 2000
        test "after command" {
            test "set " {
                test "set + set check" {
                    assert_equal [$master crdt.datainfo k1000] [$peer crdt.datainfo k1000]
                    
                }
                test "set + incrby" {
                    assert_equal [$master crdt.datainfo k1010] [$peer crdt.datainfo k1010]
                }
                test "set + incrbyfloat" {
                    assert_equal [$master crdt.datainfo k1020] [$peer crdt.datainfo k1020]
                }
                test "set + del" {
                    test "before" {
                        test "set + del(base) step2" {
                            assert_equal [$master crdt.datainfo k1030 ] [$peer crdt.datainfo k1030 ]
                            $master set k1030 2
                            $peer del k1030 1    
                        }
                        test "set + del(add)" {
                            test "set + del(add-int) step2" {
                                assert_equal [$master crdt.datainfo k1031 ] [$peer crdt.datainfo k1031 ]
                                $master set k1031 2
                                $peer del k1031 1
                            }
                            test "set + del(add-float) step2" {
                                assert_equal [$master crdt.datainfo k1032 ] [$peer crdt.datainfo k1032 ]
                                $master set k1032 2
                                $peer del k1032 1
                            }
                        }
                        test "set + del(base + add)" {
                            test "set + del(base + add-int) step2" {
                                assert_equal [$master crdt.datainfo k1033 ] [$peer crdt.datainfo k1033 ]
                                $master set k1033 2
                                $peer del k1033 1
                            }
                            test "set + del(base + add-float) step2" {
                                assert_equal [$master crdt.datainfo k1034 ] [$peer crdt.datainfo k1034 ]
                                $master set k1034 2
                                $peer del k1034 1
                                
                            }
                        }
                    }
                    after 2000
                    test "after" {
                        test "set + del(base) " {
                            assert_equal [$master crdt.datainfo k1030 ] [$peer crdt.datainfo k1030 ]
                        }
                        test "set + del(add)" {
                            test "set + del(add-int)" {
                                assert_equal [$master crdt.datainfo k1031 ] [$peer crdt.datainfo k1031 ]
                            }
                            test "set + del(add-float)" {
                                assert_equal [$master crdt.datainfo k1032 ] [$peer crdt.datainfo k1032 ]
                            }
                        }
                        test "set + del(base + add)" {
                            test "set + del(base + add-int)" {
                                assert_equal [$master crdt.datainfo k1033 ] [$peer crdt.datainfo k1033 ]
                            }
                            test "set + del(base + add-float)" {
                                assert_equal [$master crdt.datainfo k1034 ] [$peer crdt.datainfo k1034 ]
                            }
                        }
    
                    }

                }
                
            }
        }
        
    }
}
