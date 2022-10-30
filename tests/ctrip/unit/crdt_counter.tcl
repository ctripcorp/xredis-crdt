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
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set repl-diskless-sync-delay 1

    start_server {tags {"crdt-set"} overrides {crdt-gid 9} config {crdt.conf} module {crdt.so} } {
        set peer_gc [srv 0 client]
        $peer_gc peerof $master_gid $master_host $master_port

        
        test {"crdt.zadd + crdt.zadd"} {
            test "step1 add crdt.zadd" {
                $master crdt.zadd zset1 1 1000 1:1 a 2:1.0 
                $master zscore zset1 a
            } {1}
            test "step2 crdt.zadd conflict by gid fail" {
                $master crdt.zadd zset1 2 1000 2:1 a 2:2.0 b 2:2.0
                assert_equal [$master zscore zset1 b] 2
                $master zscore zset1 a
            } {1}
            test "step3 crdt.zadd conflict by time" {
                $master crdt.zadd zset1 2 1001 2:2 a 2:2.0 
                $master zscore zset1 a
            } {2}
            test "step3 crdt.zadd conflict by time fail" {
                
                catch {$master crdt.zadd zset1 1 1000 {1:2;2:1} a 2:3.0 } error 
                # print_log_file $master_log
                $master zscore zset1 a
            } {2}
            test "step4 crdt.zadd conflict by gid" {
                $master crdt.zadd zset1 1 1001 {1:3;2:1} a 2:3.0 
                $master zscore zset1 a
            } {3}
            set old_info [$master crdt.datainfo zset1]
            test "step5 crdt.zadd repeat fail" {
                $master crdt.zadd zset1 1 1000 1:1 a 2:1.0 
                $master crdt.zadd zset1 2 1000 2:1 a 2:2.0 b 2:2
                $master zscore zset1 a
            } {3}
            assert_equal $old_info [$master crdt.datainfo zset1]
            test "step6 crdt.zincrby" {
                $master crdt.zincrby zset1 1 1000 1:1 a 2:1.12 
                $master zscore zset1 a
            } {4.1200000000000001}
            test "step6 other gid crdt.zincrby" {
                $master crdt.zincrby zset1 2 1000 2:1 a 2:1.0 
                $master zscore zset1 a
            } {5.1200000000000001}
            test "step6 crdt.zadd + del_counter" {
                $master crdt.zadd zset1 1 1000 {1:3;2:1} a  2:4,1:1:2:1.12
                $master zscore zset1 a
            } {4}
            
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2(add, add + del)" {
            test "null" {
                test "null + add" {
                    $master crdt.zadd zset1000 1 1000 1:1 a 2:1.0 
                    $master zscore zset1000 a
                } {1}
            }
            test "value" {
                test "succeed" {
                    test "a + add" {
                        test "a + add" {
                            $master crdt.zincrby zset1100 1 1000 1:1 a 2:1.0 
                            $master crdt.zadd zset1100 1 1000 1:2 a 2:2.0 
                            $master zscore zset1100 a
                        } {3}
                        test "a + add + del" {
                            $master crdt.zincrby zset1110 1 1000 1:1 a 2:1.0 
                            $master crdt.zadd zset1110 1 1000 1:2 a {2:2.0,1:1:2:1.0}
                            $master zscore zset1110 a
                        } {2}
                    } 
                    test "b + add" {
                        $master crdt.zadd zset1200 1 1000 1:1 a 2:1.0 
                        $master crdt.zadd zset1200 1 1000 1:2 a 2:2.0 
                        $master zscore zset1200 a
                    } {2}
                    test "ba + add" {
                        test "ba + add" {
                            $master crdt.zadd zset1300 1 1000 1:1 a 2:2.0 
                            $master crdt.zincrby zset1300 1 1000 1:2 a 2:1.0 
                            $master crdt.zadd zset1300 1 1000 1:3 a 2:3.0
                            $master zscore zset1300 a
                        } {4}
                        test "ba + add + del" {
                            $master crdt.zadd zset1310 1 1000 1:1 a 2:2.0 
                            $master crdt.zincrby zset1310 1 1000 1:2 a 2:1.0 
                            $master crdt.zadd zset1310 1 1000 1:3 a {2:3.0,1:2:2:1.0}
                            $master zscore zset1310 a
                        } {3}
                    }
                    test "ad + add" {
                        test "ad + add" {
                            $master crdt.zincrby zset1400 1 1000 1:1 a 2:1.0 
                            $master crdt.zrem zset1400 1 1000 1:2 {3:1:a,1:1:2:1.0}  
                            $master crdt.zadd zset1400 1 1000 1:3 a 2:3.0
                            $master zscore zset1400 a
                        } {3}
                        test "ad + add + del" {
                            $master crdt.zincrby zset1410 1 1000 1:2 a 2:3.0 
                            $master crdt.zrem zset1410 1 1000 1:1 {3:1:a,1:1:2:2.0} 
                            $master crdt.zadd zset1410 1 1000 1:3 a {2:3.0,1:1:2:4.0}
                            $master zscore zset1410 a
                        } {4}
                    }
                    test "bad + add" {
                        test "bad + add" {
                            $master crdt.zadd zset1500 1 1000 1:1 a 2:2.0
                            $master crdt.zincrby zset1500 1 1000 1:2 a 2:1.0 
                            $master crdt.zrem zset1500 1 1000 1:3 {3:1:a,1:1:2:1.0}  
                            $master crdt.zadd zset1500 1 1000 1:4 a 2:3.0
                            $master zscore zset1500 a
                        } {3}
                        test "bad + add + del" {
                            $master crdt.zadd zset1510 1 1000 1:1 a 2:2.0
                            $master crdt.zincrby zset1510 1 1000 1:2 a 2:3.0 
                            $master crdt.zrem zset1510 1 1000 1:1 {3:1:a,1:1:2:2.0} 
                            $master crdt.zadd zset1510 1 1000 1:3 a {2:3.0,1:1:2:4.0}
                            $master zscore zset1510 a
                        } {4}
                    }
                }
                test "fail" {
                    test "a + add" {
                        
                    }
                    test "b + add" {
                        $master crdt.zadd zset1201 1 1000 1:2 a 2:2.0 
                        $master crdt.zadd zset1201 1 1000 1:1 a 2:1.0 
                        $master zscore zset1200 a
                    } {2}
                    test "ba + add" {
                        test "ba + add + del only del" {
                            $master crdt.zincrby zset1311 1 1000 1:2 a 2:1.0 
                            $master crdt.zadd zset1311 1 1000 1:4 a 2:2.0 
                            $master crdt.zadd zset1311 1 1000 1:3 a {2:3.0,1:2:2:1.0}
                            $master zscore zset1311 a
                        } {2}
                    }
                    test "ad + add" {
                        test "ad + add" {
                            $master crdt.zincrby zset1401 1 1000 1:2 a 2:1.0 
                            $master crdt.zrem zset1401 1 1000 1:3 {3:1:a,1:2:2:1.0}  
                            $master crdt.zadd zset1401 1 1000 1:1 a 2:3.0
                            $master zscore zset1401 a
                        } {}
                    }
                    test "bad + add" {
                        test "bad + add" {
                            $master crdt.zadd zset1501 1 1000 1:2 a 2:2.0
                            $master crdt.zincrby zset1501 1 1000 1:3 a 2:1.0 
                            $master crdt.zrem zset1501 1 1000 1:4 {3:1:a,1:2:2:1.0}  
                            $master crdt.zadd zset1501 1 1000 1:1 a 2:3.0
                            $master zscore zset1501 a
                        } {0}
                        test "bad + add + del" {
                            $master crdt.zincrby zset1511 1 1000 1:2 a 2:3.0 
                            $master crdt.zrem zset1511 1 1000 1:1 {3:1:a,1:2:2:2.0} 
                            $master crdt.zadd zset1511 1 1000 1:5 a 2:2.0
                            $master crdt.zadd zset1511 1 1000 1:4 a {2:3.0,1:3:2:4.0}
                            $master zscore zset1511 a
                        } {2}
                        test "bad + add + del" {
                            $master crdt.zincrby zset1512 1 1000 1:2 a 2:3.0 
                            $master crdt.zrem zset1512 1 1000 1:1 {3:1:a,1:2:2:2.0} 
                            $master crdt.zadd zset1512 1 1000 1:5 a 2:2.0
                            $master crdt.zadd zset1512 1 1000 1:4 a {2:3.0,1:3:2:4.0}
                            $master crdt.zincrby zset1512 1 1000 1:3 a 2:4.0
                            $master zscore zset1512 a
                        } {2}
                    }
                }
                
            }
            test "tombstone" {
                test "succeed" {
                    test "succeed tombstone ad + zincrby" {
                        test "succeed ad + zincrby" {
                            $master crdt.zincrby zset2410 2 1000 2:1 a 2:2.0
                            $master crdt.zrem zset2410 2 1000 2:2 {3:1:a,2:1:2:2.0}
                            $master crdt.zincrby zset2410 2 1000 2:3 a 2:1.0
                            $master zscore zset2410 a
                        } {-1}
                    } 
                    test "succeed tombstone bad + zincrby1" {
                        test "succeed tombstone bad + zincrby1" {
                            $master crdt.zadd zset2510 2 1000 2:1 a 2:1.0
                            $master crdt.zincrby zset2510 2 1000 2:2 a 2:2.0
                            $master crdt.zrem zset2510 2 1000 2:3 {3:1:a,2:1:2:2.0}
                            $master crdt.zincrby zset2510 2 1000 2:4 a 2:1.0
                            $master zscore zset2510 a
                        } {-1}
                    } 
                }

                test "fail" {
                    test "fail tombstone ad + zincrby" {
                        test "fail tombstone ad + zincrby" {
                            $master crdt.zincrby zset2610 2 1000 2:1 a 2:1.0
                            $master crdt.zrem zset2610 2 1000 2:2 {3:1:a,2:1:2:1.0}
                            $master crdt.zincrby zset2610 2 1000 2:1 a 2:1.0
                            $master zscore zset2610 a
                        } {}
                    } 
                    test "fail tombstone bad  + zincrby" {
                        test "fail tombstone bad + zincrby" {
                            $master crdt.zadd zset2710 2 1000 2:1 a 2:1.0
                            $master crdt.zincrby zset2710 2 1000 2:2 a 2:1.0
                            $master crdt.zrem zset2710 2 1000 2:3 {3:1:a,2:2:2:1.0}
                            $master crdt.zincrby zset2710 2 1000 2:2 a 2:1.0
                            $master zscore zset2710 a
                        } {}
                    } 
                }
                
            }
            
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2(zincrby, zincrby + del)" {
            test "null" {
                test "null + zincrby" {
                    $master crdt.zincrby zset2000 1 1000 1:1 a 2:1.0 
                    $master zscore zset1000 a
                } {1}
            }
            test "value" {
                test "succeed" {
                    test "a + zincrby" {
                        test "a + zincrby" {
                            $master crdt.zincrby zset2100 1 1000 1:1 a 2:1.0
                            $master crdt.zincrby zset2100 1 1000 1:2 a 2:1.0
                            $master zscore zset2100 a
                        } {1}

                    } 
                    test "b + zincrby" {
                        test "b + zincrby" {
                            $master crdt.zadd zset2200 1 1000 1:1 a 2:1.0
                            $master crdt.zadd zset2200 1 1000 1:2 a 2:2.0
                            $master zscore zset2200 a
                        } {2}
                    }
                    test "ad + zincrby" {
                        test "ad + zincrby" {
                            $master crdt.zincrby zset2300 1 1000 1:1 a 2:1.0
                            $master crdt.zrem zset2300 1 1000 1:2 3:1:a,1:1:2:1.0
                            $master crdt.zincrby zset2300 1 1000 1:3 a 2:2.0
                            $master zscore zset2300 a
                        } {1}
                    }
                    test "ba + zincrby" {
                        test "ba + zincrby" {
                            $master crdt.zadd zset2400 1 1000 1:1 a 2:1.0
                            $master crdt.zincrby zset2400 1 1000 1:2 a 2:1.0
                            $master crdt.zincrby zset2400 1 1000 1:3 a 2:2.0
                            $master zscore zset2400 a
                        } {3}
                    }
                    test "bad + zincrby" {
                        test "bad + zincrby" {
                            $master crdt.zadd zset2500 1 1000 1:1 a 2:1.0
                            $master crdt.zincrby zset2500 1 1000 1:2 a 2:2.0
                            $master crdt.zincrby zset2500 1 1000 1:3 a 2:3.0
                            $master crdt.zrem zset2500 1 1000 1:4 3:1:a,1:2:2:2.0 
                            $master crdt.zincrby zset2500 1 1000 1:3 a 2:4.0
                            $master zscore zset2500 a
                        } {1}   
                    }

                }

                test "fail" {
                    test "fail a + zincrby" {
                        test "a + zincrby" {
                            $master crdt.zincrby zset2600 1 1000 1:1 a 2:1.0
                            $master crdt.zincrby zset2600 1 1000 1:1 a 2:1.0
                            $master zscore zset2600 a
                        } {1}
                    } 
                    test "fail b + zincrby" {
                    }
                    test "fail ad + zincrby" {
                        test "fail ad + zincrby" {
                            $master crdt.zincrby zset2110 1 1000 1:1 a 2:1.0
                            $master crdt.zrem zset2110 1 1000 1:2 3:1:a,1:1:2:1.0
                            $master crdt.zincrby zset2110 1 1000 1:3 a 2:1.0
                            $master zscore zset2110 a
                        } {0}
                    }
                    test "fail ba + zincrby1" {
                        test "fail ba + zincrby1" {
                            $master crdt.zadd zset2210 1 1000 1:1 a 2:1.0
                            $master crdt.zincrby zset2210 1 1000 1:2 a 2:1.0
                            $master crdt.zincrby zset2210 1 1000 1:1 a 2:2.0
                            $master zscore zset2210 a
                        } {2}
                    }
                    test "fail bad + zincrby2" {
                        test "fail bad + zincrby2" {
                            $master crdt.zadd zset2310 1 1000 1:1 a 2:1.0
                            $master crdt.zincrby zset2310 1 1000 1:2 a 2:2.0
                            $master crdt.zincrby zset2310 1 1000 1:3 a 2:3.0
                            $master crdt.zrem zset2310 1 1000 1:4 3:1:a,1:2:2:2.0 
                            $master crdt.zincrby zset2310 1 1000 1:3 a 2:3.0
                            $master zscore zset2310 a
                        } {1}   
                    }

                }
            }
            test "tombstone" {
                test "succeed" {
                    test "succeed tombstone ad + zincrby" {
                        test "succeed ad + zincrby" {
                            $master crdt.zincrby zset2410 2 1000 2:1 a 2:2.0
                            $master crdt.zrem zset2410 2 1000 2:2 3:1:a,2:1:2:2.0
                            $master crdt.zincrby zset2410 2 1000 2:3 a 2:1.0
                            $master zscore zset2410 a
                        } {-1}
                    } 
                    test "succeed tombstone bad + zincrby1" {
                        test "succeed tombstone bad + zincrby1" {
                            $master crdt.zadd zset2510 2 1000 2:1 a 2:1.0
                            $master crdt.zincrby zset2510 2 1000 2:2 a 2:2.0
                            $master crdt.zrem zset2510 2 1000 2:3 3:1:a,2:1:2:2.0
                            $master crdt.zincrby zset2510 2 1000 2:4 a 2:1.0
                            $master zscore zset2510 a
                        } {-1}
                    } 
                }

                test "fail" {
                    test "fail tombstone ad + zincrby" {
                        test "fail tombstone ad + zincrby" {
                            $master crdt.zincrby zset2610 2 1000 2:1 a 2:1.0
                            $master crdt.zrem zset2610 2 1000 2:2 3:1:a,2:1:2:1.0
                            $master crdt.zincrby zset2610 2 1000 2:1 a 2:1.0
                            $master zscore zset2610 a
                        } {}
                    } 
                    test "fail tombstone bad  + zincrby" {
                        test "fail tombstone bad + zincrby" {
                            $master crdt.zadd zset2710 2 1000 2:1 a 2:1.0
                            $master crdt.zincrby zset2710 2 1000 2:2 a 2:1.0
                            $master crdt.zrem zset2710 2 1000 2:3 3:1:a,2:2:2:1.0
                            $master crdt.zincrby zset2710 2 1000 2:2 a 2:1.0
                            $master zscore zset2710 a
                        } {}
                    } 
                }
                
            }
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2(zrem, zrem + del)" {
            test "null" {
                test "null + zrem" {
                    $master crdt.zrem zset3000 1 1000 1:2 3:1:a
                    $master zscore zset3000 a
                } {}
            }
            test "value" {
                test "succeed" {
                    test "a + zrem" {
                        $master crdt.zincrby zset3100 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset3100 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master zscore zset3100 a
                    } {}
                    test "b + zrem" {
                        $master crdt.zadd zset3200 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset3200 1 1000 1:2 3:1:a
                        $master zscore zset3200 a
                    } {}
                    test "ba + zrem" {
                        $master crdt.zadd zset3300 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset3300 1 1000 1:2  a 2:1.0
                        $master crdt.zrem zset3300 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master zscore zset3300 a
                    } {}
                    test "ad + zrem" {
                        $master crdt.zincrby zset3400 1 1000 1:3  a 2:3.0
                        $master crdt.zrem zset3400 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.zrem zset3400 1 1000 1:4 3:1:a,1:3:2:3.0
                        $master zscore zset3400 a
                    } {}
                    test "bad + zrem" {
                        $master crdt.zadd zset3500 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset3500 1 1000 1:3  a 2:2.0
                        $master crdt.zrem zset3500 1 1000 1:2 3:1:a,1:2:2:1.0
                        $master crdt.zrem zset3500 1 1000 1:3 3:1:a,1:3:2:2.0
                        $master zscore zset3500 a
                    } {}
                }
                test "fail" {
                    test "fail a + zrem" {
                        $master crdt.zincrby zset3110 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset3110 1 1000 1:2 3:1:a
                        $master zscore zset3110 a
                    } {1}
                    test "fail b + zrem" {
                        $master crdt.zadd zset3210 1 1000 1:3  a 2:1.0
                        $master crdt.zrem zset3210 1 1000 1:2 3:1:a
                        $master zscore zset3210 a
                    } {1}
                    test "fail ba + zrem" {
                        $master crdt.zadd zset3310 1 1000 1:2  a 2:1.0
                        $master crdt.zincrby zset3310 1 1000 1:3  a 2:1.0
                        $master crdt.zrem zset3310 1 1000 1:1 3:1:a 
                        $master zscore zset3310 a
                    } {2}
                    test "fail ad + zrem" {
                        $master crdt.zincrby zset3410 1 1000 1:4  a 2:3.0
                        $master crdt.zrem zset3410 1 1000 1:3 3:1:a,1:1:2:1.0
                        $master crdt.zrem zset3410 1 1000 1:1 3:1:a,1:1:2:1.0 
                        $master zscore zset3410 a
                    } {2}
                    test "fail bad + zrem" {
                        $master crdt.zadd zset3510 1 1000 1:4  a 2:1.0
                        $master crdt.zincrby zset3510 1 1000 1:5  a 2:2.0
                        $master crdt.zrem zset3510 1 1000 1:3 {3:1:a,1:2:2:1.0}
                        $master crdt.zrem zset3510 1 1000 1:2 {3:1:a,1:1:2:2.0}
                        $master zscore zset3510 a
                    } {2}
                }
            }
            test "tombstone" {
                test "succeed" {
                    test "tombstone ad + zrem" {
                        $master crdt.zincrby zset3101 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset3101 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.zrem zset3101 1 1000 1:3 3:1:a,1:1:2:2.0
                        $master zscore zset3101 a
                    } {}
                    test "tombstone bad + zrem" {
                        $master crdt.zadd zset3102 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset3202 1 1000 1:2  a 2:1.0
                        $master crdt.zrem zset3102 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master crdt.zrem zset3102 1 1000 1:5 3:1:a,1:3:2:2.0
                        $master zscore zset3102 a
                    } {}
                }
                test "fail" {
                    test "tombstone fail ba + zrem" {
                        $master crdt.zincrby zset3103 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset3103 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.zrem zset3103 1 1000 1:1 3:1:a
                        $master zscore zset3103 a
                    } {}
                    test "tombstone fail bad + zrem" {
                        $master crdt.zadd zset3104 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset3104 1 1000 1:2  a 2:1.0
                        $master crdt.zrem zset3104 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master crdt.zrem zset3104 1 1000 1:1 3:1:a,1:1:2:1.0
                        $master zscore zset3104 a
                    } {}
                }
            }
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2(del, del + del)" {
            test "null" {
                test "null + del" {
                    $master crdt.del_ss zset4000 1 1000 1:2 
                    $master zscore zset4000 a
                } {}
            }
            test "value" {
                test "succeed" {
                    test "a + del" {
                        $master crdt.zincrby zset4100 1 1000 1:1  a 2:1.0
                        $master crdt.del_ss zset4100 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master zscore zset4100 a
                    } {}
                    test "b + del" {
                        test "b + del1" {
                            $master crdt.zadd zset4200 1 1000 1:1  a 2:1.0
                            $master crdt.del_ss zset4200 1 1000 1:2 3:1:a,1:1:2:1.0
                            $master zscore zset4200 a
                        } {}
                        test "b + del2" {
                            $master crdt.zadd zset4210 1 1000 1:1  b 2:1.0
                            $master crdt.zadd zset4210 1 1000 1:1  a 2:1.0 c 2:1.0
                            assert_equal [$master zscore zset4210 c] 1
                            assert_equal [$master zscore zset4210 b] 1

                            $master crdt.del_ss zset4210 1 1000 1:2 
                            assert_equal [$master zscore zset4210 b] {}
                            assert_equal [$master zscore zset4210 b] {}
                            $master zscore zset4210 a
                        } {}
                        
                    }
                    test "ba + del" {
                        $master crdt.zadd zset4300 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset4300 1 1000 1:2  a 2:1.0
                        $master crdt.del_ss zset4300 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master zscore zset4300 a
                    } {}
                    test "ad + del" {
                        $master crdt.zincrby zset4400 1 1000 1:3  a 2:3.0
                        $master crdt.zrem zset4400 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.del_ss zset4400 1 1000 1:4 3:1:a,1:3:2:3.0
                        $master zscore zset4400 a
                    } {}
                    test "bad + del" {
                        $master crdt.zadd zset4500 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset4500 1 1000 1:3  a 2:2.0
                        $master crdt.zrem zset4500 1 1000 1:2 3:1:a,1:2:2:1.0
                        $master crdt.del_ss zset4500 1 1000 1:3 3:1:a,1:3:2:2.0
                        $master zscore zset4500 a
                    } {}
                }

                test "fail" {
                    test "a + del" {
                        $master crdt.zincrby zset4110 1 1000 1:3  a 2:1.0
                        $master crdt.del_ss zset4110 1 1000 1:2 
                        $master zscore zset4110 a
                    } {1}
                    test "b + del" {
                        $master crdt.zadd zset4210 1 1000 1:3  a 2:1.0
                        $master crdt.del_ss zset4210 1 1000 1:2 
                        $master zscore zset4210 a
                    }
                    test "ba + del" {
                        $master crdt.zadd zset4310 1 1000 1:2  a 2:1.0
                        $master crdt.zincrby zset4310 1 1000 1:3  a 2:1.0
                        $master crdt.del_ss zset4310 1 1000 1:1
                        $master zscore zset4310 a
                    } {2}
                    test "ad + del" {
                        $master crdt.zincrby zset4410 1 1000 1:3  a 2:3.0
                        $master crdt.zrem zset4410 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.del_ss zset4410 1 1000 1:1 3:1:a,1:1:2:1.0
                        $master zscore zset4410 a
                    } {2}
                    test "bad + del" {
                        $master crdt.zadd zset4510 1 1000 1:2  a 2:1.0
                        $master crdt.zincrby zset4510 1 1000 1:4  a 2:2.0
                        $master crdt.zrem zset4510 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master crdt.del_ss zset4510 1 1000 1:1 3:1:a,1:1:2:2.0
                        $master zscore zset4510 a
                    } {1}
                }
            }
            test "tombstone" {
                test "succeed" {
                    test "tombstone ad + del" {
                        $master crdt.zincrby zset4101 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset4101 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.del_ss zset4101 1 1000 1:3 3:1:a,1:1:2:2.0
                        $master zscore zset4101 a
                    } {}
                    test "tombstone bad + del" {
                        $master crdt.zadd zset4102 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset4102 1 1000 1:2  a 2:1.0
                        $master crdt.zrem zset4102 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master crdt.del_ss zset4102 1 1000 1:5 3:1:a,1:3:2:2.0
                        $master zscore zset4102 a
                    } {}
                }
                test "fail" {
                    test "tombstone fail ba + del" {
                        $master crdt.zincrby zset4103 1 1000 1:1  a 2:1.0
                        $master crdt.zrem zset4103 1 1000 1:2 3:1:a,1:1:2:1.0
                        $master crdt.del_ss zset4103 1 1000 1:1 
                        $master zscore zset4103 a
                    } {}
                    test "tombstone fail bad + del" {
                        $master crdt.zadd zset4104 1 1000 1:1  a 2:1.0
                        $master crdt.zincrby zset4104 1 1000 1:2  a 2:1.0
                        $master crdt.zrem zset4104 1 1000 1:3 3:1:a,1:2:2:1.0
                        $master crdt.del_ss zset4104 1 1000 1:1 3:1:a,1:1:2:1.0
                        $master zscore zset4104 a
                    } {}
                }
            }
        }

        start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            test "before  master-slave sync" {
            test "value" {
                test "a" {
                    $master  crdt.zincrby zset5100 1 1000 1:1 a 2:1.1
                }
                test "b" {
                    $master  crdt.zadd zset5200 1 1000 1:1 a 2:1.2 
                }
                test "ad" {
                    $master  crdt.zincrby zset5300 1 1000 1:2 a 2:2.0 
                    $master  crdt.zrem zset5300 1 1000 1:1 3:1:a,1:1:2:1.0 
                    # puts [$master crdt.datainfo zset5300]
                }
                test "ba" {
                    $master  crdt.zadd zset5400 1 1000 1:1 a 2:1.1 
                    $master  crdt.zincrby zset5400 1 1000 1:1 a 2:1.0 
                }
                test "bad" {
                    $master  crdt.zadd zset5500 1 1000 1:1 a 2:1.0 
                    $master  crdt.zincrby zset5500 1 1000 1:3 a 2:2.0 
                    $master  crdt.zrem zset5500 1 1000 1:4 3:1:a,1:2:2:1.0 
                }
            }
            test "tombstone" {
                test "ad" {
                    $master  crdt.zincrby zset5600 1 1000 1:1 a 2:2.0 
                    $master  crdt.zrem zset5600 1 1000 1:2 3:1:a,1:1:2:2.0 
                }
                test "bad" {
                    $master  crdt.zadd zset5700 1 1000 1:1 a 2:2.0 
                    $master  crdt.zincrby zset5700 1 1000 1:2 a 2:2.0 
                    $master  crdt.zrem zset5700 1 1000 1:3 3:1:a,1:2:2:2.0 
                }    
            }
                
            }
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_log
            test "after  master-slave sync" {
                test "value" {
                    test "a" {
                        assert_equal [$master crdt.datainfo zset5100] [$slave crdt.datainfo zset5100]
                        # puts [$master crdt.datainfo zset5100]
                    }
                    test "b" {
                        assert_equal [$master crdt.datainfo zset5200] [$slave crdt.datainfo zset5200]
                    }
                    test "ad" {
                        assert_equal [$master crdt.datainfo zset5300] [$slave crdt.datainfo zset5300]
                        
                    }
                    test "ba" {
                        assert_equal [$master crdt.datainfo zset5400] [$slave crdt.datainfo zset5400]
                        
                    }
                    test "bad" {
                        assert_equal [$master crdt.datainfo zset5500] [$slave crdt.datainfo zset5500]
                    }
                }
                test "tombstone" {
                    test "ad" {
                    
                        assert_equal [$master crdt.datainfo zset5600] [$slave crdt.datainfo zset5600]
                    }
                    test "bad" {
                        assert_equal [$master crdt.datainfo zset5700] [$slave crdt.datainfo zset5700]
                    }
                }
                
            }
        }
    }
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
       
        test "before" {
            test "a" {
                test "a + null" {
                    $master crdt.zincrby zset6100 1 1000 1:1 a 2:1.0 
                }
                test "a + a" {
                    test "before a + a success" {
                        $master crdt.zincrby zset6101 1 1000 1:2 a 2:1.0 
                        $peer crdt.zincrby zset6101 1 1000 1:1 a 2:2.0 
                    }
                    test "before a + a fail" {
                        $master crdt.zincrby zset6102 1 1000 1:1 a 2:1.0 
                        $peer crdt.zincrby zset6102 1 1000 1:2 a 2:2.0 
                    }
                }
                test "a + b" {
                    $master crdt.zincrby zset6120 1 1000 1:2 a 2:1.0 
                    $peer crdt.zadd zset6120 1 1000 1:1 a 2:2.0 
                }
                test "a + ba" {
                    test "before a + ba success" {
                        $master crdt.zincrby zset6130 1 1000 1:3 a 2:1.0 
                        $peer crdt.zadd zset6130 1 1000 1:1 a 2:2.0 
                        $peer crdt.zincrby zset6130 1 1000 1:2 a 2:2.0 
                    }
                    test "before a + ba fail" {
                        $master crdt.zincrby zset6131 1 1000 1:2 a 2:1.0 
                        $peer crdt.zadd zset6131 1 1000 1:1 a 2:2.0 
                        $peer crdt.zincrby zset6131 1 1000 1:3 a 2:2.0
                    }
                }
                test "a + ad" {
                    test "before a + ad success" {
                        $master crdt.zincrby zset6140 1 1000 1:4 a 2:3.0 
                        $peer crdt.zincrby zset6140 1 1000 1:2 a 2:2.0 
                        $peer crdt.zrem zset6140 1 1000 1:3 3:1:a,1:1:2:1.0
                    }
                    test "before a + ad fail" {
                        $master crdt.zincrby zset6141 1 1000 1:1 a 2:1.0 
                        $peer crdt.zincrby zset6141 1 1000 1:4 a 2:3.0 
                        $peer crdt.zrem zset6141 1 1000 1:3 3:1:a,1:2:2:2.0
                    }
                }
                test "a + bad" {
                    test "before a + bad success" {
                        $master crdt.zincrby zset6150 1 1000 1:6 a 2:3.0 
                        $peer crdt.zadd zset6150 1 1000 1:5 a 2:2.0 
                        $peer crdt.zincrby zset6150 1 1000 1:3 a 2:2.0 
                        $peer crdt.zrem zset6150 1 1000 1:4 3:1:a,1:1:2:1.0
                    }
                    test "before a + ba fail" {
                        $master crdt.zincrby zset6151 1 1000 1:1 a 2:1.0 
                        $peer crdt.zadd zset6151 1 1000 1:5 a 2:2.0 
                        $peer crdt.zincrby zset6151 1 1000 1:3 a 2:2.0 
                        $peer crdt.zrem zset6151 1 1000 1:4 3:1:a,1:1:2:1.0
                    }
                }
            }
            test "b" {
                test "b + null" {
                    $master crdt.zadd zset6200 1 1000 1:1 a 2:1.0 
                }
                test "b + a" {
                    $master crdt.zadd zset6210 1 1000 1:1 a 2:1.0 
                    $peer crdt.zincrby zset6210 1 1000 1:2 a 2:1.0
                }
                test "b + b" {
                    test " b + b success" {
                        $master crdt.zadd zset6220 1 1000 1:2 a 2:1.0 
                        $peer crdt.zadd zset6220 1 1000 1:1 a 2:2.0
                    }
                    test "b + b fail" {
                        $master crdt.zadd zset6221 1 1000 1:1 a 2:1.0 
                        $peer crdt.zadd zset6221 1 1000 1:2 a 2:2.0
                    }
                }
                test "b + ad" {
                    $master crdt.zadd zset6230 1 1000 1:1 a 2:1.0 
                    $peer crdt.zincrby zset6230 1 1000 1:3 a 2:2.0
                    $peer crdt.zrem zset6230 1 1000 1:2 3:1:a,1:1:2:1.0
                }
                test "b + ba" {
                    test "b + ba success" {
                        $master crdt.zadd zset6240 1 1000 1:4 a 2:1.0
                        $peer crdt.zadd zset6240 1 1000 1:2 a 2:2.0 
                        $peer crdt.zincrby zset6240 1 1000 1:3 a 2:2.0
                    }
                    test "b + ba fail" {
                        $master crdt.zadd zset6241 1 1000 1:1 a 2:1.0
                        $peer crdt.zadd zset6241 1 1000 1:2 a 2:2.0 
                        $peer crdt.zincrby zset6241 1 1000 1:3 a 2:2.0
                    }
                    
                }
                test "b + bad" {
                    test "b + ba success" {
                        $master crdt.zadd zset6250 1 1000 1:6 a 2:1.0 
                        $peer crdt.zadd zset6250 1 1000 1:5 a 2:2.0 
                        $peer crdt.zincrby zset6250 1 1000 1:3 a 2:2.0 
                        $peer crdt.zrem zset6250 1 1000 1:4 3:1:a,1:1:2:1.0
                    }
                    test "b + ba fail" {
                        $master crdt.zadd zset6251 1 1000 1:2 a 2:1.0 
                        $peer crdt.zadd zset6251 1 1000 1:5 a 2:2.0 
                        $peer crdt.zincrby zset6251 1 1000 1:3 a 2:2.0 
                        $peer crdt.zrem zset6251 1 1000 1:4 3:1:a,1:1:2:1.0
                    }
                }
            }
            test "ad" {
                test "ad + null1" {
                    $master crdt.zincrby zset6300 1 1000 1:3 a 2:2.0
                    $master crdt.zrem zset6300 1 1000 1:2 3:1:a,1:1:2:1.0
                }
                test "ad + a" {
                    test "ad + a success" {
                        $master crdt.zincrby zset6310 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6310 1 1000 1:2 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6310 1 1000 1:1 a 2:3.0
                    }
                    test "ad + a fail" {
                        $master crdt.zincrby zset6311 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6311 1 1000 1:2 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6311 1 1000 1:4 a 2:3.0
                    }
                }
                test "ad + b" {
                    $master crdt.zincrby zset6320 1 1000 1:3 a 2:2.0
                    $master crdt.zrem zset6320 1 1000 1:2 3:1:a,1:1:2:1.0
                    $peer crdt.zadd zset6320 1 1000 1:1 a 2:3.0
                    
                }
                test "ad + ba" {
                    test "ad + ba success" {
                        $master crdt.zincrby zset6330 1 1000 1:5 a 2:2.0
                        $master crdt.zrem zset6330 1 1000 1:2 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6330 1 1000 1:1 a 2:2.0 
                        $peer crdt.zincrby zset6330 1 1000 1:4 a 2:1.0
                    }
                    test "ad + ba fail" {
                        $master crdt.zincrby zset6331 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6331 1 1000 1:2 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6331 1 1000 1:4 a 2:2.0 
                        $peer crdt.zincrby zset6331 1 1000 1:5 a 2:1.0
                        
                    }
                    
                }
                test "ad + ad" {
                    test "ad + ad success" {
                        $master crdt.zincrby zset6340 1 1000 1:4 a 2:5.0
                        $master crdt.zrem zset6340 1 1000 1:3 3:1:a,1:2:2:2.0
                        $peer crdt.zincrby zset6340 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6340 1 1000 1:1 3:1:a,1:1:2:1.0
                    }
                    test "ad + ad a fail" {
                        $master crdt.zincrby zset6341 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6341 1 1000 1:2 3:1:a,1:2:2:1.0
                        $peer crdt.zincrby zset6341 1 1000 1:4 a 2:3.0
                        $peer crdt.zrem zset6341 1 1000 1:1 3:1:a,1:1:2:2.0
                    }
                    test "ad + ad d fail" {
                        $master crdt.zincrby zset6342 1 1000 1:7 a 2:2.0
                        $master crdt.zrem zset6342 1 1000 1:2 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6342 1 1000 1:5 a 2:3.0
                        $peer crdt.zrem zset6342 1 1000 1:4 3:1:a,1:3:2:2.0
                    }
                    test "ad + ad ad fail" {
                        $master crdt.zincrby zset6343 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6343 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6343 1 1000 1:4 a 2:3.0
                        $peer crdt.zrem zset6343 1 1000 1:2 3:1:a,1:2:2:2.0
                    }

                    
                }
                test "ad + bad" {
                    test "ad + bad success" {
                        # 6
                        $master crdt.zincrby zset6350 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6350 1 1000 1:2 3:1:a,1:3:2:3.0
                        $peer crdt.zadd zset6350 1 1000 1:4 a 2:2.0
                        $peer crdt.zincrby zset6350 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6350 1 1000 1:1 3:1:a,1:1:2:1.0
                    }
                    test "ad + bad a fail" {
                        # 4
                        $master crdt.zincrby zset6351 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6351 1 1000 1:2 3:1:a,1:2:2:1.0
                        $peer crdt.zadd zset6351 1 1000 1:4 a 2:2.0
                        $peer crdt.zincrby zset6351 1 1000 1:4 a 2:3.0
                        $peer crdt.zrem zset6351 1 1000 1:1 3:1:a,1:1:2:2.0
                    }
                    test "ad + bad d fail" {
                        # 3
                        $master crdt.zincrby zset6352 1 1000 1:7 a 2:2.0
                        $master crdt.zrem zset6352 1 1000 1:2 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6352 1 1000 1:6 a 2:3.0
                        $peer crdt.zincrby zset6352 1 1000 1:5 a 2:3.0
                        $peer crdt.zrem zset6352 1 1000 1:4 3:1:a,1:3:2:2.0
                    }
                    test "ad + bad ad fail" {
                        # 5
                        $master crdt.zincrby zset6353 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6353 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6353 1 1000 1:5 a 2:4.0
                        $peer crdt.zincrby zset6353 1 1000 1:4 a 2:3.0
                        $peer crdt.zrem zset6353 1 1000 1:2 3:1:a,1:2:2:2.0
                        
                    }
                    
                }
            }
            test "ba" {
                test "ba + null" {
                    $master crdt.zadd zset6400 1 1000 1:2 a 2:1.0
                    $master crdt.zincrby zset6400 1 1000 1:3 a 2:2.0
                    
                }
                test "ba + a" {
                    test "ba + a success" {
                        # 3
                        $master crdt.zadd zset6410 1 1000 1:2 a 2:1.0
                        $master crdt.zincrby zset6410 1 1000 1:3 a 2:2.0
                        $peer crdt.zincrby zset6410 1 1000 1:1 a 2:1.0
                         
                    }
                    test "ba + a fail" {
                        # 4
                        $master crdt.zadd zset6411 1 1000 1:2 a 2:1.0
                        $master crdt.zincrby zset6411 1 1000 1:3 a 2:2.0
                        $peer crdt.zincrby zset6411 1 1000 1:4 a 2:3.0
                        
                    }
                }
                test "ba + b" {
                    test "ba + b success" {
                        # 6
                        $master crdt.zadd zset6420 1 1000 1:2 a 2:2.0
                        $master crdt.zincrby zset6420 1 1000 1:3 a 2:4.0
                        $peer crdt.zadd zset6420 1 1000 1:1 a 2:3.0 
                    }
                    test "ba + b fail" {
                        # 7
                        $master crdt.zadd zset6421 1 1000 1:2 a 2:2.0
                        $master crdt.zincrby zset6421 1 1000 1:4 a 2:4.0
                        $peer crdt.zadd zset6421 1 1000 1:3 a 2:3.0 
                        
                    }
                }
                test "ba + ad" {
                    test "ba + ad success" {
                        # 4
                        $master crdt.zadd zset6430 1 1000 1:5 a 2:2.0
                        $master crdt.zincrby zset6430 1 1000 1:6 a 2:4.0
                        $peer crdt.zincrby zset6430 1 1000 1:4 a 2:3.0
                        $peer crdt.zrem zset6430 1 1000 1:3 3:1:a,1:2:2:2.0
                        
                    }
                    test "ba + ad fail" {
                        # 3
                        $master crdt.zadd zset6431 1 1000 1:2 a 2:2.0
                        $master crdt.zincrby zset6431 1 1000 1:4 a 2:4.0
                        $peer crdt.zincrby zset6431 1 1000 1:5 a 2:3.0
                        $peer crdt.zrem zset6431 1 1000 1:3 3:1:a,1:2:2:2.0
                        
                    }
                }
                test "ba + ba" {
                    test "ba + ba success" {
                        # 13
                        $master crdt.zadd zset6440 1 1000 1:5 a 2:4.0
                        $master crdt.zincrby zset6440 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6440 1 1000 1:3 a 2:3.0
                        $peer crdt.zincrby zset6440 1 1000 1:2 a 2:2.0
                        
                    }
                    test "ba + ba b fail" {
                        # 12
                        $master crdt.zadd zset6441 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6441 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6441 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6441 1 1000 1:2 a 2:2.0
                        
                        
                    }
                    test "ba + ba a fail" {
                        # 6
                        $master crdt.zadd zset6442 1 1000 1:5 a 2:4.0
                        $master crdt.zincrby zset6442 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6442 1 1000 1:3 a 2:3.0
                        $peer crdt.zincrby zset6442 1 1000 1:6 a 2:2.0
                        
                    }
                    test "ba + ba ba fail" {
                        # 5
                        $master crdt.zadd zset6443 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6443 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6443 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6443 1 1000 1:6 a 2:2.0
                    }
                }
                test "ba + bad" {
                    test "ba + bad success" {
                        # 12
                        $master crdt.zadd zset6450 1 1000 1:5 a 2:4.0
                        $master crdt.zincrby zset6450 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6450 1 1000 1:3 a 2:3.0
                        $peer crdt.zincrby zset6450 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6450 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                    }
                    test "ba + bad b fail" {
                        # 11
                        $master crdt.zadd zset6451 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6451 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6451 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6451 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6451 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                        
                    }
                    test "ba + bad a fail" {
                        # 5
                        $master crdt.zadd zset6452 1 1000 1:5 a 2:4.0
                        $master crdt.zincrby zset6452 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6452 1 1000 1:3 a 2:3.0
                        $peer crdt.zincrby zset6452 1 1000 1:6 a 2:2.0
                        $peer crdt.zrem zset6452 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                        
                    }
                    test "ba + bad ba fail" {
                        # 4
                        $master crdt.zadd zset6453 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6453 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6453 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6453 1 1000 1:6 a 2:2.0
                        $peer crdt.zrem zset6453 1 1000 1:1 3:1:a,1:1:2:1.0
                        # puts [$master crdt.datainfo zset6453]
                        # puts [$peer crdt.datainfo zset6453]
                    }
                }
            }
            test "bad" {
                test "bad + null" {
                    $master crdt.zadd zset6500 1 1000 1:3 a 2:4.0
                    $master crdt.zincrby zset6500 1 1000 1:4 a 2:9.0
                    $master crdt.zrem zset6500 1 1000 1:1 3:1:a,1:1:2:1.0
                    
                }
                test "bad + a" {
                    test "bad + a success" {
                        # 10
                        $master crdt.zadd zset6510 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6510 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6510 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6510 1 1000 1:2 a 2:1.0
                        # puts [$master crdt.datainfo zset6510]
                        # puts [$peer crdt.datainfo zset6510]
                    }
                    test "bad + a fail" {
                        # 4
                        $master crdt.zadd zset6511 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6511 1 1000 1:4 a 2:9.0
                        $master crdt.zrem zset6511 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6511 1 1000 1:7 a 2:1.0
                        
                    }
                }
                test "bad + b" {
                    test "bad + b success" {
                        # 10
                        $master crdt.zadd zset6520 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6520 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6520 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6520 1 1000 1:2 a 2:1.0
                        
                    }
                    test "bad + b fail" {
                        # 4
                        $master crdt.zadd zset6521 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6521 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6521 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6521 1 1000 1:7 a 2:1.0
                        
                    }
                }
                test "bad + ad" {
                    test "bad + ad success" {
                        # 9
                        $master crdt.zadd zset6530 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6530 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6530 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zincrby zset6530 1 1000 1:2 a 2:4.0
                        $peer crdt.zrem zset6530 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                    }
                    test "bad + ad a fail" {
                        # 6
                        $master crdt.zadd zset6531 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6531 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6531 1 1000 1:1 3:1:a,1:3:2:2.0
                        $peer crdt.zincrby zset6531 1 1000 1:5 a 2:4.0
                        $peer crdt.zrem zset6531 1 1000 1:1 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + ad d fail" {
                        # 10
                        $master crdt.zadd zset6532 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6532 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6532 1 1000 1:1 3:1:a,1:1:2:2.0
                        $peer crdt.zincrby zset6532 1 1000 1:3 a 2:4.0
                        $peer crdt.zrem zset6532 1 1000 1:2 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + ad ad fail" {
                        # 7
                        $master crdt.zadd zset6533 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6533 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6533 1 1000 1:1 3:1:a,1:1:2:2.0
                        $peer crdt.zincrby zset6533 1 1000 1:5 a 2:4.0
                        $peer crdt.zrem zset6533 1 1000 1:2 3:1:a,1:2:2:1.0
                    }
                }
                test "bad + ba" {
                    test "bad + ba success" {
                        # 9
                        $master crdt.zadd zset6540 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6540 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6540 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6540 1 1000 1:2 a 2:3.0
                        $peer crdt.zincrby zset6540 1 1000 1:3 a 2:6.0
                    }
                    test "bad + ba b fail" {
                        # 8
                        $master crdt.zadd zset6541 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6541 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6541 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6541 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6541 1 1000 1:3 a 2:5.0
                        
                    }
                    test "bad + ba a fail" {
                        # 7
                        $master crdt.zadd zset6542 1 1000 1:6 a 2:4.0
                        $master crdt.zincrby zset6542 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6542 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6542 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6542 1 1000 1:5 a 2:5.0
                        
                    }
                    test "bad + ba  ba fail" {
                        # 6
                        $master crdt.zadd zset6543 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6543 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6543 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6543 1 1000 1:5 a 2:3.0
                        $peer crdt.zincrby zset6543 1 1000 1:6 a 2:5.0
                    }
                }
                test "bad + bad" {
                    test "bad + bad success" {
                        # 9
                        $master crdt.zadd zset6550 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6550 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6550 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6550 1 1000 1:2 a 2:3.0
                        $peer crdt.zincrby zset6550 1 1000 1:3 a 2:6.0
                        $peer crdt.zrem zset6550 1 1000 1:2 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + bad  b fail" {
                        # 8
                        $master crdt.zadd zset6551 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6551 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6551 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6551 1 1000 1:8 a 2:3.0
                        $peer crdt.zincrby zset6551 1 1000 1:3 a 2:6.0
                        $peer crdt.zrem zset6551 1 1000 1:2 3:1:a,1:2:2:1.0
                    }
                    test "bad + bad  a fail" {
                        # 7
                        $master crdt.zadd zset6552 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6552 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6552 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6552 1 1000 1:2 a 2:3.0
                        $peer crdt.zincrby zset6552 1 1000 1:7 a 2:5.0
                        $peer crdt.zrem zset6552 1 1000 1:2 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + bad  d fail" {
                        # 7
                        $master crdt.zadd zset6553 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6553 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6553 1 1000 1:3 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6553 1 1000 1:6 a 2:3.0
                        $peer crdt.zincrby zset6553 1 1000 1:3 a 2:4.0
                        $peer crdt.zrem zset6553 1 1000 1:4 3:1:a,1:3:2:4.0
                    }
                    test "bad + bad  ba fail" {
                        # 8
                        $master crdt.zadd zset6554 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6554 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6554 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6554 1 1000 1:4 a 2:3.0
                        $peer crdt.zincrby zset6554 1 1000 1:6 a 2:6.0
                        $peer crdt.zrem zset6554 1 1000 1:2 3:1:a,1:2:2:2.0

                    }
                    test "bad + bad  bd fail" {
                        # 6
                        $master crdt.zadd zset6555 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6555 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6555 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6555 1 1000 1:8 a 2:3.0
                        $peer crdt.zincrby zset6555 1 1000 1:4 a 2:6.0
                        $peer crdt.zrem zset6555 1 1000 1:3 3:1:a,1:3:2:4.0
                    }
                    test "bad + bad  ad fail" {
                        # 6
                        $master crdt.zadd zset6556 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6556 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6556 1 1000 1:4 3:1:a,1:3:2:2.0
                        $peer crdt.zadd zset6556 1 1000 1:2 a 2:3.0
                        $peer crdt.zincrby zset6556 1 1000 1:7 a 2:6.0
                        $peer crdt.zrem zset6556 1 1000 1:5 3:1:a,1:4:2:4.0
                    }
                    test "bad + bad  bad fail" {
                        # 7
                        $master crdt.zadd zset6557 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6557 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6557 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6557 1 1000 1:8 a 2:3.0
                        $peer crdt.zincrby zset6557 1 1000 1:6 a 2:6.0
                        $peer crdt.zrem zset6557 1 1000 1:5 3:1:a,1:5:2:2.0
                        # puts [$master crdt.datainfo zset6557]
                        # puts [$peer crdt.datainfo zset6557]
                    }
                }
            }
        }
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        
        # wait_for_peer_sync $peer
        after 5000
        # print_log_file $peer_log
        wait_for_peer_sync $master
        test "after" {
            test "a" {
                test "a + null" {
                    assert_equal [$master crdt.datainfo zset6100] [$peer crdt.datainfo zset6100]
                }
                test "a + a" {
                    test "a + a success" {
                        $peer zscore zset6101 a 
                    } {1}
                    test "a + a fail" {
                        $peer zscore zset6102 a 
                    } {2}
                }
                test "a + b" {
                    $peer zscore zset6120 a 
                } {3}
                test "a + ba" {
                    test "before a + ba success" {
                        $peer zscore zset6130 a
                    } {3}
                    test "before a + ba fail" {
                        $peer zscore zset6131 a
                    } {4}
                } 
                test "a + ad" {
                    test "before a + ad success" {
                        $peer zscore zset6140 a
                    } {2}
                    test "before a + ad fail" {
                        $peer zscore zset6141 a
                    } {1}
                } 
                test "a + bad" {
                    test "before a + bad success" {
                        $peer zscore zset6150 a
                    } {4}
                    test "before a + bad fail" {
                        $peer zscore zset6151 a
                    } {3}
                } 
            }
            test "b" {
                test "b + null" {
                    assert_equal [$master crdt.datainfo zset6200] [$peer crdt.datainfo zset6200]
                }
                test "b + a" {
                    $peer zscore zset6210 a
                } {2}
                test "b + b" {
                    test "b + b success" {
                        $peer zscore zset6220 a
                    } {1}
                    test "b + b fail" {
                        $peer zscore zset6221 a
                    } {2}
                }
                test "b + ad" {
                    $peer zscore zset6230 a
                } {1}
                test "b + ba" {
                    test "b + ba success" {
                        $peer zscore zset6240 a
                    } {3}
                    test "b + ba fail" {
                        $peer zscore zset6241 a
                    } {4}
                } 
                test "b + bad" {
                    test "b + bad success" {
                        $peer zscore zset6250 a
                    } {2}
                    test "b + bad fail" {
                        $peer zscore zset6251 a
                    } {3}
                }
            }

            test "ad" {
                test "ad + null1" {
                    assert_equal [$master crdt.datainfo zset6300] [$peer crdt.datainfo zset6300]
                }
                test "ad + a" {
                    test "ad + a success" {
                        $peer zscore zset6310 a
                    } {1}
                    test "ad + a fail" {
                        $peer zscore zset6311 a
                    } {2}
                }
                test "ad + b" {
                    $peer zscore zset6320 a
                } {1}
                test "ad + ba" {
                    test "ad + ba success" {
                        $peer zscore zset6330 a
                    } {1}
                    test "ad + ba fail" {
                        $peer zscore zset6331 a
                    } {2}
                }
                test "ad + ad" {
                    test "ad + ad success" {
                        $peer zscore zset6340 a
                    } {3}
                    test "ad + ad a fail" {
                        $peer zscore zset6341 a
                    } {2}
                    test "ad + ad d fail" {
                        $peer zscore zset6342 a
                    } {0}
                    test "ad + ad ad fail" {
                        $peer zscore zset6343 a
                    } {1}
                }
                test "ad + bad" {
                    test "ad + bad success" {
                        $peer zscore zset6350 a
                    } {6}
                    test "ad + bad a fail" {
                        
                        $peer zscore zset6351 a
                    } {4}
                    test "ad + bad d fail" {
                        $peer zscore zset6352 a
                    } {3}
                    test "ad + bad ad fail" {
                        $peer zscore zset6353 a
                    } {5}
                }
            }

            test "ba" {
                test "ba + null" {
                    assert_equal [$master crdt.datainfo zset6400] [$peer crdt.datainfo zset6400]
                }
                test "ba + a" {
                    test "ba + a success" {
                        $peer zscore zset6410 a
                    } {3}
                    test "ba + a fail" {
                        
                        $peer zscore zset6411 a
                    } {4}
                }
                test "ba + b" {
                    test "ba + b success" {
                        
                        $peer zscore zset6420 a
                    } {6}
                    test "ba + b fail" {
                        
                        $peer zscore zset6421 a
                    } {7}
                }
                test "ba + ad" {
                    test "ba + ad success" {
                        
                        $peer zscore zset6430 a
                    } {4}
                    test "ba + ad fail" {
                        
                       $peer zscore zset6431 a
                    } {1}
                }
                test "ba + ba" {
                    test "ba + ba success" {
                        $peer zscore zset6440 a
                    } {13}
                    test "ba + ba b fail" {
                        $peer zscore zset6441 a
                    } {12}
                    test "ba + ba a fail" {
                        $peer zscore zset6442 a
                    } {6}
                    test "ba + ba ba fail" {
                        
                        $peer zscore zset6443 a
                    } {5}
                }
                test "ba + bad" {
                   test "ba + bad success" {
                       
                        $peer zscore zset6450 a
                    } {12}
                    test "ba + bad b fail" {
                        
                        $peer zscore zset6451 a
                    } {11}
                    test "ba + bad a fail" {
                        $peer zscore zset6452 a
                    } {5}
                    test "ba + bad ba fail" {

                        $peer zscore zset6453 a
                    } {4}
                }
            }
            test "bad" {
                test "bad + null" {
                    assert_equal [$master crdt.datainfo zset6500] [$peer crdt.datainfo zset6500]
                }
                test "bad + a" {
                    test "bad + a success" {
                        $peer zscore zset6510 a
                    } {10}
                    test "bad + a fail" {
                        $peer zscore zset6511 a
                    } {4}
                }
                test "bad + b" {
                    test "bad + b success" {
                        $peer zscore zset6520 a
                    } {10}
                    test "bad + b fail" {
                        $peer zscore zset6521 a
                    } {4}
                }
                test "bad + ad" {
                    test "bad + ad success" {
                        $peer zscore zset6530 a
                    } {9}
                    test "bad + ad a fail" {
                        $peer zscore zset6531 a
                    } {6}
                    test "bad + ad d fail" {
                        $peer zscore zset6532 a
                    } {10}
                    test "bad + ad ad fail" {
                        $peer zscore zset6533 a
                    } {7}
                }
                test "bad + ba" {
                    test "bad + ba success" {
                        $peer zscore zset6540 a
                    } {9}
                    test "bad + ba b fail" {
                        $peer zscore zset6541 a
                    } {8}
                    test "bad + ba a fail" {
                        $peer zscore zset6542 a
                    } {7}
                    test "bad + ba ba fail" {
                        $peer zscore zset6543 a
                    } {6}
                }
                test "bad + bad" {
                    test "bad + bad success" {
                        $peer zscore zset6550 a
                    } {9}
                    test "bad + bad b fail" {
                        $peer zscore zset6551 a
                    } {8}
                    test "bad + bad  a fail" {
                        $peer zscore zset6552 a
                    } {7}
                    test "bad + bad  d fail" {
                        $peer zscore zset6553 a
                    } {7}
                    test "bad + bad  ba fail" {
                        $peer zscore zset6554 a
                    } {8}
                    test "bad + bad  bd fail" {
                        $peer zscore zset6555 a
                    } {6}
                    test "bad + bad  ad fail" {
                        $peer zscore zset6556 a
                    } {6}
                    test "bad + bad  bad fail" {
                        # puts [$peer crdt.datainfo zset6557]
                        $peer zscore zset6557 a
                    } {7}
                }
            }
        }


    }
}


