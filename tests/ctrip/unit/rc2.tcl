start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    $master crdt.debug_gc rc 0
    # set master [redis "127.0.0.1" 6379]
    # $master select 9
    # set master_gid 1
    # set master_host "127.0.0.1"
    # set master_port 6379
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        # set peer [redis "127.0.0.1" 6379]
        # $master select 9
        # set peer_gid 2
        # set peer_host "127.0.0.1"
        # set peer_port 6379
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer crdt.debug_gc rc 0
        test "before" {
            test "a" {
                test "a + null" {
                    $master crdt.counter rc6100 1 1000 1:10 4 4:1.0 
                }
                test "a + a" {
                    test "before a + a success" {
                        $master crdt.counter rc6101 1 1000 1:20 4 4:1.0 
                        $peer crdt.counter rc6101 1 1000 1:1 4 4:2.0 
                    }
                    # test "before + fail" {
                    #     $master crdt.counter rc6102 1 1000 1:1 4 4:1.0 
                    #     $peer crdt.counter rc6102 1 1000 1:2 4 4:2.0 
                    # }
                }
                test "a + b" {
                    $master crdt.counter rc6120 1 1000 1:11 4 4:1.0 
                    $peer crdt.rc rc6120 1 1000 1:3 3:3:2.0  -1
                }
                test "a + ba" {
                    test "before + ba success" {
                        $master crdt.counter rc6130 1 1000 1:11 4 4:1.0 
                        $peer crdt.rc rc6130 1 1000 1:1 3:3:2.0 -1  
                        $peer crdt.counter rc6130 1 1000 1:2 4 4:2.0 
                    }
                    # test "before + ba fail" {
                    #     $master crdt.counter rc6131 1 1000 1:2 4 4:1.0 
                    #     $peer crdt.rc rc6131 1 1000 1:1 3:3:2.0 -1
                    #     $peer crdt.counter rc6131 1 1000 1:3 4 4:2.0
                    # }
                }
                test "a + ad" {
                    test "before + ad success" {
                        $master crdt.counter rc6140 1 1000 1:50 4 4:3.0 
                        $peer crdt.counter rc6140 1 1000 1:2 4 4:2.0 
                        $peer crdt.del_rc rc6140 1 1000 1:3  1:1:2:1.0
                    }
                    # test "before + ad fail" {
                    #     $master crdt.counter rc6141 1 1000 1:1 4 4:1.0 
                    #     $peer crdt.counter rc6141 1 1000 1:4 4 4:3.0 
                    #     $peer crdt.del_rc rc6141 1 1000 1:3  1:2:2:2.0
                    # }
                }
                test "a + bad" {
                    test "before + bad success" {
                        $master crdt.counter rc6150 1 1000 1:6 4 4:3.0 
                        $peer crdt.rc rc6150 1 1000 1:7 3:3:2.0 -1
                        $peer crdt.counter rc6150 1 1000 1:3 4 4:2.0 
                        $peer crdt.del_rc rc6150 1 1000 1:4  1:1:2:1.0
                    }
                    # test "before + ba fail" {
                    #     $master crdt.counter rc6151 1 1000 1:1 4 4:1.0 
                    #     $peer crdt.rc rc6151 1 1000 1:5 4 4:2.0 -1
                    #     $peer crdt.counter rc6151 1 1000 1:3 4 4:2.0 
                    #     $peer crdt.del_rc rc6151 1 1000 1:4  1:1:2:1.0
                    # }
                }
            }
        }
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "a" {
                test "a + null" {
                    assert_equal [$master crdt.datainfo rc6100] [$peer crdt.datainfo rc6100]
                }
                test "a + a" {
                    test "a + success" {
                        $peer get  rc6101 
                    } {1}
                    # test "a + fail" {
                    #     $peer get  rc6102 
                    # } {2}
                }
                test "a + b" {
                    $peer get  rc6120 
                } {3}
                test "a + ba" {
                    test "before + ba success" {
                        $peer get  rc6130 
                    } {3}
                    # test "before + ba fail" {
                    #     $peer get  rc6131 a
                    # } {4}
                } 
                test "a + ad" {
                    test "before + ad success" {
                        $peer get  rc6140 
                    } {2}
                    # test "before + ad fail" {
                    #     $peer get  rc6141 a
                    # } {1}
                } 
                test "a + bad" {
                    test "before + bad success" {
                        $peer get  rc6150 
                    } {4}
                    # test "before + bad fail" {
                    #     $peer get  rc6151 a
                    # } {3}
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
    $master crdt.debug_gc rc 0
    # set master [redis "127.0.0.1" 6379]
    # $master select 9
    # set master_gid 1
    # set master_host "127.0.0.1"
    # set master_port 6379
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        # set peer [redis "127.0.0.1" 6379]
        # $master select 9
        # set peer_gid 2
        # set peer_host "127.0.0.1"
        # set peer_port 6379
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer crdt.debug_gc rc 0
        test "before" {
            test "b" {
                test "b + null" {
                    $master crdt.rc rc6200 1 1000 1:10 3:3:1.0 -1
                }
                test "b + a" {
                    $master crdt.rc rc6210 1 1000 1:10 3:3:1.0 -1
                    $peer crdt.counter rc6210 1 1000 1:2 4 4:1.0
                }
                test "b + b" {
                    test " b + b success" {
                        $master crdt.rc rc6220 1 1000 1:10 3:1:1 -1
                        $peer crdt.rc rc6220 1 1000 1:1 3:3:2.0 -1
                    }
                    # test "b + b fail" {
                    #     $master crdt.rc rc6221 1 1000 1:1 4 4:1.0 -1
                    #     $peer crdt.rc rc6221 1 1000 1:2 4 4:2.0 -1
                    # }
                }
                test "b + ad" {
                    $master crdt.rc rc6230 1 1000 1:11 3:3:1.0 -1
                    $peer crdt.counter rc6230 1 1000 1:1 4 4:2.0
                    $peer crdt.del_rc rc6230 1 1000 1:2  1:1:2:1.0
                }
                test "b + ba" {
                    test "b + ba success" {
                        $master crdt.rc rc6240 1 1000 1:14 3:3:1.0 -1
                        $peer crdt.rc rc6240 1 1000 1:2 3:3:2.0 -1
                        $peer crdt.counter rc6240 1 1000 1:3 4 4:2.0
                    }
                    # test "b + ba fail" {
                    #     $master crdt.rc rc6241 1 1000 1:1 4 4:1.0 -1
                    #     $peer crdt.rc rc6241 1 1000 1:2 4 4:2.0 -1
                    #     $peer crdt.counter rc6241 1 1000 1:3 4 4:2.0
                    # }
                    
                }
                test "b + bad" {
                    test "b + bad success" {
                        $master crdt.rc rc6250 1 1000 1:6 3:3:1.0 -1
                        $peer crdt.rc rc6250 1 1000 1:5 3:3:2.0 -1
                        $peer crdt.counter rc6250 1 1000 1:3 4 4:2.0 
                        $peer crdt.del_rc rc6250 1 1000 1:4  1:1:2:1.0
                    }
                    # test "b + ba fail" {
                    #     $master crdt.rc rc6251 1 1000 1:2 4 4:1.0 -1
                    #     $peer crdt.rc rc6251 1 1000 1:5 4 4:2.0 -1
                    #     $peer crdt.counter rc6251 1 1000 1:3 4 4:2.0 
                    #     $peer crdt.del_rc rc6251 1 1000 1:4  1:1:2:1.0
                    # }
                }
            }
        }
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "b" {
                test "b + null" {
                    assert_equal [$master crdt.datainfo rc6200] [$peer crdt.datainfo rc6200]
                }
                test "b + a" {
                    $peer get  rc6210 
                } {2}
                test "b + b" {
                    test "b + b success" {
                        $peer get  rc6220 
                    } {1}
                    # test "b + b fail" {
                    #     $peer get  rc6221 a
                    # } {2}
                }
                test "b + ad" {
                    $peer get  rc6230 
                } {1}
                test "b + ba" {
                    test "b + ba success" {
                        $peer get  rc6240 
                    } {3}
                    # test "b + ba fail" {
                    #     $peer get  rc6241 a
                    # } {4}
                } 
                test "b + bad" {
                    test "b + bad success" {
                        $peer get  rc6250 
                    } {2}
                    # test "b + bad fail" {
                    #     $peer get  rc6251 a
                    # } {3}
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
    $master crdt.debug_gc rc 0
    # set master [redis "127.0.0.1" 6379]
    # $master select 9
    # set master_gid 1
    # set master_host "127.0.0.1"
    # set master_port 6379
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        # set peer [redis "127.0.0.1" 6379]
        # $master select 9
        # set peer_gid 2
        # set peer_host "127.0.0.1"
        # set peer_port 6379
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer crdt.debug_gc rc 0
        test "before" {
            test "ad" {
                test "ad + null" {
                    $master crdt.counter rc6300 1 1000 1:31 4 4:2.0
                    $master crdt.del_rc rc6300 1 1000 1:21  1:1:2:1.0
                }
                test "ad + a" {
                    test "ad + success" {
                        $master crdt.counter rc6310 1 1000 1:31 4 4:2.0
                        $master crdt.del_rc rc6310 1 1000 1:21  1:1:2:1.0
                        $peer crdt.counter rc6310 1 1000 1:1 4 4:3.0
                    }
                    # test "ad + fail" {
                    #     $master crdt.counter rc6311 1 1000 1:3 4 4:2.0
                    #     $master crdt.del_rc rc6311 1 1000 1:2  1:1:2:1.0
                    #     $peer crdt.counter rc6311 1 1000 1:4 4 4:3.0
                    # }
                }
                test "ad + b" {
                    $master crdt.counter rc6320 1 1000 1:3 4 4:2.0
                    $master crdt.del_rc rc6320 1 1000 1:2  1:1:2:1.0
                    $peer crdt.rc rc6320 1 1000 1:1 3:3:3.0 -1
                    
                }
                test "ad + ba" {
                    test "ad + ba success" {
                        $master crdt.counter rc6330 1 1000 1:15 4 4:2.0
                        $master crdt.del_rc rc6330 1 1000 1:12  1:1:2:1.0
                        $peer crdt.rc rc6330 1 1000 1:1 3:3:2.0 -1
                        $peer crdt.counter rc6330 1 1000 1:4 4 4:1.0
                    }
                    # test "ad + ba fail" {
                    #     $master crdt.counter rc6331 1 1000 1:3 4 4:2.0
                    #     $master crdt.del_rc rc6331 1 1000 1:2  1:1:2:1.0
                    #     $peer crdt.rc rc6331 1 1000 1:4 4 4:2.0 -1
                    #     $peer crdt.counter rc6331 1 1000 1:5 4 4:1.0
                        
                    # }
                    
                }
                test "ad + ad" {
                    test "ad + ad success" {
                        $master crdt.counter rc6340 1 1000 1:14 4 4:5.0
                        $master crdt.del_rc rc6340 1 1000 1:13  1:2:2:2.0
                        $peer crdt.counter rc6340 1 1000 1:2 4 4:2.0
                        $peer crdt.del_rc rc6340 1 1000 1:1  1:1:2:1.0
                    }
                    # test "ad + ad fail" {
                    #     $master crdt.counter rc6341 1 1000 1:3 4 4:2.0
                    #     $master crdt.del_rc rc6341 1 1000 1:2  1:2:2:1.0
                    #     $peer crdt.counter rc6341 1 1000 1:4 4 4:3.0
                    #     $peer crdt.del_rc rc6341 1 1000 1:1  1:1:2:2.0
                    # }
                    # test "ad + ad d fail" {
                    #     $master crdt.counter rc6342 1 1000 1:7 4 4:2.0
                    #     $master crdt.del_rc rc6342 1 1000 1:2  1:1:2:1.0
                    #     $peer crdt.counter rc6342 1 1000 1:5 4 4:3.0
                    #     $peer crdt.del_rc rc6342 1 1000 1:4  1:3:2:2.0
                    # }
                    # test "ad + ad ad fail" {
                    #     $master crdt.counter rc6343 1 1000 1:3 4 4:2.0
                    #     $master crdt.del_rc rc6343 1 1000 1:1  1:1:2:1.0
                    #     $peer crdt.counter rc6343 1 1000 1:4 4 4:3.0
                    #     $peer crdt.del_rc rc6343 1 1000 1:2  1:2:2:2.0
                    # }

                    
                }
                test "ad + bad" {
                    test "ad + bad success" {
                        # 6
                        $master crdt.counter rc6350 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6350 1 1000 1:2  1:3:2:3.0
                        $peer crdt.rc rc6350 1 1000 1:4 3:3:2.0 -1
                        $peer crdt.counter rc6350 1 1000 1:2 4 4:2.0
                        $peer crdt.del_rc rc6350 1 1000 1:1  1:1:2:1.0
                    }
                    test "ad + bad fail" {
                        # 4
                        $master crdt.counter rc6351 1 1000 1:3 4 4:2.0
                        $master crdt.del_rc rc6351 1 1000 1:2  1:2:2:1.0
                        $peer crdt.rc rc6351 1 1000 1:4 3:3:2.0 -1
                        $peer crdt.counter rc6351 1 1000 1:4 4 4:3.0
                        $peer crdt.del_rc rc6351 1 1000 1:1  1:1:2:2.0
                    }
                    test "ad + bad d fail" {
                        # 3
                        $master crdt.counter rc6352 1 1000 1:7 4 4:2.0
                        $master crdt.del_rc rc6352 1 1000 1:2  1:1:2:1.0
                        $peer crdt.rc rc6352 1 1000 1:6 3:3:3.0 -1
                        $peer crdt.counter rc6352 1 1000 1:5 4 4:3.0
                        $peer crdt.del_rc rc6352 1 1000 1:4  1:3:2:2.0
                    }
                    test "ad + bad ad fail" {
                        # 5
                        $master crdt.counter rc6353 1 1000 1:3 4 4:2.0
                        $master crdt.del_rc rc6353 1 1000 1:1  1:1:2:1.0
                        $peer crdt.rc rc6353 1 1000 1:5 3:3:4.0 -1
                        $peer crdt.counter rc6353 1 1000 1:4 4 4:3.0
                        $peer crdt.del_rc rc6353 1 1000 1:2  1:2:2:2.0
                        
                    }
                    
                }
            }
        }
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "ad" {
                test "ad + null" {
                    assert_equal [$master crdt.datainfo rc6300] [$peer crdt.datainfo rc6300]
                }
                test "ad + a" {
                    test "ad + success" {
                        $peer get  rc6310 
                    } {1}
                    # test "ad + fail" {
                    #     $peer get  rc6311 a
                    # } {2}
                }
                test "ad + b" {
                    $peer get  rc6320 
                } {1}
                test "ad + ba" {
                    test "ad + ba success" {
                        $peer get  rc6330 
                    } {1}
                    # test "ad + ba fail" {
                    #     $peer get  rc6331 a
                    # } {2}
                }
                test "ad + ad" {
                    test "ad + ad success" {
                        $peer get  rc6340 
                    } {3}
                    # test "ad + ad fail" {
                    #     $peer get  rc6341 a
                    # } {2}
                    # test "ad + ad d fail" {
                    #     $peer get  rc6342 a
                    # } {0}
                    # test "ad + ad ad fail" {
                    #     $peer get  rc6343 a
                    # } {1}
                }
                test "ad + bad" {
                    test "ad + bad success" {
                        $peer get  rc6350 
                    } {6}
                    test "ad + bad fail" {
                        
                        $peer get  rc6351 
                    } {4}
                    test "ad + bad d fail" {
                        $peer get  rc6352 
                    } {3}
                    test "ad + bad ad fail" {
                        $peer get  rc6353 
                    } {5}
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
    $master crdt.debug_gc rc 0
    # set master [redis "127.0.0.1" 6379]
    # $master select 9
    # set master_gid 1
    # set master_host "127.0.0.1"
    # set master_port 6379
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        # set peer [redis "127.0.0.1" 6379]
        # $master select 9
        # set peer_gid 2
        # set peer_host "127.0.0.1"
        # set peer_port 6379
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer crdt.debug_gc rc 0
        test "before" {
            test "ba" {
                test "ba + null" {
                    $master crdt.rc rc6400 1 1000 1:10 3:3:1.0 -1
                    $master crdt.counter rc6400 1 1000 1:3 4 4:2.0
                    
                }
                test "ba + a" {
                    test "ba + success" {
                        # 3
                        $master crdt.rc rc6410 1 1000 1:10 3:3:1.0 -1
                        $master crdt.counter rc6410 1 1000 1:11 4 4:2.0
                        $peer crdt.counter rc6410 1 1000 1:1 4 4:1.0
                         
                    }
                    # test "ba + fail" {
                    #     # 4
                    #     $master crdt.rc rc6411 1 1000 1:2 4 4:1.0 -1
                    #     $master crdt.counter rc6411 1 1000 1:3 4 4:2.0
                    #     $peer crdt.counter rc6411 1 1000 1:4 4 4:3.0
                        
                    # }
                }
                test "ba + b" {
                    test "ba + b success" {
                        # 6
                        $master crdt.rc rc6420 1 1000 1:10 3:3:2.0 -1
                        $master crdt.counter rc6420 1 1000 1:13 4 4:4.0
                        $peer crdt.rc rc6420 1 1000 1:1 3:3:3.0  -1
                    }
                    # test "ba + b fail" {
                    #     # 7
                    #     $master crdt.rc rc6421 1 1000 1:10 4 4:2.0 -1
                    #     $master crdt.counter rc6421 1 1000 1:13 4 4:4.0
                    #     $peer crdt.rc rc6421 1 1000 1:2 4 4:3.0  -1
                        
                    # }
                }
                test "ba + ad" {
                    test "ba + ad success" {
                        # 4
                        $master crdt.rc rc6430 1 1000 1:5 3:3:2.0 -1
                        $master crdt.counter rc6430 1 1000 1:6 4 4:4.0
                        $peer crdt.counter rc6430 1 1000 1:4 4 4:3.0
                        $peer crdt.del_rc rc6430 1 1000 1:3  1:2:2:2.0
                        
                    }
                    # test "ba + ad fail" {
                    #     # 3
                    #     $master crdt.rc rc6431 1 1000 1:11 4 4:2.0 -1
                    #     $master crdt.counter rc6431 1 1000 1:14 4 4:4.0
                    #     $peer crdt.counter rc6431 1 1000 1:5 4 4:3.0
                    #     $peer crdt.del_rc rc6431 1 1000 1:3  1:2:2:2.0
                        
                    # }
                }
                test "ba + ba" {
                    test "ba + ba success" {
                        # 13
                        $master crdt.rc rc6440 1 1000 1:11 3:3:4.0 -1
                        $master crdt.counter rc6440 1 1000 1:14 4 4:9.0
                        $peer crdt.rc rc6440 1 1000 1:3 3:3:3.0 -1
                        $peer crdt.counter rc6440 1 1000 1:2 4 4:2.0
                        
                    }
                    test "ba + ba b fail" {
                        # 12
                        $master crdt.rc rc6441 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6441 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6441 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6441 1 1000 1:2 4 4:2.0
                        
                        
                    }
                    test "ba + ba fail" {
                        # 6
                        $master crdt.rc rc6442 1 1000 1:5 3:3:4.0 -1
                        $master crdt.counter rc6442 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6442 1 1000 1:3 3:3:3.0 -1
                        $peer crdt.counter rc6442 1 1000 1:6 4 4:2.0
                        
                    }
                    test "ba + ba ba fail" {
                        # 5
                        $master crdt.rc rc6443 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6443 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6443 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6443 1 1000 1:6 4 4:2.0
                    }
                }
                test "ba + bad" {
                    test "ba + bad success" {
                        # 12
                        $master crdt.rc rc6450 1 1000 1:5 3:3:4.0 -1
                        $master crdt.counter rc6450 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6450 1 1000 1:3 3:3:3.0 -1
                        $peer crdt.counter rc6450 1 1000 1:2 4 4:2.0
                        $peer crdt.del_rc rc6450 1 1000 1:1  1:1:2:1.0
                        
                    }
                    test "ba + bad b fail" {
                        # 11
                        $master crdt.rc rc6451 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6451 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6451 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6451 1 1000 1:2 4 4:2.0
                        $peer crdt.del_rc rc6451 1 1000 1:1  1:1:2:1.0
                        
                        
                    }
                    test "ba + bad fail" {
                        # 5
                        $master crdt.rc rc6452 1 1000 1:5 3:3:4.0 -1
                        $master crdt.counter rc6452 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6452 1 1000 1:3 3:3:3.0 -1
                        $peer crdt.counter rc6452 1 1000 1:6 4 4:2.0
                        $peer crdt.del_rc rc6452 1 1000 1:1  1:1:2:1.0
                        
                        
                    }
                    test "ba + bad ba fail" {
                        # 4
                        $master crdt.rc rc6453 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6453 1 1000 1:4 4 4:9.0
                        $peer crdt.rc rc6453 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6453 1 1000 1:6 4 4:2.0
                        $peer crdt.del_rc rc6453 1 1000 1:1  1:1:2:1.0
                        # puts [$master crdt.datainfo rc6453]
                        # puts [$peer crdt.datainfo rc6453]
                    }
                }
            }
        }
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "ba" {
                test "ba + null" {
                    assert_equal [$master crdt.datainfo rc6400] [$peer crdt.datainfo rc6400]
                }
                test "ba + a" {
                    test "ba + success" {
                        $peer get  rc6410 
                    } {3}
                    # test "ba + fail" {
                        
                    #     $peer get  rc6411 a
                    # } {4}
                }
                test "ba + b" {
                    test "ba + b success" {
                        
                        $peer get  rc6420 
                    } {6}
                    # test "ba + b fail" {
                        
                    #     $peer get  rc6421 a
                    # } {7}
                }
                test "ba + ad" {
                    test "ba + ad success" {
                        
                        $peer get  rc6430 
                    } {4}
                    # test "ba + ad fail" {
                        
                    #    $peer get  rc6431 a
                    # } {1}
                }
                test "ba + ba" {
                    test "ba + ba success" {
                        $peer get  rc6440 
                    } {13}
                    test "ba + ba b fail" {
                        $peer get  rc6441 
                    } {12}
                    test "ba + ba fail" {
                        $peer get  rc6442 
                    } {6}
                    test "ba + ba ba fail" {
                        
                        $peer get  rc6443 
                    } {5}
                }
                test "ba + bad" {
                   test "ba + bad success" {
                       
                        $peer get  rc6450 
                    } {12}
                    test "ba + bad b fail" {
                        
                        $peer get  rc6451 
                    } {11}
                    test "ba + bad fail" {
                        $peer get  rc6452 
                    } {5}
                    test "ba + bad ba fail" {

                        $peer get  rc6453 
                    } {4}
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
    $master crdt.debug_gc rc 0
    # set master [redis "127.0.0.1" 6379]
    # $master select 9
    # set master_gid 1
    # set master_host "127.0.0.1"
    # set master_port 6379
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        # set peer [redis "127.0.0.1" 6379]
        # $master select 9
        # set peer_gid 2
        # set peer_host "127.0.0.1"
        # set peer_port 6379
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer crdt.debug_gc rc 0
        test "before" {
            test "bad" {
                test "bad + null" {
                    $master crdt.rc rc6500 1 1000 1:3 3:3:4.0 -1
                    $master crdt.counter rc6500 1 1000 1:4 4 4:9.0
                    $master crdt.del_rc rc6500 1 1000 1:1  1:1:2:1.0
                }
                test "bad + a" {
                    test "bad + success" {
                        # 10
                        $master crdt.rc rc6510 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6510 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6510 1 1000 1:1  1:1:2:1.0
                        $peer crdt.counter rc6510 1 1000 1:2 4 4:1.0
                        # puts [$master crdt.datainfo rc6510]
                        # puts [$peer crdt.datainfo rc6510]
                    }
                    test "bad + fail" {
                        # 4
                        $master crdt.rc rc6511 1 1000 1:8 3:3:4.0 -1
                        $master crdt.counter rc6511 1 1000 1:4 4 4:9.0
                        $master crdt.del_rc rc6511 1 1000 1:1  1:1:2:1.0
                        $peer crdt.counter rc6511 1 1000 1:7 4 4:1.0
                        
                    }
                }
                test "bad + b" {
                    test "bad + b success" {
                        # 10
                        $master crdt.rc rc6520 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6520 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6520 1 1000 1:1  1:1:2:1.0
                        $peer crdt.rc rc6520 1 1000 1:2 3:3:1.0 -1
                        
                    }
                    test "bad + b fail" {
                        # 4
                        $master crdt.rc rc6521 1 1000 1:8 3:3:4.0 -1
                        $master crdt.counter rc6521 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6521 1 1000 1:1  1:1:2:1.0
                        $peer crdt.counter rc6521 1 1000 1:7 4 4:1.0
                        
                    }
                }
                test "bad + ad" {
                    test "bad + ad success" {
                        # 9
                        $master crdt.rc rc6530 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6530 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6530 1 1000 1:2  1:2:2:2.0
                        $peer crdt.counter rc6530 1 1000 1:2 4 4:4.0
                        $peer crdt.del_rc rc6530 1 1000 1:1  1:1:2:1.0
                        
                    }
                    test "bad + ad fail" {
                        # 6
                        $master crdt.rc rc6531 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6531 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6531 1 1000 1:1  1:3:2:2.0
                        $peer crdt.counter rc6531 1 1000 1:5 4 4:4.0
                        $peer crdt.del_rc rc6531 1 1000 1:1  1:2:2:1.0
                        
                    }
                    test "bad + ad d fail" {
                        # 10
                        $master crdt.rc rc6532 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6532 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6532 1 1000 1:1  1:1:2:2.0
                        $peer crdt.counter rc6532 1 1000 1:3 4 4:4.0
                        $peer crdt.del_rc rc6532 1 1000 1:2  1:2:2:1.0
                        
                    }
                    test "bad + ad ad fail" {
                        # 7
                        $master crdt.rc rc6533 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6533 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6533 1 1000 1:1  1:1:2:2.0
                        $peer crdt.counter rc6533 1 1000 1:5 4 4:4.0
                        $peer crdt.del_rc rc6533 1 1000 1:2  1:2:2:1.0
                    }
                }
                test "bad + ba" {
                    test "bad + ba success" {
                        # 9
                        $master crdt.rc rc6540 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6540 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6540 1 1000 1:2  1:2:2:2.0
                        $peer crdt.rc rc6540 1 1000 1:2 3:3:3.0 -1
                        $peer crdt.counter rc6540 1 1000 1:3 4 4:6.0
                    }
                    test "bad + ba b fail" {
                        # 8
                        $master crdt.rc rc6541 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6541 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6541 1 1000 1:2  1:2:2:2.0
                        $peer crdt.rc rc6541 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6541 1 1000 1:3 4 4:5.0
                        
                    }
                    test "bad + ba fail" {
                        # 7
                        $master crdt.rc rc6542 1 1000 1:6 3:3:4.0 -1
                        $master crdt.counter rc6542 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6542 1 1000 1:2  1:2:2:2.0
                        $peer crdt.rc rc6542 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6542 1 1000 1:5 4 4:5.0
                        
                    }
                    test "bad + ba  ba fail" {
                        # 6
                        $master crdt.rc rc6543 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6543 1 1000 1:4 4 4:7.0
                        $master crdt.del_rc rc6543 1 1000 1:2  1:2:2:2.0
                        $peer crdt.rc rc6543 1 1000 1:5 3:3:3.0 -1
                        $peer crdt.counter rc6543 1 1000 1:6 4 4:5.0
                    }
                }
                test "bad + bad" {
                    test "bad + bad success" {
                        # 9
                        $master crdt.rc rc6550 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6550 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6550 1 1000 1:4  1:4:2:2.0
                        $peer crdt.rc rc6550 1 1000 1:2 3:3:3.0 -1
                        $peer crdt.counter rc6550 1 1000 1:3 4 4:6.0
                        $peer crdt.del_rc rc6550 1 1000 1:2  1:2:2:1.0
                        
                    }
                    test "bad + bad  b fail" {
                        # 8
                        $master crdt.rc rc6551 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6551 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6551 1 1000 1:4  1:4:2:2.0
                        $peer crdt.rc rc6551 1 1000 1:8 3:3:3.0 -1
                        $peer crdt.counter rc6551 1 1000 1:3 4 4:6.0
                        $peer crdt.del_rc rc6551 1 1000 1:2  1:2:2:1.0
                    }
                    test "bad + bad  fail" {
                        # 7
                        $master crdt.rc rc6552 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6552 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6552 1 1000 1:4  1:4:2:2.0
                        $peer crdt.rc rc6552 1 1000 1:2 3:3:3.0 -1
                        $peer crdt.counter rc6552 1 1000 1:7 4 4:5.0
                        $peer crdt.del_rc rc6552 1 1000 1:2  1:2:2:1.0
                        
                    }
                    test "bad + bad  d fail" {
                        # 7
                        $master crdt.rc rc6553 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6553 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6553 1 1000 1:3  1:2:2:2.0
                        $peer crdt.rc rc6553 1 1000 1:6 3:3:3.0 -1
                        $peer crdt.counter rc6553 1 1000 1:3 4 4:4.0
                        $peer crdt.del_rc rc6553 1 1000 1:4  1:3:2:4.0
                    }
                    test "bad + bad  ba fail" {
                        # 8
                        $master crdt.rc rc6554 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6554 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6554 1 1000 1:4  1:4:2:2.0
                        $peer crdt.rc rc6554 1 1000 1:4 3:3:3.0 -1
                        $peer crdt.counter rc6554 1 1000 1:6 4 4:6.0
                        $peer crdt.del_rc rc6554 1 1000 1:2  1:2:2:2.0

                    }
                    test "bad + bad  bd fail" {
                        # 6
                        $master crdt.rc rc6555 1 1000 1:3 3:3:4.0 -1
                        $master crdt.counter rc6555 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6555 1 1000 1:2  1:2:2:2.0
                        $peer crdt.rc rc6555 1 1000 1:8 3:3:3.0 -1
                        $peer crdt.counter rc6555 1 1000 1:4 4 4:6.0
                        $peer crdt.del_rc rc6555 1 1000 1:3  1:3:2:4.0
                    }
                    test "bad + bad  ad fail" {
                        # 6
                        $master crdt.rc rc6556 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6556 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6556 1 1000 1:4  1:3:2:2.0
                        $peer crdt.rc rc6556 1 1000 1:2 3:3:3.0 -1
                        $peer crdt.counter rc6556 1 1000 1:7 4 4:6.0
                        $peer crdt.del_rc rc6556 1 1000 1:5  1:4:2:4.0
                    }
                    test "bad + bad  bad fail" {
                        # 7
                        $master crdt.rc rc6557 1 1000 1:7 3:3:4.0 -1
                        $master crdt.counter rc6557 1 1000 1:5 4 4:7.0
                        $master crdt.del_rc rc6557 1 1000 1:4  1:4:2:2.0
                        $peer crdt.rc rc6557 1 1000 1:8 3:3:3.0 -1
                        $peer crdt.counter rc6557 1 1000 1:6 4 4:6.0
                        $peer crdt.del_rc rc6557 1 1000 1:5  1:5:2:2.0
                        puts [$master crdt.datainfo rc6557]
                        puts [$peer crdt.datainfo rc6557]
                    }
                }
            }
        }
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "bad" {
                test "bad + null" {
                    assert_equal [$master crdt.datainfo rc6500] [$peer crdt.datainfo rc6500]
                }
                test "bad + a" {
                    test "bad + success" {
                        $peer get  rc6510 
                    } {10}
                    test "bad + fail" {
                        $peer get  rc6511 
                    } {4}
                }
                test "bad + b" {
                    test "bad + b success" {
                        $peer get  rc6520 
                    } {10}
                    test "bad + b fail" {
                        $peer get  rc6521 
                    } {4}
                }
                test "bad + ad" {
                    test "bad + ad success" {
                        $peer get  rc6530 
                    } {9}
                    test "bad + ad fail" {
                        $peer get  rc6531 
                    } {6}
                    test "bad + ad d fail" {
                        $peer get  rc6532 
                    } {10}
                    test "bad + ad ad fail" {
                        $peer get  rc6533 
                    } {7}
                }
                test "bad + ba" {
                    test "bad + ba success" {
                        $peer get  rc6540 
                    } {9}
                    test "bad + ba b fail" {
                        $peer get  rc6541 
                    } {8}
                    test "bad + ba fail" {
                        $peer get  rc6542 
                    } {7}
                    test "bad + ba ba fail" {
                        $peer get  rc6543 
                    } {6}
                }
                test "bad + bad" {
                    test "bad + bad success" {
                        $peer get  rc6550 
                    } {9}
                    test "bad + bad b fail" {
                        $peer get  rc6551 
                    } {8}
                    test "bad + bad  fail" {
                        $peer get  rc6552 
                    } {7}
                    test "bad + bad  d fail" {
                        $peer get  rc6553 
                    } {7}
                    test "bad + bad  ba fail" {
                        $peer get  rc6554 
                    } {8}
                    test "bad + bad  bd fail" {
                        $peer get  rc6555 
                    } {6}
                    test "bad + bad  ad fail" {
                        $peer get  rc6556 
                    } {6}
                    test "bad + bad  bad fail" {
                        puts [$peer crdt.datainfo rc6557]
                        $peer get  rc6557 
                    } {7}
                }
            }
        }
    }
}