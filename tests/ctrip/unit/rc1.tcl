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
    proc params_error {script} {
        catch {[uplevel 1 $script ]} result opts
        # puts $result
        assert_match "*ERR wrong number of arguments for '*' command*" $result
    }
    test "params" {
        params_error {
            $master get 
        }
        params_error {
            $master set 
        }
        params_error {
            $master incr
        }
        params_error {
            $master decr 
        }
        params_error {
            $master incrbyfloat 
        }
        params_error {
            $master incrby 
        }
        params_error {
            $master setex 
        }
        params_error {
            $master setnx 
        }
        params_error {
            $master expire 
        }
        params_error {
            $master PERSIST
        }
        params_error {
            $master pexpire
        }
    }
    proc type_error {script} {
        catch {[uplevel 1 $script ]} result opts
        assert_match "*WRONGTYPE Operation against a key holding the wrong kind of value*" $result
    }
    test "type_error" {
        $master hset k a b 
        type_error {
            $master get k 
        }
        type_error {
            $master set k v 
        }
        type_error {
            $master incr k 
        }
        type_error {
            $master decr k 
        }
        type_error {
            $master incrbyfloat k  1.0
        }
        type_error {
            $master incrby k 1
        }
        type_error {
            $master setex k 10 a 
        }
        assert_equal [$master hget k a ] b
    }
    test "setex" {
        assert_equal [$master ttl exkey] -2 
        $master setex exkey 100 v 
        assert {[$master ttl exkey] != -1} 
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
    $master crdt.debug_gc rc 0
    

        
        test {"crdt.rc + crdt.rc"} {
            test "step1  set crdt.rc" {
                $master crdt.rc rc1  1 1000 1:1 3:1:1 -1
                $master get rc1 
            } {1}
            test "step2 crdt.rc conflict by gid fail" {
                $master crdt.rc rc1 2 1000 2:1 3:1:2 -1
                $master get rc1 
            } {1}
            test "step3 crdt.rc conflict by time" {
                $master crdt.rc rc1  2 1001 2:2  3:1:2 -1
                $master get rc1 
            } {2}
            test "step3 crdt.rc conflict by time fail" {
                catch {$master crdt.rc rc1  1 1000 {1:2;2:1}  3:3:3.0 -1 } error 
                $master get rc1 
            } {2}
            test "step4 crdt.rc conflict by gid" {
                $master crdt.rc rc1  1 1001 {1:3;2:1}  3:1:3 -1
                $master get rc1 
            } {3}
            set old_info [$master crdt.datainfo rc1]
            test "step5 crdt.rc repeat fail" {
                $master crdt.rc rc1  1 1000 1:1  3:1:1 -1
                $master get rc1 
            } {3}
            assert_equal $old_info [$master crdt.datainfo rc1]
            test "step6 crdt.counter" {
                $master crdt.counter rc1 1 1000 1:1 4 4:1.12
                assert {abs([$master get rc1] - 4.12) < 0.001}
            } 
            test "step6 other gid crdt.counter" {
                $master crdt.counter rc1 2 1000 2:1 4 4:1.0 
                puts {abs([$master get rc1] - 5.12) < 0.001}
                assert {[expr abs([$master get rc1] - 5.12)] < 0.001} 
            } 
            test "step6 crdt.rc + del_counter" {
                $master crdt.rc rc1 1 1000 {1:3;2:1}  3:1:4,1:1:4:1.12 -1
                $master get rc1 
            } {4}
            
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2( set,  set + del)" {
            test "null" {
                test "null +  set" {
                    $master crdt.rc rc1000 1 1000 1:1  3:1:1 -1
                    $master get rc1000 
                } {1}
            }
            test "value" {
                test "succeed" {
                    test "a +  set" {
                        test "a +  set" {
                            $master crdt.counter rc1100 1 1000 1:1 4 4:1.0 
                            $master crdt.rc rc1100 1 1000 1:2  2:2.0 -1
                            $master get rc1100 
                        } {3}
                        test "a +  set + del" {
                            $master crdt.counter rc1110 1 1000 1:1 4 4:1.0 
                            $master crdt.rc rc1110 1 1000 1:2  {2:2.0,1:1:2:1.0} -1
                            $master get rc1110 
                        } {2}
                    } 
                    test "b +  set" {
                        $master crdt.rc rc1200 1 1000 1:1  3:1:1 -1
                        $master crdt.rc rc1200 1 1000 1:2  3:1:2 -1
                        $master get rc1200 
                    } {2}
                    test "ba +  set" {
                        test "ba +  set" {
                            $master crdt.rc rc1300 1 1000 1:1 2:2.0 -1
                            $master crdt.counter rc1300 1 1000 1:2 4 4:1.0 
                            $master crdt.rc rc1300 1 1000 1:3 2:3.0 -1
                            $master get rc1300 
                        } {4}
                        test "ba +  set + del" {
                            $master crdt.rc rc1310 1 1000 1:1 3:1:1  -1
                            $master crdt.counter rc1310 1 1000 1:2 4 4:1 
                            $master crdt.rc rc1310 1 1000 1:3 {3:1:3,1:2:4:1} -1
                            $master get rc1310 
                        } {3}
                    }
                    test "ad +  set" {
                        test "ad +  set" {
                            $master crdt.counter rc1400 1 1000 1:1 4 4:1.0 
                            $master crdt.del_rc rc1400 1 1000 1:2 {1:1:4:1.0}  
                            $master crdt.rc rc1400 1 1000 1:3 3:1:3 -1
                            $master get rc1400 
                        } {3}
                        test "ad +  set + del" {
                            $master crdt.counter rc1410 1 1000 1:2 4 4:3.0 
                            $master crdt.del_rc rc1410 1 1000 1:1 {1:1:2:2.0} 
                            $master crdt.rc rc1410 1 1000 1:3 {2:3.0,1:1:4:4.0} -1
                            $master get rc1410 
                        } {4}
                    }
                    test "bad +  set" {
                        test "bad +  set" {
                            $master crdt.rc rc1500 1 1000 1:1 3:3:2.0 -1
                            $master crdt.counter rc1500 1 1000 1:2 4 4:1.0 
                            $master crdt.del_rc rc1500 1 1000 1:3 {1:1:4:1.0}  
                            $master crdt.rc rc1500 1 1000 1:4 3:3:3.0 -1
                            $master get rc1500 
                        } {3}
                        test "bad +  set + del" {
                            $master crdt.rc rc1510 1 1000 1:1 3:3:2.0 -1
                            $master crdt.counter rc1510 1 1000 1:2 4 4:3.0 
                            $master crdt.del_rc rc1510 1 1000 1:1 {1:1:2:2.0} 
                            $master crdt.rc rc1510 1 1000 1:3 {2:3.0,1:1:3:3:4.0} -1
                            $master get rc1510 
                        } {4}
                    }
                }
                test "fail" {
                    test "a +  set" {
                        
                    }
                    test "b +  set" {
                        $master crdt.rc rc1201 1 1000 1:2 3:1:2 -1
                        $master crdt.rc rc1201 1 1000 1:1 3:3:1.0 -1
                        $master get rc1200 
                    } {2}
                    test "ba +  set" {
                        test "ba +  set + del only del" {
                            $master crdt.counter rc1311 1 1000 1:2 4 4:1.0 
                            $master crdt.rc rc1311 1 1000 1:4 3:1:2 -1
                            $master crdt.rc rc1311 1 1000 1:3 {3:3:3.0,1:2:4:1.0} -1
                            $master get rc1311 
                        } {2}
                    }
                    test "ad +  set" {
                        test "ad +  set" {
                            $master crdt.counter rc1401 1 1000 1:2 4 4:1.0 
                            $master crdt.del_rc rc1401 1 1000 1:3 {1:2:4:1.0}  
                            $master crdt.rc rc1401 1 1000 1:1 3:3:3.0 -1
                            $master crdt.rc rc1401 1 1000 1:1 3:3:3.0 -1
                            $master get rc1401 
                        } {}
                    }
                    test "bad +  set" {
                        test "bad +  set" {
                            $master crdt.rc rc1501 1 1000 1:2 3:3:2.0 -1
                            $master crdt.counter rc1501 1 1000 1:3 4 4:1.0 
                            $master crdt.del_rc rc1501 1 1000 1:4 {1:2:4:1.0}  
                            $master crdt.rc rc1501 1 1000 1:1 3:3:3.0 -1
                            $master get rc1501 
                        } {0}
                        test "bad +  set + del" {
                            $master crdt.counter rc1511 1 1000 1:2 4 4:3.0 
                            $master crdt.del_rc rc1511 1 1000 1:1 {1:2:2:2.0} 
                            $master crdt.rc rc1511 1 1000 1:5 3:1:2 -1
                            $master crdt.rc rc1511 1 1000 1:4 {3:3:3.0,1:3:2:4.0} -1
                            $master get rc1511 
                        } {2}
                        test "bad +  set + del" {
                            $master crdt.counter rc1512 1 1000 1:2 4 4:3.0 
                            $master crdt.del_rc rc1512 1 1000 1:1 {1:2:4:2.0} 
                            $master crdt.rc rc1512 1 1000 1:5 3:1:2 -1
                            $master crdt.rc rc1512 1 1000 1:4 {3:3:3.0,1:3:4:4.0} -1
                            $master crdt.counter rc1512 1 1000 1:3 4 4:4.0
                            $master get rc1512 
                        } {2}
                    }
                }
                
            }
            test "tombstone" {
                test "succeed" {
                    test "succeed tombstone ad + counter" {
                        test "succeed ad + counter" {
                            $master crdt.counter rc2410 2 1000 2:1 4 4:2.0
                            $master crdt.del_rc rc2410 2 1000 2:2 {2:1:4:2.0}
                            $master crdt.counter rc2410 2 1000 2:3 4 4:1.0
                            $master get rc2410 
                        } {-1}
                    } 
                    test "succeed tombstone bad + counter1" {
                        test "succeed tombstone bad + counter1" {
                            $master crdt.rc rc2510 2 1000 2:1 3:3:1.0 -1
                            $master crdt.counter rc2510 2 1000 2:2 4 4:2.0
                            $master crdt.del_rc rc2510 2 1000 2:3 {2:1:2:2.0}
                            $master crdt.counter rc2510 2 1000 2:4 4 4:1.0
                            $master get rc2510 
                        } {-1}
                    } 
                }

                test "fail" {
                    test "fail tombstone ad + counter" {
                        test "fail tombstone ad + counter" {
                            $master crdt.counter rc2610 2 1000 2:1 4 4:1.0
                            $master crdt.del_rc rc2610 2 1000 2:2 {2:1:4:1.0}
                            $master crdt.counter rc2610 2 1000 2:1 4 4:1.0
                            $master get rc2610 
                        } {}
                    } 
                    test "fail tombstone bad  + counter" {
                        test "fail tombstone bad + counter" {
                            $master crdt.rc rc2710 2 1000 2:1 3:3:1.0 -1
                            $master crdt.counter rc2710 2 1000 2:2 4 4:1.0
                            $master crdt.del_rc rc2710 2 1000 2:3 {2:2:4:1.0}
                            $master crdt.counter rc2710 2 1000 2:2 4 4:1.0
                            $master get rc2710 
                        } {}
                    } 
                }
                
            }
            
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2(counter, counter + del)" {
            test "null" {
                test "null + counter" {
                    $master crdt.counter rc2000 1 1000 1:1 4 4:1.0 
                    $master get rc1000 
                } {1}
            }
            test "value" {
                test "succeed" {
                    test "a + counter" {
                        test "a + counter" {
                            $master crdt.counter rc2100 1 1000 1:1 4 4:1.0
                            $master crdt.counter rc2100 1 1000 1:2 4 4:1.0
                            $master get rc2100 
                        } {1}

                    } 
                    test "b + counter" {
                        test "b + counter" {
                            $master crdt.rc rc2200 1 1000 1:1 3:3:1.0 -1
                            $master crdt.rc rc2200 1 1000 1:2 3:1:2 -1
                            $master get rc2200 
                        } {2}
                    }
                    test "ad + counter" {
                        test "ad + counter" {
                            $master crdt.counter rc2300 1 1000 1:1 4 4:1.0
                            $master crdt.del_rc rc2300 1 1000 1:2 1:1:4:1.0
                            $master crdt.counter rc2300 1 1000 1:3 4 4:2.0
                            $master get rc2300 
                        } {1}
                    }
                    test "ba + counter" {
                        test "ba + counter" {
                            $master crdt.rc rc2400 1 1000 1:1  3:3:1.0 -1
                            $master crdt.counter rc2400 1 1000 1:2 4 4:1.0
                            $master crdt.counter rc2400 1 1000 1:3 4 4:2.0
                            $master get rc2400 
                        } {3}
                    }
                    test "bad + counter" {
                        test "bad + counter" {
                            $master crdt.rc rc2500 1 1000 1:1 3:3:1.0 -1
                            $master crdt.counter rc2500 1 1000 1:2 4 4:2.0
                            $master crdt.counter rc2500 1 1000 1:3 4 4:3.0
                            $master crdt.del_rc rc2500 1 1000 1:4 1:2:4:2.0 
                            $master crdt.counter rc2500 1 1000 1:3 4 4:4.0
                            $master get rc2500 
                        } {1}   
                    }

                }

                test "fail" {
                    test "fail + counter" {
                        test "a + counter" {
                            $master crdt.counter rc2600 1 1000 1:1 4 4:1.0
                            $master crdt.counter rc2600 1 1000 1:1 4 4:1.0
                            $master get rc2600 
                        } {1}
                    } 
                    test "fail b + counter" {
                    }
                    test "fail ad + counter" {
                        test "fail ad + counter" {
                            $master crdt.counter rc2110 1 1000 1:1 4 4:1.0
                            $master crdt.del_rc rc2110 1 1000 1:2 1:1:4:1.0
                            $master crdt.counter rc2110 1 1000 1:3 4 4:1.0
                            $master get rc2110 
                        } {0}
                    }
                    test "fail ba + counter1" {
                        test "fail ba + counter1" {
                            $master crdt.rc rc2210 1 1000 1:1  3:3:1.0 -1
                            $master crdt.counter rc2210 1 1000 1:2 4 4:1.0
                            $master crdt.counter rc2210 1 1000 1:1 4 4:2.0
                            $master get rc2210 
                        } {2}
                    }
                    test "fail bad + counter2" {
                        test "fail bad + counter2" {
                            $master crdt.rc rc2310 1 1000 1:1 3:3:1.0 -1
                            $master crdt.counter rc2310 1 1000 1:2 4 4:2.0
                            $master crdt.counter rc2310 1 1000 1:3 4 4:3.0
                            $master crdt.del_rc rc2310 1 1000 1:4 1:2:2:2.0 
                            $master crdt.counter rc2310 1 1000 1:3 4 4:3.0
                            $master get rc2310 
                        } {1}   
                    }

                }
            }
            test "tombstone" {
                test "succeed" {
                    test "succeed tombstone ad + counter" {
                        test "succeed ad + counter" {
                            $master crdt.counter rc2410 2 1000 2:1 4 4:2.0
                            $master crdt.del_rc rc2410 2 1000 2:2 2:1:4:2.0
                            $master crdt.counter rc2410 2 1000 2:3 4 4:1.0
                            $master get rc2410 
                        } {-1}
                    } 
                    test "succeed tombstone bad + counter1" {
                        test "succeed tombstone bad + counter1" {
                            $master crdt.rc rc2510 2 1000 2:1 3:3:1.0 -1
                            $master crdt.counter rc2510 2 1000 2:2 4 4:2.0
                            $master crdt.del_rc rc2510 2 1000 2:3 2:1:4:2.0
                            $master crdt.counter rc2510 2 1000 2:4 4 4:1.0
                            $master get rc2510 
                        } {-1}
                    } 
                }

                test "fail" {
                    test "fail tombstone ad + counter" {
                        test "fail tombstone ad + counter" {
                            $master crdt.counter rc2610 2 1000 2:1 4 4:1.0
                            $master crdt.del_rc rc2610 2 1000 2:2 2:1:2:1.0
                            $master crdt.counter rc2610 2 1000 2:1 4 4:1.0
                            $master get rc2610 
                        } {}
                    } 
                    test "fail tombstone bad  + counter" {
                        test "fail tombstone bad + counter" {
                            $master crdt.rc rc2710 2 1000 2:1 3:3:1.0 -1
                            $master crdt.counter rc2710 2 1000 2:2 4 4:1.0
                            $master crdt.del_rc rc2710 2 1000 2:3 2:2:4:1.0
                            $master crdt.counter rc2710 2 1000 2:2 4 4:1.0
                            $master get rc2710 
                        } {}
                    } 
                }
                
            }
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2( del_rc,  del_rc + del)" {
            test "null" {
                test "null +  del_rc" {
                    $master crdt.del_rc rc3000 1 1000 1:2 
                    $master get rc3000 
                } {}
            }
            test "value" {
                test "succeed" {
                    test "a +  del_rc" {
                        $master crdt.counter rc3100 1 1000 1:1 4 4:1.0
                        $master crdt.del_rc rc3100 1 1000 1:2 1:1:4:1.0
                        $master get rc3100 
                    } {}
                    test "b +  del_rc" {
                        $master crdt.rc rc3200 1 1000 1:1  3:3:1.0 -1
                        $master crdt.del_rc rc3200 1 1000 1:2 
                        $master get rc3200 
                    } {}
                    test "ba +  del_rc" {
                        $master crdt.rc rc3300 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc3300 1 1000 1:2  4 4:1.0
                        $master crdt.del_rc rc3300 1 1000 1:3 1:2:4:1.0
                        $master get rc3300 
                    } {}
                    test "ad +  del_rc" {
                        $master crdt.counter rc3400 1 1000 1:3  4 4:3.0 
                        $master crdt.del_rc rc3400 1 1000 1:2 1:1:4:1.0
                        $master crdt.del_rc rc3400 1 1000 1:4 1:3:4:3.0
                        $master get rc3400 
                    } {}
                    test "bad +  del_rc" {
                        $master crdt.rc rc3500 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc3500 1 1000 1:3  4 4:2.0
                        $master crdt.del_rc rc3500 1 1000 1:2 1:2:4:1.0
                        $master crdt.del_rc rc3500 1 1000 1:3 1:3:4:2.0
                        $master get rc3500 
                    } {}
                }
                test "fail" {
                    test "fail +  del_rc" {
                        $master crdt.counter rc3110 1 1000 1:1 4 4:1.0
                        $master crdt.del_rc rc3110 1 1000 1:2 
                        $master get rc3110 
                    } {1}
                    test "fail b +  del_rc" {
                        $master crdt.rc rc3210 1 1000 1:3  3:1:1 -1
                        $master crdt.del_rc rc3210 1 1000 1:2 
                        $master get rc3210 
                    } {1}
                    test "fail ba +  del_rc" {
                        $master crdt.rc rc3310 1 1000 1:2  3:3:1.0 -1
                        $master crdt.counter rc3310 1 1000 1:3 4 4:1.0
                        $master crdt.del_rc rc3310 1 1000 1:1  
                        $master get rc3310 
                    } {2}
                    test "fail ad +  del_rc" {
                        $master crdt.counter rc3410 1 1000 1:4  4 4:3.0
                        $master crdt.del_rc rc3410 1 1000 1:3 1:1:4:1.0
                        $master crdt.del_rc rc3410 1 1000 1:1 1:1:4:1.0 
                        $master get rc3410 
                    } {2}
                    test "fail bad +  del_rc" {
                        $master crdt.rc rc3510 1 1000 1:4  2:1.0 -1
                        $master crdt.counter rc3510 1 1000 1:5  4 4:2.0
                        $master crdt.del_rc rc3510 1 1000 1:3 {1:2:4:1.0}
                        $master crdt.del_rc rc3510 1 1000 1:2 {1:1:4:2.0}
                        $master get rc3510 
                    } {2}
                }
            }
            test "tombstone" {
                test "succeed" {
                    test "tombstone ad +  del_rc" {
                        $master crdt.counter rc3101 1 1000 1:1 4  4:1.0
                        $master crdt.del_rc rc3101 1 1000 1:2 1:1:4:1.0
                        $master crdt.del_rc rc3101 1 1000 1:3 1:1:4:2.0
                        $master get rc3101 
                    } {}
                    test "tombstone bad +  del_rc" {
                        $master crdt.rc rc3102 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc3202 1 1000 1:2  4 4:1.0
                        $master crdt.del_rc rc3102 1 1000 1:3 1:2:4:1.0
                        $master crdt.del_rc rc3102 1 1000 1:5 1:3:4:2.0
                        $master get rc3102 
                    } {}
                }
                test "fail" {
                    test "tombstone fail ba +  del_rc" {
                        $master crdt.counter rc3103 1 1000 1:1  4 4:1.0
                        $master crdt.del_rc rc3103 1 1000 1:2 1:1:4:1.0
                        $master crdt.del_rc rc3103 1 1000 1:1 
                        $master get rc3103 
                    } {}
                    test "tombstone fail bad +  del_rc" {
                        $master crdt.rc rc3104 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc3104 1 1000 1:2  4 4:1.0
                        $master crdt.del_rc rc3104 1 1000 1:3 1:2:4:1.0
                        $master crdt.del_rc rc3104 1 1000 1:1 1:1:4:1.0
                        $master get rc3104 
                    } {}
                }
            }
        }
        test "5(stats) * 2(value,tombstone) * 2(fail, succeed) * 2(del, del + del)" {
            test "null" {
                test "null + del" {
                    $master crdt.del_rc rc4000 1 1000 1:2 
                    $master get rc4000 
                } {}
            }
            test "value" {
                test "succeed" {
                    test "a + del" {
                        $master crdt.counter rc4100 1 1000 1:1  4 4:1.0
                        $master crdt.del_rc rc4100 1 1000 1:2 1:1:2:1.0
                        $master get rc4100 
                    } {}
                    test "b + del" {
                        test "b + del1" {
                            $master crdt.rc rc4200 1 1000 1:1  3:3:1.0 -1
                            $master crdt.del_rc rc4200 1 1000 1:2 1:1:4:1.0
                            $master get rc4200 
                        } {}
                        test "b + del2" {
                            $master crdt.rc rc4210 1 1000 1:1  3:3:1.0 -1
                            $master crdt.del_rc rc4210 1 1000 1:2 
                            $master get rc4210 
                        } {}
                        
                    }
                    test "ba + del" {
                        $master crdt.rc rc4300 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc4300 1 1000 1:2  4 4:1.0
                        $master crdt.del_rc rc4300 1 1000 1:3 1:2:2:1.0
                        $master get rc4300 
                    } {}
                    test "ad + del" {
                        $master crdt.counter rc4400 1 1000 1:3  4 4:3.0
                        $master crdt.del_rc rc4400 1 1000 1:2 1:1:4:1.0
                        $master crdt.del_rc rc4400 1 1000 1:4 1:3:4:3.0
                        $master get rc4400 
                    } {}
                    test "bad + del" {
                        $master crdt.rc rc4500 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc4500 1 1000 1:3  4 4:2.0 
                        $master crdt.del_rc rc4500 1 1000 1:2 1:2:4:1.0
                        $master crdt.del_rc rc4500 1 1000 1:3 1:3:4:2.0
                        $master get rc4500 
                    } {}
                }

                test "fail" {
                    test "a + del" {
                        $master crdt.counter rc4110 1 1000 1:3  4 4:1.0
                        $master crdt.del_rc rc4110 1 1000 1:2 
                        $master get rc4110 
                    } {1}
                    test "b + del" {
                        $master crdt.rc rc4210 1 1000 1:3  3:3:1.0 -1
                        $master crdt.del_rc rc4210 1 1000 1:2 
                        $master get rc4210 
                    }
                    test "ba + del" {
                        $master crdt.rc rc4310 1 1000 1:2  3:3:1.0 -1
                        $master crdt.counter rc4310 1 1000 1:3  4 4:1.0
                        $master crdt.del_rc rc4310 1 1000 1:1
                        $master get rc4310 
                    } {2}
                    test "ad + del" {
                        $master crdt.counter rc4410 1 1000 1:3  4 4:3.0
                        $master crdt.del_rc rc4410 1 1000 1:2 1:1:4:1.0
                        $master crdt.del_rc rc4410 1 1000 1:1 1:1:4:1.0
                        $master get rc4410 
                    } {2}
                    test "bad + del" {
                        $master crdt.rc rc4510 1 1000 1:2  3:3:1.0 -1
                        $master crdt.counter rc4510 1 1000 1:4 4 4:2.0
                        $master crdt.del_rc rc4510 1 1000 1:3 1:2:4:1.0
                        $master crdt.del_rc rc4510 1 1000 1:1 1:1:4:2.0
                        $master get rc4510 
                    } {1}
                }
            }
            test "tombstone" {
                test "succeed" {
                    test "tombstone ad + del" {
                        $master crdt.counter rc4101 1 1000 1:1  4 4:1.0
                        $master crdt.del_rc rc4101 1 1000 1:2 1:1:2:1.0
                        $master crdt.del_rc rc4101 1 1000 1:3 1:1:2:2.0
                        $master get rc4101 
                    } {}
                    test "tombstone bad + del" {
                        $master crdt.rc rc4102 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc4102 1 1000 1:2  4 4:1.0
                        $master crdt.del_rc rc4102 1 1000 1:3 1:2:4:1.0
                        $master crdt.del_rc rc4102 1 1000 1:5 1:3:4:2.0
                        $master get rc4102 
                    } {}
                }
                test "fail" {
                    test "tombstone fail ba + del" {
                        $master crdt.counter rc4103 1 1000 1:1  4 4:1.0
                        $master crdt.del_rc rc4103 1 1000 1:2 1:1:4:1.0
                        $master crdt.del_rc rc4103 1 1000 1:1 
                        $master get rc4103 
                    } {}
                    test "tombstone fail bad + del" {
                        $master crdt.rc rc4104 1 1000 1:1  3:3:1.0 -1
                        $master crdt.counter rc4104 1 1000 1:2  4 4:1.0
                        $master crdt.del_rc rc4104 1 1000 1:3 1:2:2:1.0
                        $master crdt.del_rc rc4104 1 1000 1:1 1:1:2:1.0
                        $master get rc4104 
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
            $slave crdt.debug_gc rc 0 
            test "before  master-slave sync" {
            test "value" {
                test "a" {
                    $master  crdt.counter rc5100 1 1000 1:1 4 4:1.1  
                }
                test "b" {
                    $master  crdt.rc rc5200 1 1000 1:1 3:3:1.2 -1 
                }
                test "ad" {
                    $master  crdt.counter rc5300 1 1000 1:2 4 4:2.0 
                    $master  crdt.del_rc rc5300 1 1000 1:1 1:1:2:1.0 
                    puts [$master crdt.datainfo rc5300]
                }
                test "ba" {
                    $master  crdt.rc rc5400 1 1000 1:1 3:3:1.1 -1 
                    $master  crdt.counter rc5400 1 1000 1:1 4 4:1.0 
                }
                test "bad" {
                    $master  crdt.rc rc5500 1 1000 1:1 3:3:1.0 -1 
                    $master  crdt.counter rc5500 1 1000 1:3 4 4:2.0 
                    $master  crdt.del_rc rc5500 1 1000 1:4 1:2:4:1.0 
                }
            }
            test "tombstone" {
                test "ad" {
                    $master  crdt.counter rc5600 1 1000 1:1 4 4:2.0 
                    $master  crdt.del_rc rc5600 1 1000 1:2 1:1:2:2.0 
                }
                test "bad" {
                    $master  crdt.rc rc5700 1 1000 1:1 3:3:2.0 -1
                    $master  crdt.counter rc5700 1 1000 1:2 4 4:2.0 
                    $master  crdt.del_rc rc5700 1 1000 1:3 1:2:4:2.0 
                }    
            }
                
            }
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_log
            test "after  master-slave sync" {
                test "value" {
                    test "a" {
                        assert_equal [$master crdt.datainfo rc5100] [$slave crdt.datainfo rc5100]
                        puts [$master crdt.datainfo rc5100]
                    }
                    test "b" {
                        assert_equal [$master crdt.datainfo rc5200] [$slave crdt.datainfo rc5200]
                    }
                    test "ad" {
                        assert_equal [$master crdt.datainfo rc5300] [$slave crdt.datainfo rc5300]
                        
                    }
                    test "ba" {
                        assert_equal [$master crdt.datainfo rc5400] [$slave crdt.datainfo rc5400]
                        
                    }
                    test "bad" {
                        assert_equal [$master crdt.datainfo rc5500] [$slave crdt.datainfo rc5500]
                    }
                }
                test "tombstone" {
                    test "ad" {
                    
                        assert_equal [$master crdt.datainfo rc5600] [$slave crdt.datainfo rc5600]
                    }
                    test "bad" {
                        assert_equal [$master crdt.datainfo rc5700] [$slave crdt.datainfo rc5700]
                    }
                }
                
            }
        }
    
}