start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 9} config {crdt.conf} module {crdt.so} } {
        set peer_gc [srv 0 client]
        $peer_gc peerof $master_gid $master_host $master_port
        start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            set peer [srv 0 client]
            set peer_gid 2 
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_log [srv 0 stdout]
            $peer config crdt.set repl-diskless-sync-delay 1
            $peer config set repl-diskless-sync-delay 1
        
            test "before" {
                test "b" {
                    test "b + null" {
                        $master crdt.zadd zset7000 1 1000 1:1 a 2:1.0 
                        $master crdt.zrem zset7000 1 1000 1:2 3:1:a 
                        
                    }
                    test "b + ad" {
                        $master crdt.zadd zset7010 1 1000 1:1 a 2:1.0 
                        $master crdt.zrem zset7010 1 1000 1:4 3:1:a 

                        $peer crdt.zincrby zset7010 1 1000 1:2 a 2:1.0 
                        $peer crdt.zrem zset7010 1 1000 1:3 3:1:a,1:2:2:1.0 

    
                    }
                    test "b + bad" {
                        test "b + bad success" {
                            $master crdt.zadd zset7020 1 1000 1:1 a 2:1.0 
                            $master crdt.zrem zset7020 1 1000 1:4 3:1:a 

                            $master crdt.zadd zset7020 1 1000 1:1 a 2:1.0 
                            $peer crdt.zincrby zset7020 1 1000 1:2 a 2:1.0 
                            $peer crdt.zrem zset7020 1 1000 1:3 3:1:a,1:2:2:1.0 
                        }
                        test "b + bad fail" {
                            $master crdt.zadd zset7021 1 1000 1:1 a 2:1.0 
                            $master crdt.zrem zset7021 1 1000 1:2 3:1:a 

                            $master crdt.zadd zset7021 1 1000 1:1 a 2:1.0 
                            $peer crdt.zincrby zset7021 1 1000 1:2 a 2:1.0 
                            $peer crdt.zrem zset7021 1 1000 1:3 3:1:a,1:2:2:1.0
                        }
                        
                    }
                }
                test "ad" {
                    test "ad + null" {
                        
                        $master crdt.zincrby zset7100 1 1000 1:1 a 2:1.0 
                        $master crdt.zrem zset7100 1 1000 1:2 3:1:a,1:2:2:1.0 
                    }
                    test "ad + b" {
                        $master crdt.zincrby zset7110 1 1000 1:2 a 2:1.0 
                        $master crdt.zrem zset7110 1 1000 1:3 3:1:a,1:2:2:1.0 

                        $peer crdt.zadd zset7110 1 1000 1:1 a 2:1.0 
                        $peer crdt.zrem zset7110 1 1000 1:4 3:1:a  
                        
                    }
                    test "ad + bad" {
                        test "ad + bad sucess" {
                            $master crdt.zincrby zset7120 1 1000 1:4 a 2:1.0 
                            $master crdt.zrem zset7120 1 1000 1:5 3:1:a,1:4:2:1.0 

                            $peer crdt.zadd zset7120 1 1000 1:1 a 2:1.0 
                            $peer crdt.zincrby zset7120 1 1000 1:2 a 2:1.0
                            $peer crdt.zrem zset7120 1 1000 1:3 3:1:a,1:2:2:1.0
                        }
                        test "ad + bad fail" {
                            $master crdt.zincrby zset7121 1 1000 1:2 a 2:1.0 
                            $master crdt.zrem zset7121 1 1000 1:3 3:1:a,1:2:2:1.0 

                            $peer crdt.zadd zset7121 1 1000 1:1 a 2:1.0 
                            $peer crdt.zincrby zset7121 1 1000 1:4 a 2:1.0
                            $peer crdt.zrem zset7121 1 1000 1:5 3:1:a,1:4:2:1.0
                            
                        }
                    }
                }
                test "bad" {
                    test "bad + null" {
                        $master crdt.zadd zset7200 1 1000 1:1 a 2:1.0 
                        $master crdt.zincrby zset7200 1 1000 1:2 a 2:1.0 
                        $master crdt.zrem zset7200 1 1000 1:2 3:1:a,1:2:2:1.0
                    }
                    test "bad + b" {
                        test "bad + b success" {
                            $master crdt.zadd zset7210 1 1000 1:5 a 2:1.0 
                            $master crdt.zincrby zset7210 1 1000 1:2 a 2:1.0 
                            $master crdt.zrem zset7210 1 1000 1:5 3:1:a,1:2:2:1.0

                            $peer crdt.zadd zset7210 1 1000 1:1 a 2:1.0 
                            $peer crdt.zrem zset7210 1 1000 1:4 3:1:a 
                        }

                        test "bad + b fail" {
                            $master crdt.zadd zset7211 1 1000 1:1 a 2:1.0 
                            $master crdt.zincrby zset7211 1 1000 1:2 a 2:1.0 
                            $master crdt.zrem zset7211 1 1000 1:2 3:1:a,1:2:2:1.0

                            $peer crdt.zadd zset7211 1 1000 1:1 a 2:1.0 
                            $peer crdt.zrem zset7211 1 1000 1:4 3:1:a 
                        }
                        

                        
                    }
                    test "bad + ad" {
                        test "bad + ad success" {
                            $master crdt.zadd zset7220 1 1000 1:1 a 2:1.0 
                            $master crdt.zincrby zset7220 1 1000 1:7 a 2:1.0 
                            $master crdt.zrem zset7220 1 1000 1:8 3:1:a,1:7:2:1.0

                            $master crdt.zincrby zset7220 1 1000 1:4 a 2:1.0 
                            $master crdt.zrem zset7220 1 1000 1:5 3:1:a,1:4:2:1.0 
                        }   
                        test "bad + ad fail" {
                            $master crdt.zadd zset7221 1 1000 1:1 a 2:1.0 
                            $master crdt.zincrby zset7221 1 1000 1:2 a 2:1.0 
                            $master crdt.zrem zset7221 1 1000 1:2 3:1:a,1:2:2:1.0

                            $master crdt.zincrby zset7221 1 1000 1:4 a 2:1.0 
                            $master crdt.zrem zset7221 1 1000 1:5 3:1:a,1:4:2:1.0 
                        }
                        
                    }
                }
                
            }
            $peer peerof $master_gid $master_host $master_port
            wait_for_peer_sync $peer
            test "after" {
                test "b" {
                    test "b + null" {
                        assert_equal [$master crdt.datainfo zset7000] [$peer crdt.datainfo zset7000]
                    }
                    test "b + ad" {
                        $peer crdt.zadd zset7010 1 1000 1:2 a 2:1.0 
                        $peer zscore zset7010 a
                    } {}
                    test "b + bad" {
                        test "b + bad success" {
                            $peer crdt.zadd zset7020 1 1000 1:4 a 2:1.0 
                            $peer zscore zset7020 a
                        } {}

                        test "b + bad fail" {
                            $peer crdt.zadd zset7020 1 1000 1:3 a 2:1.0 
                            $peer zscore zset7020 a
                        } {}
                        
                    } 
                }
                test "ad" {
                    test "ad + null" {
                    assert_equal [$master crdt.datainfo zset7100] [$peer crdt.datainfo zset7100]
                    }
                    test "ad + b" {
                        $peer crdt.zadd zset7110 1 1000 1:3 a 2:1.0 
                        $peer zscore zset7110 a
                        
                    } {}
                    test "ad + bad" {
                    test "ad + bad success" {
                        $peer crdt.zadd zset7120 1 1000 1:2 a 2:1.0 
                        $peer zscore zset7120 a
                    } {}
                    test "ad + bad fail" {
                        $peer crdt.zadd zset7121 1 1000 1:4 a 2:1.0 
                        $peer zscore zset7121 a
                    } {}
                    }
                }
                test "bad" {
                    test "bad + null" {
                        assert_equal [$master crdt.datainfo zset7200] [$peer crdt.datainfo zset7200]
                    }
                    test "bad + b" {
                        test "bad + b success" {
                            $peer crdt.zadd zset7210 1 1000 1:5 a 2:1.0 
                            $peer zscore zset7210 a
                        } {}
                        test "bad + b fail" {
                            $peer crdt.zadd zset7211 1 1000 1:4 a 2:1.0 
                            $peer zscore zset7211 a
                        } {}
                    }
                    test "bad + ad" {
                        test "bad + ad success" {
                            $peer crdt.zadd zset7220 1 1000 1:8 a 2:1.0 
                            $peer zscore zset7220 a
                        } {}
                        test "bad + ad fail" {
                            $peer crdt.zadd zset7221 1 1000 1:5 a 2:1.0 
                            $peer zscore zset7221 a
                        } {}
                    }
                }
            }

        }
    }
}


