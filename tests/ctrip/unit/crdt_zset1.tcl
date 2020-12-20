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
    $master crdt.debug_gc zset 0
    

        
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
                print_log_file $master_log
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
            $slave crdt.debug_gc zset 0 
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
                    puts [$master crdt.datainfo zset5300]
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
                        puts [$master crdt.datainfo zset5100]
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