start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 9} config {crdt.conf} module {crdt.so} } {
        set peer_gc [srv 0 client]
        $peer_gc peerof $master_gid $master_host $master_port
        start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            set peer [srv 0 client]
            set peer_gid 2
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_log [srv 0 stdout]
            $peer config crdt.set repl-diskless-sync-delay 1
            $peer config set repl-diskless-sync-delay 1
        
            test "before" {
                test "value + tomstone" {
                    test "a" {
                        test "a + tb " {
                            $master crdt.zincrby zset8000 1 1000 1:2 a 2:1.0 
                            $peer crdt.zadd zset8000 1 1000 1:3 a 2:1.0
                            $peer crdt.zrem zset8000 1 1000 1:4 3:1:a
                        }
                        test "a + tad" {
                            test "a + tad success" {
                                $master crdt.zincrby zset8010 1 1000 1:4 a 2:5.0 
                                $peer crdt.zincrby zset8010 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8010 1 1000 1:3 3:1:a,1:2:2:1.0 
                            }
                            test "a + tad fail" {
                                $master crdt.zincrby zset8011 1 1000 1:1 a 2:2.0 
                                $peer crdt.zincrby zset8011 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8011 1 1000 1:3 3:1:a,1:2:2:1.0 
                            }
                            
                        }
                        test "a + tbad" {
                            test "a + tbad success" {
                                # 4
                                $master crdt.zincrby zset8020 1 1000 1:4 a 2:5.0 
                                $peer crdt.zadd zset8020 1 1000 1:1 a 2:4.0
                                $peer crdt.zincrby zset8020 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8020 1 1000 1:3 3:1:a,1:2:2:1.0 
                            }
                            test "a + tbad fail" {
                                # {}
                                $master crdt.zincrby zset8021 1 1000 1:1 a 2:5.0 
                                $peer crdt.zadd zset8021 1 1000 1:2 a 2:4.0
                                $peer crdt.zincrby zset8021 1 1000 1:3 a 2:1.0 
                                $peer crdt.zrem zset8021 1 1000 1:4 3:1:a,1:3:2:1.0 
                            }
                        }
                    }
                    test "b" {
                        test "b + tb " {
                            test "b + tb success" {
                                # 5
                                $master crdt.zadd zset8100 1 1000 1:5 a 2:5.0
                                $peer crdt.zadd zset8100 1 1000 1:3 a 2:1.0
                                $peer crdt.zrem zset8100 1 1000 1:4 3:1:a
                                
                                
                            } 
                            test "b + tb fail" {
                                # {}
                                $master crdt.zadd zset8101 1 1000 1:1 a 2:3.0
                                $peer crdt.zadd zset8101 1 1000 1:3 a 2:1.0
                                $peer crdt.zrem zset8101 1 1000 1:4 3:1:a
                                
                            }
                        }
                        test "b + ad" {
                            $master crdt.zadd zset8110 1 1000 1:5 a 2:5.0
                            $peer crdt.zincrby zset8110 1 1000 1:2 a 2:1.0 
                            $peer crdt.zrem zset8110 1 1000 1:3 3:1:a,1:2:2:1.0 
                        }
                        test "b + bad" {
                            test "b + tbad success" {
                                $master crdt.zadd zset8120 1 1000 1:5 a 2:7.0
                                $peer crdt.zadd zset8120 1 1000 1:1 a 2:4.0
                                $peer crdt.zincrby zset8120 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8120 1 1000 1:3 3:1:a,1:2:2:1.0 
                            }
                            test "b + tbad fail" {
                                $master crdt.zadd zset8121 1 1000 1:1 a 2:5.0
                                $peer crdt.zadd zset8121 1 1000 1:2 a 2:4.0
                                $peer crdt.zincrby zset8121 1 1000 1:3 a 2:1.0 
                                $peer crdt.zrem zset8121 1 1000 1:4 3:1:a,1:3:2:1.0 
                            }
                        }
                    }
                    test "ba" {
                        test "ba + tb " {
                            test "ba + tb success" {

                                # 6
                                $master crdt.zadd zset8200 1 1000 1:5 a 2:5.0
                                $master crdt.zincrby zset8200 1 1000 1:2 a 2:1.0 

                                $peer crdt.zadd zset8200 1 1000 1:3 a 2:1.0
                                $peer crdt.zrem zset8200 1 1000 1:4 3:1:a
                                
                                
                            } 
                            test "ba + tb fail" {
                                # 1
                                $master crdt.zadd zset8201 1 1000 1:2 a 2:3.0
                                $master crdt.zincrby zset8201 1 1000 1:2 a 2:1.0 
                                $peer crdt.zadd zset8201 1 1000 1:3 a 2:1.0
                                $peer crdt.zrem zset8201 1 1000 1:4 3:1:a
                                
                                
                            }
                        }
                        test "ba + tad" {
                            test "ba + tad success" {
                                # 6
                                $master crdt.zadd zset8210 1 1000 1:5 a 2:5.0
                                $master crdt.zincrby zset8210 1 1000 1:4 a 2:2.0 
                                $peer crdt.zincrby zset8210 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8210 1 1000 1:3 3:1:a,1:2:2:1.0 
                            }
                            test "ba + tad fail" {
                                # 7
                                $master crdt.zadd zset8211 1 1000 1:5 a 2:7.0
                                $master crdt.zincrby zset8211 1 1000 1:1 a 2:2.0 
                                $peer crdt.zincrby zset8211 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8211 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            }
                            
                        }
                        test "ba + bad" {
                            test "ba + tbad success" {
                                # 8
                                $master crdt.zadd zset8220 1 1000 1:5 a 2:7.0
                                $master crdt.zincrby zset8220 1 1000 1:4 a 2:2.0 
                                $peer crdt.zadd zset8220 1 1000 1:1 a 2:4.0
                                $peer crdt.zincrby zset8220 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8220 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            }
                            test "ba + tbad b fail" {
                                # 1
                                $master crdt.zadd zset8221 1 1000 1:1 a 2:5.0
                                $master crdt.zincrby zset8221 1 1000 1:4 a 2:2.0 
                                $peer crdt.zadd zset8221 1 1000 1:2 a 2:4.0
                                $peer crdt.zincrby zset8221 1 1000 1:3 a 2:1.0 
                                $peer crdt.zrem zset8221 1 1000 1:4 3:1:a,1:3:2:1.0 
                                
                            }
                            test "ba + tbad a fail" {
                                # 5
                                $master crdt.zadd zset8222 1 1000 1:5 a 2:5.0
                                $master crdt.zincrby zset8222 1 1000 1:1 a 2:2.0 
                                $peer crdt.zadd zset8222 1 1000 1:2 a 2:4.0
                                $peer crdt.zincrby zset8222 1 1000 1:3 a 2:1.0 
                                $peer crdt.zrem zset8222 1 1000 1:4 3:1:a,1:3:2:1.0 
                                
                            }
                            test "ba + tbad ba fail" {
                                #  {}
                                $master crdt.zadd zset8223 1 1000 1:2 a 2:5.0
                                $master crdt.zincrby zset8223 1 1000 1:1 a 2:2.0 
                                $peer crdt.zadd zset8223 1 1000 1:3 a 2:4.0
                                $peer crdt.zincrby zset8223 1 1000 1:4 a 2:1.0 
                                $peer crdt.zrem zset8223 1 1000 1:5 3:1:a,1:4:2:1.0 
                                
                            }
                        }
                    }
                    test "ad" {
                        test "ad + tb " {
                            test "ad + tb success" {

                                # 3
                                $master crdt.zincrby zset8300 1 1000 1:7 a 2:5.0
                                $master crdt.zrem zset8300 1 1000 1:6 3:1:a,1:6:2:2.0 

                                $peer crdt.zadd zset8300 1 1000 1:3 a 2:1.0
                                $peer crdt.zrem zset8300 1 1000 1:4 3:1:a
                                
                                
                            } 
                        }
                        test "ad + tad" {
                            test "ad + tad success" {
                                # 3
                                $master crdt.zincrby zset8310 1 1000 1:7 a 2:5.0
                                $master crdt.zrem zset8310 1 1000 1:6 3:1:a,1:6:2:2.0 
                                $peer crdt.zincrby zset8310 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8310 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            }
                            test "ad + tad ad fail" {
                                # {}
                                $master crdt.zincrby zset8311 1 1000 1:5 a 2:5.0
                                $master crdt.zrem zset8311 1 1000 1:4 3:1:a,1:4:2:2.0 
                                $peer crdt.zincrby zset8311 1 1000 1:7 a 2:1.0 
                                $peer crdt.zrem zset8311 1 1000 1:8 3:1:a,1:7:2:1.0 
    
                            }
                            test "ad + tad a success" {
                                # {}
                                $master crdt.zincrby zset8312 1 1000 1:10 a 2:5.0
                                $master crdt.zrem zset8312 1 1000 1:4 3:1:a,1:4:2:2.0 
                                $peer crdt.zincrby zset8312 1 1000 1:7 a 2:1.0 
                                $peer crdt.zrem zset8312 1 1000 1:8 3:1:a,1:7:2:1.0 
    
                            }
                            
                        }
                        test "ad + tbad" {
                            test "ad + tbad success" {
                                # 3
                                $master crdt.zincrby zset8320 1 1000 1:5 a 2:5.0
                                $master crdt.zrem zset8320 1 1000 1:4 3:1:a,1:3:2:2.0 
                                $peer crdt.zadd zset8320 1 1000 1:1 a 2:4.0
                                $peer crdt.zincrby zset8320 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8320 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                                
                            }
                            test "ad + tbad ad fail" {
                                #  {}
                                $master crdt.zincrby zset8321 1 1000 1:2 a 2:5.0
                                $master crdt.zrem zset8321 1 1000 1:1 3:1:a,1:1:2:2.0 
                                $peer crdt.zadd zset8321 1 1000 1:3 a 2:4.0
                                $peer crdt.zincrby zset8321 1 1000 1:4 a 2:1.0 
                                $peer crdt.zrem zset8321 1 1000 1:5 3:1:a,1:4:2:1.0 
                                
                            }
                            test "ad + tbad a success" {
                                #  {}
                                $master crdt.zincrby zset8322 1 1000 1:10 a 2:5.0
                                $master crdt.zrem zset8322 1 1000 1:1 3:1:a,1:1:2:2.0 
                                $peer crdt.zadd zset8322 1 1000 1:3 a 2:4.0
                                $peer crdt.zincrby zset8322 1 1000 1:4 a 2:1.0 
                                $peer crdt.zrem zset8322 1 1000 1:5 3:1:a,1:4:2:1.0 
                                
                            }
                        }
                    }
                    test "bad" {
                        test "bad + tb" {
                            test "bad + tb success" {

                                # 4
                                $master crdt.zadd zset8400 1 1000 1:8 a 2:1.0
                                $master crdt.zincrby zset8400 1 1000 1:7 a 2:5.0
                                $master crdt.zrem zset8400 1 1000 1:6 3:1:a,1:6:2:2.0 

                                $peer crdt.zadd zset8400 1 1000 1:3 a 2:1.0
                                $peer crdt.zrem zset8400 1 1000 1:4 3:1:a

                                
                                
                            }
                            test "bad + tb fail" {
                                # {}
                                $master crdt.zadd zset8401 1 1000 1:5 a 2:3.0
                                $master crdt.zincrby zset8401 1 1000 1:2 a 2:4.0
                                $master crdt.zrem zset8401 1 1000 1:3 3:1:a,1:1:2:5.0 
                                
                                $peer crdt.zadd zset8401 1 1000 1:6 a 2:1.0
                                $peer crdt.zrem zset8401 1 1000 1:7 3:1:a
                                
                            }
                        }
                        test "bad + tad" {
                            test "bad + tad success" {

                                # 4
                                $master crdt.zadd zset8410 1 1000 1:8 a 2:1.0
                                $master crdt.zincrby zset8410 1 1000 1:7 a 2:5.0
                                $master crdt.zrem zset8410 1 1000 1:6 3:1:a,1:6:2:2.0 

                                $peer crdt.zincrby zset8410 1 1000 1:2 a 2:1.0 
                                $peer crdt.zrem zset8410 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                                
                            }
                            test "bad + tad fail" {
                                # 3
                                $master crdt.zadd zset8411 1 1000 1:5 a 2:3.0
                                $master crdt.zincrby zset8411 1 1000 1:2 a 2:4.0
                                $master crdt.zrem zset8411 1 1000 1:3 3:1:a,1:1:2:5.0 
                                
                                $peer crdt.zincrby zset8411 1 1000 1:3 a 2:1.0 
                                $peer crdt.zrem zset8411 1 1000 1:4 3:1:a,1:3:2:1.0 
                            }
                            test "bad + tad a success" {
                                # 3
                                $master crdt.zadd zset8412 1 1000 1:5 a 2:3.0
                                $master crdt.zincrby zset8412 1 1000 1:6 a 2:4.0
                                $master crdt.zrem zset8412 1 1000 1:3 3:1:a,1:1:2:5.0 
                                
                                $peer crdt.zincrby zset8412 1 1000 1:3 a 2:1.0 
                                $peer crdt.zrem zset8412 1 1000 1:4 3:1:a,1:3:2:1.0 
                            }

                        }
                        test "bad + tbad" {
                            test "bad + tad success" {

                                # 4
                                $master crdt.zadd zset8420 1 1000 1:8 a 2:1.0
                                $master crdt.zincrby zset8420 1 1000 1:7 a 2:5.0
                                $master crdt.zrem zset8420 1 1000 1:6 3:1:a,1:6:2:2.0 

                                $peer crdt.zadd zset8420 1 1000 1:3 a 2:4.0
                                $peer crdt.zincrby zset8420 1 1000 1:4 a 2:1.0 
                                $peer crdt.zrem zset8420 1 1000 1:5 3:1:a,1:4:2:1.0 
                                
                                
                            }
                            test "bad + tbad b fail" {
                                # 3
                                $master crdt.zadd zset8421 1 1000 1:5 a 2:3.0
                                $master crdt.zincrby zset8421 1 1000 1:8 a 2:4.0
                                $master crdt.zrem zset8421 1 1000 1:4 3:1:a,1:1:2:5.0 
                                
                                $peer crdt.zadd zset8421 1 1000 1:3 a 2:4.0
                                $peer crdt.zincrby zset8421 1 1000 1:4 a 2:1.0 
                                $peer crdt.zrem zset8421 1 1000 1:5 3:1:a,1:4:2:1.0 
                                
                                
                            }
                            test "bad + tbad ad fail" {
                                # 3
                                $master crdt.zadd zset8422 1 1000 1:7 a 2:3.0
                                $master crdt.zincrby zset8422 1 1000 1:2 a 2:4.0
                                $master crdt.zrem zset8422 1 1000 1:3 3:1:a,1:1:2:5.0 
                                
                                $peer crdt.zadd zset8422 1 1000 1:3 a 2:4.0
                                $peer crdt.zincrby zset8422 1 1000 1:4 a 2:1.0 
                                $peer crdt.zrem zset8422 1 1000 1:5 3:1:a,1:4:2:1.0 

                                
                                
                            }
                            test "bad + tbad bad fail" {
                                # 3
                                $master crdt.zadd zset8423 1 1000 1:5 a 2:3.0
                                $master crdt.zincrby zset8423 1 1000 1:2 a 2:4.0
                                $master crdt.zrem zset8423 1 1000 1:3 3:1:a,1:1:2:5.0 
                                
                                $peer crdt.zadd zset8423 1 1000 1:6 a 2:4.0
                                $peer crdt.zincrby zset8423 1 1000 1:7 a 2:1.0 
                                $peer crdt.zrem zset8423 1 1000 1:8 3:1:a,1:7:2:1.0 
                                
                                
                            }
                        }
                    }
                }

                test "tombstone + value" {
                    test "b" {
                        test "tb + a" {
                            $master crdt.zadd zset9000 1 1000 1:3 a 2:1.0
                            $master crdt.zrem zset9000 1 1000 1:4 3:1:a
                            $peer crdt.zincrby zset9000 1 1000 1:2 a 2:1.0 
                            
                        }
                        test "tb + b" {
                            test "tb + b success" {
                                $master crdt.zadd zset9010 1 1000 1:3 a 2:1.0
                                $master crdt.zrem zset9010 1 1000 1:4 3:1:a

                                $peer crdt.zadd zset9010 1 1000 1:2 a 2:5.0
                            } 
                            test "tb + b fail " {
                                $master crdt.zadd zset9011 1 1000 1:3 a 2:1.0
                                $master crdt.zrem zset9011 1 1000 1:4 3:1:a

                                $peer crdt.zadd zset9011 1 1000 1:5 a 2:5.0
                                
                            } 
                            
                        }
                        test "tb + ad" {
                            $master crdt.zadd zset9020 1 1000 1:3 a 2:1.0
                            $master crdt.zrem zset9020 1 1000 1:4 3:1:a

                            $peer crdt.zincrby zset9020 1 1000 1:7 a 2:5.0
                            $peer crdt.zrem zset9020 1 1000 1:6 3:1:a,1:6:2:2.0 
                            
                        }
                        test "tb + ba" {
                            test "tb + ba success" {
                                # 1
                                $master crdt.zadd zset9030 1 1000 1:7 a 2:1.0
                                $master crdt.zrem zset9030 1 1000 1:8 3:1:a

                                $peer crdt.zadd zset9030 1 1000 1:5 a 2:5.0
                                $peer crdt.zincrby zset9030 1 1000 1:2 a 2:1.0 
                                
                            }
                            test "tb + ba fail" {
                                $master crdt.zadd zset9031 1 1000 1:3 a 2:1.0
                                $master crdt.zrem zset9031 1 1000 1:4 3:1:a

                                $peer crdt.zadd zset9031 1 1000 1:5 a 2:5.0
                                $peer crdt.zincrby zset9031 1 1000 1:2 a 2:1.0 
                                
                            }
                        }
                        test "tb + bad" {
                            test "tb + bad success" {
                                $master crdt.zadd zset9040 1 1000 1:10 a 2:1.0
                                $master crdt.zrem zset9040 1 1000 1:11 3:1:a

                                $peer crdt.zadd zset9040 1 1000 1:8 a 2:2.0
                                $peer crdt.zincrby zset9040 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9040 1 1000 1:6 3:1:a,1:6:2:2.0 

                            }
                            test "tb + bad fail" {
                                $master crdt.zadd zset9041 1 1000 1:1 a 2:1.0
                                $master crdt.zrem zset9041 1 1000 1:2 3:1:a

                                $peer crdt.zadd zset9041 1 1000 1:8 a 2:2.0
                                $peer crdt.zincrby zset9041 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9041 1 1000 1:6 3:1:a,1:6:2:2.0 
                                
                            }
                            
                        }
                    }
                    test "tad" {
                        test "tad + a" {
                            test "tad + a success" {
                                $master crdt.zincrby zset9100 1 1000 1:5 a 2:1.0 
                                $master crdt.zrem zset9100 1 1000 1:6 3:1:a,1:5:2:1.0 
                                $peer crdt.zincrby zset9100 1 1000 1:4 a 2:5.0 
                            }
                            test "tad + a fail" {
                                $master crdt.zincrby zset9101 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9101 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zincrby zset9101 1 1000 1:4 a 2:5.0 
                            }
                        }
                        test "tad + b" {
                            
                            $master crdt.zincrby zset9110 1 1000 1:5 a 2:1.0 
                            $master crdt.zrem zset9110 1 1000 1:6 3:1:a,1:5:2:1.0 

                            $peer crdt.zadd zset9110 1 1000 1:4 a 2:5.0 
                            

                        }
                        test "tad + ad" {
                            test "tad + ad success" {
                                $peer crdt.zincrby zset9120 1 1000 1:3 a 2:5.0
                                $peer crdt.zrem zset9120 1 1000 1:2 3:1:a,1:1:2:2.0 
                                $master crdt.zincrby zset9120 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9120 1 1000 1:7 3:1:a,1:6:2:1.0 

                            
                            }
                            test "tad + ad d success" {
                                # 4
                                $peer crdt.zincrby zset9121 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9121 1 1000 1:1 3:1:a,1:1:2:2.0 
                                $master crdt.zincrby zset9121 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9121 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            }
                            test "tad + ad d fail" {
                                $peer crdt.zincrby zset9122 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9122 1 1000 1:6 3:1:a,1:6:2:2.0 
                                $master crdt.zincrby zset9122 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9122 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            }
                            
                        }
                        test "tad + ba" {
                            
                            test "tad + ba success" {
                                $peer crdt.zadd zset9130 1 1000 1:5 a 2:5.0
                                $peer crdt.zincrby zset9130 1 1000 1:4 a 2:2.0 
                                $master crdt.zincrby zset9130 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9130 1 1000 1:7 3:1:a,1:6:2:1.0 
                            
                            }
                            test "tad + ba fail" {
                                $peer crdt.zadd zset9131 1 1000 1:5 a 2:5.0
                                $peer crdt.zincrby zset9131 1 1000 1:4 a 2:2.0 
                                $master crdt.zincrby zset9131 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9131 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            }
                        }
                        test "tad + bad" {
                            test "tad + bad success" {
                                $master crdt.zincrby zset9140 1 1000 1:10 a 2:1.0 
                                $master crdt.zrem zset9140 1 1000 1:11 3:1:a,1:10:2:1.0

                                $peer crdt.zadd zset9140 1 1000 1:8 a 2:1.0
                                $peer crdt.zincrby zset9140 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9140 1 1000 1:6 3:1:a,1:6:2:2.0 
                                
                            }
                            test "tad + bad d success" {
                                $master crdt.zincrby zset9141 1 1000 1:3 a 2:1.0 
                                $master crdt.zrem zset9141 1 1000 1:4 3:1:a,1:3:2:1.0

                                $peer crdt.zadd zset9141 1 1000 1:8 a 2:1.0
                                $peer crdt.zincrby zset9141 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9141 1 1000 1:2 3:1:a,1:1:2:2.0 
                                
                            }
                            test "tad + bad fail" {
                                $master crdt.zincrby zset9142 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9142 1 1000 1:3 3:1:a,1:2:2:1.0

                                $peer crdt.zadd zset9142 1 1000 1:8 a 2:1.0
                                $peer crdt.zincrby zset9142 1 1000 1:7 a 2:5.0
                                $peer crdt.zrem zset9142 1 1000 1:6 3:1:a,1:6:2:2.0 
                            
                            }
                            
                        }
                    }
                    test "tbad" {
                        test "tbad + a" {
                            test "tbad + a success" {
                                $master crdt.zadd zset9200 1 1000 1:5 a 2:4.0
                                $master crdt.zincrby zset9200 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9200 1 1000 1:7 3:1:a,1:6:2:1.0 
                                $peer crdt.zincrby zset9200 1 1000 1:4 a 2:5.0 
                                
                            } 
                            test "tbad + a fail" {
                                $master crdt.zadd zset9201 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9201 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9201 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zincrby zset9201 1 1000 1:4 a 2:5.0 
                                
                            }
                        }
                        test "tbad + b" {
                            test "tbad + b success" {
                                $master crdt.zadd zset9210 1 1000 1:5 a 2:4.0
                                $master crdt.zincrby zset9210 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9210 1 1000 1:7 3:1:a,1:6:2:1.0 
                                $peer crdt.zadd zset9210 1 1000 1:4 a 2:5.0 
                                
                                
                            } 
                            test "tbad + b fail" {
                                $master crdt.zadd zset9211 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9211 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9211 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zadd zset9211 1 1000 1:4 a 2:5.0 
                                
                            }
                        }
                        test "tbad + ad" {
                            test "tbad + ad success" {
                                $master crdt.zadd zset9220 1 1000 1:5 a 2:4.0
                                $master crdt.zincrby zset9220 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9220 1 1000 1:7 3:1:a,1:6:2:1.0 
                                $peer crdt.zincrby zset9220 1 1000 1:4 a 2:5.0 
                                $peer crdt.zrem zset9220 1 1000 1:3 3:1:a,1:2:2:1.0 
                                
                            } 
                            test "tbad + ad d suceess" {
                                $master crdt.zadd zset9221 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9221 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9221 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zincrby zset9221 1 1000 1:4 a 2:5.0 
                                $peer crdt.zrem zset9221 1 1000 1:2 3:1:a,1:1:2:1.0 
                                
                            }
                            test "tbad + ad fail" {
                                $master crdt.zadd zset9222 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9222 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9222 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zincrby zset9222 1 1000 1:5 a 2:5.0 
                                $peer crdt.zrem zset9222 1 1000 1:4 3:1:a,1:3:2:2.0 
                                
                            }
                        }
                        test "tbad + ba" {
                            test "tbad + ba success" {
                                $master crdt.zadd zset9230 1 1000 1:5 a 2:4.0
                                $master crdt.zincrby zset9230 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9230 1 1000 1:7 3:1:a,1:6:2:1.0 
                                $peer crdt.zadd zset9230 1 1000 1:4 a 2:5.0 
                                $peer crdt.zincrby zset9230 1 1000 1:3 a 2:1.0
                                
                            } 
                            test "tbad + ba b suceess" {
                                $master crdt.zadd zset9231 1 1000 1:4 a 2:4.0
                                $master crdt.zincrby zset9231 1 1000 1:4 a 2:1.0 
                                $master crdt.zrem zset9231 1 1000 1:5 3:1:a,1:4:2:1.0 
                                $peer crdt.zadd zset9231 1 1000 1:3 a 2:5.0 
                                $peer crdt.zincrby zset9231 1 1000 1:7 a 2:3.0 
                                
                            }
                            test "tbad + ba a suceess" {
                                $master crdt.zadd zset9232 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9232 1 1000 1:7 a 2:2.0 
                                $master crdt.zrem zset9232 1 1000 1:8 3:1:a,1:7:2:2.0 
                                $peer crdt.zadd zset9232 1 1000 1:9 a 2:5.0 
                                $peer crdt.zincrby zset9232 1 1000 1:2 a 2:1.0
                                
                            }
                            test "tbad + ba fail" {
                                $master crdt.zadd zset9233 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9233 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9233 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zadd zset9233 1 1000 1:5 a 2:5.0 
                                $peer crdt.zincrby zset9233 1 1000 1:4 a 2:3.0
                                
                            }
                        }
                        test "tbad + bad" {
                            test "tbad + bad success" {
                                $master crdt.zadd zset9240 1 1000 1:5 a 2:4.0
                                $master crdt.zincrby zset9240 1 1000 1:6 a 2:1.0 
                                $master crdt.zrem zset9240 1 1000 1:7 3:1:a,1:6:2:1.0 
                                $peer crdt.zadd zset9240 1 1000 1:4 a 2:5.0 
                                $peer crdt.zincrby zset9240 1 1000 1:3 a 2:3.0
                                $peer crdt.zrem zset9240 1 1000 1:2 3:1:a,1:1:2:1.0 
                                
                            } 
                            test "tbad + bad b success" {
                                $master crdt.zadd zset9241 1 1000 1:2 a 2:4.0
                                $master crdt.zincrby zset9241 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9241 1 1000 1:7 3:1:a,1:2:2:1.0 
                                $peer crdt.zadd zset9241 1 1000 1:1 a 2:5.0 
                                $peer crdt.zincrby zset9241 1 1000 1:9 a 2:3.0 
                                $peer crdt.zrem zset9241 1 1000 1:8 3:1:a,1:7:2:2.0
                            }
                            test "tbad + bad ad success" {
                                $master crdt.zadd zset9242 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9242 1 1000 1:3 a 2:2.0 
                                $master crdt.zrem zset9242 1 1000 1:4 3:1:a,1:3:2:2.0 
                                $peer crdt.zadd zset9242 1 1000 1:5 a 2:5.0 
                                $peer crdt.zincrby zset9242 1 1000 1:1 a 2:1.0
                                $peer crdt.zrem zset9242 1 1000 1:2 3:1:a,1:1:2:1.0
                            }
                            test "tbad + bad  d success" {
                                $master crdt.zadd zset9243 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9243 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9243 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zadd zset9243 1 1000 1:5 a 2:5.0 
                                $peer crdt.zincrby zset9243 1 1000 1:4 a 2:3.0
                                $peer crdt.zrem zset9243 1 1000 1:1 3:1:a,1:1:2:1.0
                            }
                            test "tbad + bad  bd success" {
                                $master crdt.zadd zset9244 1 1000 1:4 a 2:4.0
                                $master crdt.zincrby zset9244 1 1000 1:5 a 2:1.0 
                                $master crdt.zrem zset9244 1 1000 1:6 3:1:a,1:5:2:1.0 
                                $peer crdt.zadd zset9244 1 1000 1:2 a 2:5.0 
                                $peer crdt.zincrby zset9244 1 1000 1:7 a 2:3.0
                                $peer crdt.zrem zset9244 1 1000 1:1 3:1:a,1:1:2:1.0
                                
                            }
                            test "tbad + bad  bad fail" {
                                $master crdt.zadd zset9245 1 1000 1:1 a 2:4.0
                                $master crdt.zincrby zset9245 1 1000 1:2 a 2:1.0 
                                $master crdt.zrem zset9245 1 1000 1:3 3:1:a,1:2:2:1.0 
                                $peer crdt.zadd zset9245 1 1000 1:6 a 2:5.0 
                                $peer crdt.zincrby zset9245 1 1000 1:7 a 2:3.0
                                $peer crdt.zrem zset9245 1 1000 1:5 3:1:a,1:5:2:1.0
                            }
                        }
                    }
                }
                
            }
            $peer peerof $master_gid $master_host $master_port
            # wait_for_peer_sync $peer
            after 5000
            # puts [print_log_file $peer_log]
            test "after" {
                test "value + tomstone" {
                    test "a" {
                        test "a + tb " {
                            $peer zscore zset8000 a
                        } {1}
                        test "a + tad " {
                            test "a + tad success" {
                                $peer zscore zset8010 a
                            } {4}
                            test "a + tad fail" {
                                $peer zscore zset8011 a
                            } {}
                            
                        }
                        test "a + tbad" {
                            test "a + tbad success" {
                                $peer zscore zset8020 a
                            } {4}
                            test "a + tbad fail" {
                                $peer zscore zset8021 a
                            } {}
                        }
                    }
                    test "b" {
                        test "b + tb " {
                            test "b + tb success" {
                                
                                $peer zscore zset8100 a
                                
                            } {5}
                            test "b + tb fail" {
                                
                                $peer zscore zset8101 a
                            } {}
                        }
                        test "b + tad" {
                            test "b + tad success" {
                                $peer zscore zset8110 a
                            } {5}
                        }
                        test "b + tbad" {
                            test "b + tbad success" {
                                # puts [$peer crdt.datainfo zset8120]
                                $peer zscore zset8120 a
                            } {7}
                            test "b + tbad fail" {
                                $peer zscore zset8121 a
                            } {}
                        }
                    }
                    test "ba" {
                        test "ba + tb " {
                            test "ba + tb success" {
                                $peer zscore zset8200 a
                            } {6}
                            test "ba + tb fail" {
                                
                                $peer zscore zset8201 a
                            } {1}
                        }
                        test "ba + tad" {
                            test "ba + tad success" {
                                
                                $peer zscore zset8210 a
                            } {6}
                            test "ba + tad fail" {
                                $peer zscore zset8211 a
                            } {7}
                        }
                        test "ba + bad" {
                            test "ba + tbad success" {
                                # 8
                                $peer zscore zset8220 a
                            } {8}
                            test "ba + tbad b fail" {
                                # 1
                                $peer zscore zset8221 a
                            } {1}
                            test "ba + tbad a fail" {
                                # 5
                                $peer zscore zset8222 a
                            } {5}
                            test "ba + tbad ba fail" {
                                #  {}
                                $peer zscore zset8223 a
                            } {}
                        }
                        
                    }
                    test "ad" {
                        test "ad + tb " {
                            test "ad + tb success" {

                                # 3

                                
                                $peer zscore zset8300 a
                            } {3}
                        }
                        test "ad + tad" {
                            test "ad + tad success" {
                                # 7
                                $peer zscore zset8310 a
                            } {3}
                            test "ad + tad ad fail" {
                                # {}
                                $peer zscore zset8311 a
                                
                            } {}
                            test "ad + tad a success" {
                                $peer zscore zset8312 a
                            } {4}
                        }
                        test "ad + tbad" {
                            test "ad + tbad success" {
                                # 6
                                $peer zscore zset8320 a
                                
                            } {3}
                            test "ad + tbad ad fail" {
                                #  {}
                                $peer zscore zset8321 a
                                
                            } {}
                            test "ad + tbad a success" {
                                #  {}
                                $peer zscore zset8322 a
                                
                            } {4}
                        }
                    }
                    test "bad" {
                        test "bad + tb" {
                            test "bad + tb success" {
                                # 4
                                $peer zscore zset8400 a
                            } {4}
                            test "bad + tb fail" {
                                $peer zscore zset8401 a
                            } {-1}
                        }
                        test "bad + tad" {
                            test "bad + tad success" {
                                
                                $peer zscore zset8410 a
                                
                            } {4}
                            test "bad + tad fail" {
                                # 3
                                $peer zscore zset8411 a
                            } {3}
                            test "bad + tad a success" {
                                # 3
                                $peer zscore zset8412 a
                            } {6}
                        }
                        test "bad + tbad" {
                            test "bad + tad success" {
                                # 4
                                $peer zscore zset8420 a      
                            } {4}
                            test "bad + tbad b fail" {
                                # 3
                                
                                $peer zscore zset8421 a
                                
                                
                                
                            } {3}
                            test "bad + tbad ad fail" {
                                # 3
                                $peer zscore zset8422 a
                            } {3}
                            test "bad + tbad bad fail" {
                                $peer zscore zset8423 a
                                
                                
                            } {}
                        }
                    }
                    
                }

                test "tombstone + value" {
                    test "b" {
                        test "tb + a" {
                            $peer zscore zset9000 a
                        } {1}
                        test "tb + b" {
                            test "tb + b success" {
                                $peer zscore zset9010 a
                            } {}
                            test "tb + b fail" {
                                $peer zscore zset9011 a   
                            } {5}
                        }
                        test "tb + ad" {
                            $peer zscore zset9020 a
                        } {3}
                        test "tb + ba" {
                            test "tb + ba success" {
                                # puts [$peer crdt.datainfo zset9030]
                                $peer zscore zset9030 a
                            } {1}
                            test "tb + ba fail" {
                                $peer zscore zset9031 a
                            } {6}
                        }
                        test "tb + bad" {
                            test "tb + bad success" {
                                $peer zscore zset9040 a
                            } {3}
                            test "tb + bad fail" {
                                $peer zscore zset9041 a
                            } {5}
                        }
                    }
                    test "ad" {
                        test "tad + a" {
                            test "tad + a success" {
                                $peer zscore zset9100 a
                            } {}
                            test "tad + a fail" {
                                $peer zscore zset9101 a
                            } {4}
                        }
                        test "tad + b" {
                            $peer zscore zset9110 a
                        } {}
                        test "tad + ad" {
                            test "tad + ad success" {
                                $peer zscore zset9120 a 
                            } {}
                            test "tad + ad  d success" {
                                $peer zscore zset9121 a 
                            } {4}
                            test "tad + ad  d fail" {
                                $peer zscore zset9122 a 
                            } {3}
                        } 
                        test "tad + ba" {
                            test "tad + ba success" {
                                $peer zscore zset9130 a
                            } {}
                            test "tad + ba fail" {
                                $peer zscore zset9131 a
                            } {6}
                            
                        }
                        test "tad + bad" {
                            test "tad + bad success" {
                                
                                $peer zscore zset9140 a
                            } {}
                            test "tad + bad d success" {
                                $peer zscore zset9141 a
                            } {5}
                            test "tad + bad fail" {
                                $peer zscore zset9142 a
                            } {4}
                        }
                    }
                    test "tbad" {
                        test "tbad + a" {
                            test "tbad + a success" {
                                $peer zscore zset9200 a
                            } {}
                            test "tbad + a fail" {
                                $peer zscore zset9201 a
                            } {4}
                        }
                        test "tbad + b" {
                            test "tbad + b success" {
                                $peer zscore zset9210 a
                            } {}
                            test "tbad + b fail" {
                                $peer zscore zset9211 a
                            } {5}
                        }
                        test "tbad + ad" {
                            test "tbad + ad success" {
                                $peer zscore zset9220 a
                            } {}
                            test "tbad + ad d suceess" {
                                $peer zscore zset9221 a
                            } {4}
                            test "tbad + ad fail" {
                                $peer zscore zset9222 a
                            } {3}
                        }
                        test "tbad + ba" {
                            test "tbad + ba success" {
                                $peer zscore zset9230 a
                            } {}
                            test "tbad + ba b suceess" {
                                $peer zscore zset9231 a
                            } {2}
                            test "tbad + ba a suceess" {
                                $peer zscore zset9232 a
                            } {5}
                            test "tbad + ba fail" {
                                $peer zscore zset9233 a
                            } {7}
                        }
                        test "tbad + bad" {
                            test "tbad + bad success" {
                                $peer zscore zset9240 a
                                
                            } {}
                            test "tbad + bad b suceess" {
                                $peer zscore zset9241 a
                                
                            } {1}
                            test "tbad + bad ad suceess" {
                                $peer zscore zset9242 a
                            } {5}
                            test "tbad + bad  d sucess" {
                                $peer zscore zset9243 a
                            }  {7}
                            test "tbad + bad  bd success" {
                                $peer zscore zset9244 a
                            } {2}
                            test "tbad + bad  bad fail" {
                                $peer zscore zset9245 a
                            } {7}
                        }
                    }
                }
            }

        }
    }
}
