start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    $master crdt.debug_gc zset 0
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
        $peer crdt.debug_gc zset 0
        test "before" {
            test "a" {
                test "a + null" {
                    $master crdt.zincrby zset6100 1 1000 1:10 a 2:1.0 
                }
                test "a + a" {
                    test "before a + a success" {
                        $master crdt.zincrby zset6101 1 1000 1:20 a 2:1.0 
                        $peer crdt.zincrby zset6101 1 1000 1:1 a 2:2.0 
                    }
                    # test "before a + a fail" {
                    #     $master crdt.zincrby zset6102 1 1000 1:1 a 2:1.0 
                    #     $peer crdt.zincrby zset6102 1 1000 1:2 a 2:2.0 
                    # }
                }
                test "a + b" {
                    $master crdt.zincrby zset6120 1 1000 1:11 a 2:1.0 
                    $peer crdt.zadd zset6120 1 1000 1:3 a 2:2.0 
                }
                test "a + ba" {
                    test "before a + ba success" {
                        $master crdt.zincrby zset6130 1 1000 1:11 a 2:1.0 
                        $peer crdt.zadd zset6130 1 1000 1:1 a 2:2.0 
                        $peer crdt.zincrby zset6130 1 1000 1:2 a 2:2.0 
                    }
                    # test "before a + ba fail" {
                    #     $master crdt.zincrby zset6131 1 1000 1:2 a 2:1.0 
                    #     $peer crdt.zadd zset6131 1 1000 1:1 a 2:2.0 
                    #     $peer crdt.zincrby zset6131 1 1000 1:3 a 2:2.0
                    # }
                }
                test "a + ad" {
                    test "before a + ad success" {
                        $master crdt.zincrby zset6140 1 1000 1:50 a 2:3.0 
                        $peer crdt.zincrby zset6140 1 1000 1:2 a 2:2.0 
                        $peer crdt.zrem zset6140 1 1000 1:3 3:1:a,1:1:2:1.0
                    }
                    # test "before a + ad fail" {
                    #     $master crdt.zincrby zset6141 1 1000 1:1 a 2:1.0 
                    #     $peer crdt.zincrby zset6141 1 1000 1:4 a 2:3.0 
                    #     $peer crdt.zrem zset6141 1 1000 1:3 3:1:a,1:2:2:2.0
                    # }
                }
                test "a + bad" {
                    test "before a + bad success" {
                        $master crdt.zincrby zset6150 1 1000 1:6 a 2:3.0 
                        $peer crdt.zadd zset6150 1 1000 {1:7;2:1} a 2:2.0 
                        $peer crdt.zincrby zset6150 1 1000 1:3 a 2:2.0 
                        $peer crdt.zrem zset6150 1 1000 1:4 3:1:a,1:1:2:1.0
                    }
                    # test "before a + ba fail" {
                    #     $master crdt.zincrby zset6151 1 1000 1:1 a 2:1.0 
                    #     $peer crdt.zadd zset6151 1 1000 1:5 a 2:2.0 
                    #     $peer crdt.zincrby zset6151 1 1000 1:3 a 2:2.0 
                    #     $peer crdt.zrem zset6151 1 1000 1:4 3:1:a,1:1:2:1.0
                    # }
                }
            }
        }
        $master crdt.set set_vcu vcu 1 1000 1:100000
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "a" {
                test "a + null" {
                    assert_equal [$master crdt.datainfo zset6100] [$peer crdt.datainfo zset6100]
                }
                test "a + a" {
                    test "a + a success" {
                        $peer zscore zset6101 a 
                    } {1}
                    # test "a + a fail" {
                    #     $peer zscore zset6102 a 
                    # } {2}
                }
                test "a + b" {
                    $peer zscore zset6120 a 
                } {3}
                test "a + ba" {
                    test "before a + ba success" {
                        $peer zscore zset6130 a
                    } {3}
                    # test "before a + ba fail" {
                    #     $peer zscore zset6131 a
                    # } {4}
                } 
                test "a + ad" {
                    test "before a + ad success" {
                        $peer zscore zset6140 a
                    } {2}
                    # test "before a + ad fail" {
                    #     $peer zscore zset6141 a
                    # } {1}
                } 
                test "a + bad" {
                    test "before a + bad success" {
                        $master zscore zset6150 a
                    } {4}
                    # test "before a + bad fail" {
                    #     $peer zscore zset6151 a
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
    $master crdt.debug_gc zset 0
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
        $peer crdt.debug_gc zset 0
        test "before" {
            test "b" {
                test "b + null" {
                    $master crdt.zadd zset6200 1 1000 1:10 a 2:1.0 
                }
                test "b + a" {
                    $master crdt.zadd zset6210 1 1000 1:10 a 2:1.0 
                    $peer crdt.zincrby zset6210 1 1000 1:2 a 2:1.0
                }
                test "b + b" {
                    test " b + b success" {
                        $master crdt.zadd zset6220 1 1000 1:10 a 2:1.0 
                        $peer crdt.zadd zset6220 1 1000 1:1 a 2:2.0
                    }
                    # test "b + b fail" {
                    #     $master crdt.zadd zset6221 1 1000 1:1 a 2:1.0 
                    #     $peer crdt.zadd zset6221 1 1000 1:2 a 2:2.0
                    # }
                }
                test "b + ad" {
                    $master crdt.zadd zset6230 1 1000 1:11 a 2:1.0 
                    $peer crdt.zincrby zset6230 1 1000 1:1 a 2:2.0
                    $peer crdt.zrem zset6230 1 1000 1:2 3:1:a,1:1:2:1.0
                }
                test "b + ba" {
                    test "b + ba success" {
                        $master crdt.zadd zset6240 1 1000 1:14 a 2:1.0
                        $peer crdt.zadd zset6240 1 1000 1:2 a 2:2.0 
                        $peer crdt.zincrby zset6240 1 1000 1:3 a 2:2.0
                    }
                    # test "b + ba fail" {
                    #     $master crdt.zadd zset6241 1 1000 1:1 a 2:1.0
                    #     $peer crdt.zadd zset6241 1 1000 1:2 a 2:2.0 
                    #     $peer crdt.zincrby zset6241 1 1000 1:3 a 2:2.0
                    # }
                    
                }
                test "b + bad" {
                    test "b + bad success" {
                        $master crdt.zadd zset6250 1 1000 1:6 a 2:1.0 
                        $peer crdt.zadd zset6250 1 1000 1:5 a 2:2.0 
                        $peer crdt.zincrby zset6250 1 1000 1:3 a 2:2.0 
                        $peer crdt.zrem zset6250 1 1000 1:4 3:1:a,1:1:2:1.0
                    }
                    # test "b + ba fail" {
                    #     $master crdt.zadd zset6251 1 1000 1:2 a 2:1.0 
                    #     $peer crdt.zadd zset6251 1 1000 1:5 a 2:2.0 
                    #     $peer crdt.zincrby zset6251 1 1000 1:3 a 2:2.0 
                    #     $peer crdt.zrem zset6251 1 1000 1:4 3:1:a,1:1:2:1.0
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
                    assert_equal [$master crdt.datainfo zset6200] [$peer crdt.datainfo zset6200]
                }
                test "b + a" {
                    $peer zscore zset6210 a
                } {2}
                test "b + b" {
                    test "b + b success" {
                        $peer zscore zset6220 a
                    } {1}
                    # test "b + b fail" {
                    #     $peer zscore zset6221 a
                    # } {2}
                }
                test "b + ad" {
                    $peer zscore zset6230 a
                } {1}
                test "b + ba" {
                    test "b + ba success" {
                        $peer zscore zset6240 a
                    } {3}
                    # test "b + ba fail" {
                    #     $peer zscore zset6241 a
                    # } {4}
                } 
                test "b + bad" {
                    test "b + bad success" {
                        $peer zscore zset6250 a
                    } {2}
                    # test "b + bad fail" {
                    #     $peer zscore zset6251 a
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
    $master crdt.debug_gc zset 0
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
        $peer crdt.debug_gc zset 0
        test "before" {
            test "ad" {
                test "ad + null" {
                    $master crdt.zincrby zset6300 1 1000 1:31 a 2:2.0
                    $master crdt.zrem zset6300 1 1000 1:21 3:1:a,1:1:2:1.0
                }
                test "ad + a" {
                    test "ad + a success" {
                        $master crdt.zincrby zset6310 1 1000 1:31 a 2:2.0
                        $master crdt.zrem zset6310 1 1000 1:21 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6310 1 1000 1:1 a 2:3.0
                    }
                    # test "ad + a fail" {
                    #     $master crdt.zincrby zset6311 1 1000 1:3 a 2:2.0
                    #     $master crdt.zrem zset6311 1 1000 1:2 3:1:a,1:1:2:1.0
                    #     $peer crdt.zincrby zset6311 1 1000 1:4 a 2:3.0
                    # }
                }
                test "ad + b" {
                    $master crdt.zincrby zset6320 1 1000 1:3 a 2:2.0
                    $master crdt.zrem zset6320 1 1000 1:2 3:1:a,1:1:2:1.0
                    $peer crdt.zadd zset6320 1 1000 {1:1;2:1} a 2:3.0
                    
                }
                test "ad + ba" {
                    test "ad + ba success" {
                        $master crdt.zincrby zset6330 1 1000 1:15 a 2:2.0
                        $master crdt.zrem zset6330 1 1000 1:12 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6330 1 1000 1:1 a 2:2.0 
                        $peer crdt.zincrby zset6330 1 1000 1:4 a 2:1.0
                    }
                    # test "ad + ba fail" {
                    #     $master crdt.zincrby zset6331 1 1000 1:3 a 2:2.0
                    #     $master crdt.zrem zset6331 1 1000 1:2 3:1:a,1:1:2:1.0
                    #     $peer crdt.zadd zset6331 1 1000 1:4 a 2:2.0 
                    #     $peer crdt.zincrby zset6331 1 1000 1:5 a 2:1.0
                        
                    # }
                    
                }
                test "ad + ad" {
                    test "ad + ad success" {
                        $master crdt.zincrby zset6340 1 1000 1:14 a 2:5.0
                        $master crdt.zrem zset6340 1 1000 1:13 3:1:a,1:2:2:2.0
                        $peer crdt.zincrby zset6340 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6340 1 1000 1:1 3:1:a,1:1:2:1.0
                    }
                    # test "ad + ad a fail" {
                    #     $master crdt.zincrby zset6341 1 1000 1:3 a 2:2.0
                    #     $master crdt.zrem zset6341 1 1000 1:2 3:1:a,1:2:2:1.0
                    #     $peer crdt.zincrby zset6341 1 1000 1:4 a 2:3.0
                    #     $peer crdt.zrem zset6341 1 1000 1:1 3:1:a,1:1:2:2.0
                    # }
                    # test "ad + ad d fail" {
                    #     $master crdt.zincrby zset6342 1 1000 1:7 a 2:2.0
                    #     $master crdt.zrem zset6342 1 1000 1:2 3:1:a,1:1:2:1.0
                    #     $peer crdt.zincrby zset6342 1 1000 1:5 a 2:3.0
                    #     $peer crdt.zrem zset6342 1 1000 1:4 3:1:a,1:3:2:2.0
                    # }
                    # test "ad + ad ad fail" {
                    #     $master crdt.zincrby zset6343 1 1000 1:3 a 2:2.0
                    #     $master crdt.zrem zset6343 1 1000 1:1 3:1:a,1:1:2:1.0
                    #     $peer crdt.zincrby zset6343 1 1000 1:4 a 2:3.0
                    #     $peer crdt.zrem zset6343 1 1000 1:2 3:1:a,1:2:2:2.0
                    # }

                    
                }
                test "ad + bad" {
                    test "ad + bad success" {
                        # 6
                        $master crdt.zincrby zset6350 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6350 1 1000 1:2 3:1:a,1:3:2:3.0
                        $peer crdt.zadd zset6350 1 1000 {1:4;2:1} a 2:2.0
                        $peer crdt.zincrby zset6350 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6350 1 1000 1:1 3:1:a,1:1:2:1.0
                    }
                    test "ad + bad a fail" {
                        # 4
                        $master crdt.zincrby zset6351 1 1000 1:3 a 2:2.0
                        $master crdt.zrem zset6351 1 1000 1:2 3:1:a,1:2:2:1.0
                        $peer crdt.zadd zset6351 1 1000 {1:4;2:1} a 2:2.0
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
        }
        $master crdt.set set_vcu vcu 1 1000 1:100000
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer
        wait_for_peer_sync $master
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "ad" {
                test "ad + null" {
                    assert_equal [$master crdt.datainfo zset6300] [$peer crdt.datainfo zset6300]
                }
                test "ad + a" {
                    test "ad + a success" {
                        $peer zscore zset6310 a
                    } {1}
                    # test "ad + a fail" {
                    #     $peer zscore zset6311 a
                    # } {2}
                }
                test "ad + b" {
                    $master zscore zset6320 a
                } {1}
                test "ad + ba" {
                    test "ad + ba success" {
                        $peer zscore zset6330 a
                    } {1}
                    # test "ad + ba fail" {
                    #     $peer zscore zset6331 a
                    # } {2}
                }
                test "ad + ad" {
                    test "ad + ad success" {
                        $peer zscore zset6340 a
                    } {3}
                    # test "ad + ad a fail" {
                    #     $peer zscore zset6341 a
                    # } {2}
                    # test "ad + ad d fail" {
                    #     $peer zscore zset6342 a
                    # } {0}
                    # test "ad + ad ad fail" {
                    #     $peer zscore zset6343 a
                    # } {1}
                }
                test "ad + bad" {
                    test "ad + bad success" {
                        $master zscore zset6350 a
                    } {6}
                    test "ad + bad a fail" {
                        
                        $master zscore zset6351 a
                    } {4}
                    test "ad + bad d fail" {
                        $peer zscore zset6352 a
                    } {3}
                    test "ad + bad ad fail" {
                        $peer zscore zset6353 a
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
    $master crdt.debug_gc zset 0
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
        $peer crdt.debug_gc zset 0
        test "before" {
            test "ba" {
                test "ba + null" {
                    $master crdt.zadd zset6400 1 1000 1:10 a 2:1.0
                    $master crdt.zincrby zset6400 1 1000 1:3 a 2:2.0
                    
                }
                test "ba + a" {
                    test "ba + a success" {
                        # 3
                        $master crdt.zadd zset6410 1 1000 1:10 a 2:1.0
                        $master crdt.zincrby zset6410 1 1000 1:11 a 2:2.0
                        $peer crdt.zincrby zset6410 1 1000 1:1 a 2:1.0
                         
                    }
                    # test "ba + a fail" {
                    #     # 4
                    #     $master crdt.zadd zset6411 1 1000 1:2 a 2:1.0
                    #     $master crdt.zincrby zset6411 1 1000 1:3 a 2:2.0
                    #     $peer crdt.zincrby zset6411 1 1000 1:4 a 2:3.0
                        
                    # }
                }
                test "ba + b" {
                    test "ba + b success" {
                        # 6
                        $master crdt.zadd zset6420 1 1000 1:10 a 2:2.0
                        $master crdt.zincrby zset6420 1 1000 1:13 a 2:4.0
                        $peer crdt.zadd zset6420 1 1000 1:1 a 2:3.0 
                    }
                    # test "ba + b fail" {
                    #     # 7
                    #     $master crdt.zadd zset6421 1 1000 1:10 a 2:2.0
                    #     $master crdt.zincrby zset6421 1 1000 1:13 a 2:4.0
                    #     $peer crdt.zadd zset6421 1 1000 1:2 a 2:3.0 
                        
                    # }
                }
                test "ba + ad" {
                    test "ba + ad success" {
                        # 4
                        $master crdt.zadd zset6430 1 1000 1:5 a 2:2.0
                        $master crdt.zincrby zset6430 1 1000 1:6 a 2:4.0
                        $peer crdt.zincrby zset6430 2 1000 {2:1} a 2:0.0
                        $peer crdt.zincrby zset6430 1 1000 {1:4;2:1} a 2:3.0
                        $peer crdt.zrem zset6430 1 1000 1:3 3:1:a,1:2:2:2.0
                        
                    }
                    # test "ba + ad fail" {
                    #     # 3
                    #     $master crdt.zadd zset6431 1 1000 1:11 a 2:2.0
                    #     $master crdt.zincrby zset6431 1 1000 1:14 a 2:4.0
                    #     $peer crdt.zincrby zset6431 1 1000 1:5 a 2:3.0
                    #     $peer crdt.zrem zset6431 1 1000 1:3 3:1:a,1:2:2:2.0
                        
                    # }
                }
                test "ba + ba" {
                    test "ba + ba success" {
                        # 13
                        $master crdt.zadd zset6440 1 1000 1:11 a 2:4.0
                        $master crdt.zincrby zset6440 1 1000 1:14 a 2:9.0
                        $peer crdt.zadd zset6440 1 1000 1:3 a 2:3.0
                        $peer crdt.zincrby zset6440 1 1000 1:2 a 2:2.0
                        
                    }
                    test "ba + ba b fail" {
                        # 12
                        $master crdt.zadd zset6441 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6441 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6441 1 1000 {1:5;2:1} a 2:3.0
                        $peer crdt.zincrby zset6441 1 1000 1:2 a 2:2.0
                        
                        
                    }
                    test "ba + ba a fail" {
                        # 6
                        $master crdt.zadd zset6442 1 1000 1:5 a 2:4.0
                        $master crdt.zincrby zset6442 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6442 1 1000 {1:3;2:1} a 2:3.0
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
                        $peer crdt.zadd zset6450 1 1000 {1:3;2:1} a 2:3.0
                        $peer crdt.zincrby zset6450 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6450 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                    }
                    test "ba + bad b fail" {
                        # 11
                        $master crdt.zadd zset6451 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6451 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6451 1 1000 {1:5;2:1} a 2:3.0
                        $peer crdt.zincrby zset6451 1 1000 1:2 a 2:2.0
                        $peer crdt.zrem zset6451 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                        
                    }
                    test "ba + bad a fail" {
                        # 5
                        $master crdt.zadd zset6452 1 1000 1:5 a 2:4.0
                        $master crdt.zincrby zset6452 1 1000 1:4 a 2:9.0
                        $peer crdt.zadd zset6452 1 1000 {1:3;2:1} a 2:3.0
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
        }
        $master crdt.set set_vcu vcu 1 1000 1:100000
        $master peerof $peer_gid $peer_host $peer_port
         wait_for_peer_sync $master
        $peer peerof $master_gid $master_host $master_port
        wait_for_peer_sync $peer
       
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "ba" {
                test "ba + null" {
                    assert_equal [$master crdt.datainfo zset6400] [$peer crdt.datainfo zset6400]
                }
                test "ba + a" {
                    test "ba + a success" {
                        $peer zscore zset6410 a
                    } {3}
                    # test "ba + a fail" {
                        
                    #     $peer zscore zset6411 a
                    # } {4}
                }
                test "ba + b" {
                    test "ba + b success" {
                        
                        $peer zscore zset6420 a
                    } {6}
                    # test "ba + b fail" {
                        
                    #     $peer zscore zset6421 a
                    # } {7}
                }
                test "ba + ad" {
                    test "ba + ad success" {
                        # puts [$master crdt.datainfo zset6430]
                        $master zscore zset6430 a
                    } {4}
                    # test "ba + ad fail" {
                        
                    #    $peer zscore zset6431 a
                    # } {1}
                }
                test "ba + ba" {
                    test "ba + ba success" {
                        $peer zscore zset6440 a
                    } {13}
                    test "ba + ba b fail" {
                        $master zscore zset6441 a
                    } {12}
                    test "ba + ba a fail" {
                        $master zscore zset6442 a
                    } {6}
                    test "ba + ba ba fail" {
                        
                        $peer zscore zset6443 a
                    } {5}
                }
                test "ba + bad" {
                   test "ba + bad success" {
                       
                        $master zscore zset6450 a
                    } {12}
                    test "ba + bad b fail" {
                        
                        $master zscore zset6451 a
                    } {11}
                    test "ba + bad a fail" {
                        $master zscore zset6452 a
                    } {5}
                    test "ba + bad ba fail" {

                        $peer zscore zset6453 a
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
    $master crdt.debug_gc zset 0
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
        $peer crdt.debug_gc zset 0
        test "before" {
            test "bad" {
                test "bad + null" {
                    $master crdt.zadd zset6500 1 1000 1:13 a 2:4.0
                    $master crdt.zincrby zset6500 1 1000 1:4 a 2:9.0
                    $master crdt.zrem zset6500 1 1000 1:1 3:1:a,1:1:2:1.0
                }
                test "bad + a" {
                    test "bad + a success" {
                        # 10
                        $master crdt.zadd zset6510 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6510 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6510 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6510 2 1000 2:1 a 2:0
                        $peer crdt.zincrby zset6510 1 1000 {1:2;2:1} a 2:1.0
                        # puts [$master crdt.datainfo zset6510]
                        # puts [$peer crdt.datainfo zset6510]
                    }
                    test "bad + a fail" {
                        # 4
                        $master crdt.zadd zset6511 1 1000 1:8 a 2:4.0
                        $master crdt.zincrby zset6511 1 1000 1:4 a 2:9.0
                        $master crdt.zrem zset6511 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6511 2 1000 {2:1} a 2:0.0
                        $peer crdt.zincrby zset6511 1 1000 {1:7;2:2} a 2:1.0
                        
                    }
                }
                test "bad + b" {
                    test "bad + b success" {
                        # 10
                        $master crdt.zadd zset6520 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6520 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6520 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zadd zset6520 1 1000 {1:2;2:1} a 2:1.0
                        
                    }
                    test "bad + b fail" {
                        # 4
                        $master crdt.zadd zset6521 1 1000 1:8 a 2:4.0
                        $master crdt.zincrby zset6521 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6521 1 1000 1:1 3:1:a,1:1:2:1.0
                        $peer crdt.zincrby zset6521 2 1000 2:1 a 2:0.0
                        $peer crdt.zincrby zset6521 1 1000 {1:7;2:2} a 2:1.0
                        
                    }
                }
                test "bad + ad" {
                    test "bad + ad success" {
                        # 9
                        $master crdt.zadd zset6530 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6530 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6530 1 1000 1:2 3:1:a,1:2:2:2.0
                         $peer crdt.zincrby zset6530 2 1000 {2:1} a 2:0.0
                        $peer crdt.zincrby zset6530 1 1000 {1:2;2:1} a 2:4.0
                        $peer crdt.zrem zset6530 1 1000 1:1 3:1:a,1:1:2:1.0
                        
                    }
                    test "bad + ad a fail" {
                        # 6
                        $master crdt.zadd zset6531 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6531 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6531 1 1000 1:1 3:1:a,1:3:2:2.0
                        $peer crdt.zincrby zset6531 2 1000 {2:1} a 2:0.0
                        $peer crdt.zincrby zset6531 1 1000 {1:5;2:1} a 2:4.0
                        $peer crdt.zrem zset6531 1 1000 1:1 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + ad d fail" {
                        # 10
                        $master crdt.zadd zset6532 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6532 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6532 1 1000 1:1 3:1:a,1:1:2:2.0
                        $peer crdt.zincrby zset6532 2 1000 {2:1} a 2:0.0
                        $peer crdt.zincrby zset6532 1 1000 {1:3;2:1} a 2:4.0
                        $peer crdt.zrem zset6532 1 1000 1:2 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + ad ad fail" {
                        # 7
                        $master crdt.zadd zset6533 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6533 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6533 1 1000 1:1 3:1:a,1:1:2:2.0
                        $peer crdt.zincrby zset6533 2 1000 {2:1} a 2:0.0
                        $peer crdt.zincrby zset6533 1 1000 {1:5;2:1} a 2:4.0
                        $peer crdt.zrem zset6533 1 1000 1:2 3:1:a,1:2:2:1.0
                    }
                }
                test "bad + ba" {
                    test "bad + ba success" {
                        # 9
                        $master crdt.zadd zset6540 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6540 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6540 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6540 1 1000 {1:2;2:1} a 2:3.0
                        $peer crdt.zincrby zset6540 1 1000 1:3 a 2:6.0
                    }
                    test "bad + ba b fail" {
                        # 8
                        $master crdt.zadd zset6541 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6541 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6541 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6541 1 1000 {1:5;2:1} a 2:3.0
                        $peer crdt.zincrby zset6541 1 1000 1:3 a 2:5.0
                        
                    }
                    test "bad + ba a fail" {
                        # 7
                        $master crdt.zadd zset6542 1 1000 1:6 a 2:4.0
                        $master crdt.zincrby zset6542 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6542 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6542 1 1000 {1:5;2:1} a 2:3.0
                        $peer crdt.zincrby zset6542 1 1000 1:5 a 2:5.0
                        
                    }
                    test "bad + ba  ba fail" {
                        # 6
                        $master crdt.zadd zset6543 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6543 1 1000 1:4 a 2:7.0
                        $master crdt.zrem zset6543 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6543 1 1000 {1:5;2:1} a 2:3.0
                        $peer crdt.zincrby zset6543 1 1000 1:6 a 2:5.0
                    }
                }
                test "bad + bad" {
                    test "bad + bad success" {
                        # 9
                        $master crdt.zadd zset6550 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6550 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6550 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6550 1 1000 {1:2;2:1} a 2:3.0
                        $peer crdt.zincrby zset6550 1 1000 1:3 a 2:6.0
                        $peer crdt.zrem zset6550 1 1000 1:2 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + bad  b fail" {
                        # 8
                        $master crdt.zadd zset6551 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6551 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6551 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6551 1 1000 {1:8;2:1} a 2:3.0
                        $peer crdt.zincrby zset6551 1 1000 1:3 a 2:6.0
                        $peer crdt.zrem zset6551 1 1000 1:2 3:1:a,1:2:2:1.0
                    }
                    test "bad + bad  a fail" {
                        # 7
                        $master crdt.zadd zset6552 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6552 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6552 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6552 1 1000 {1:2;2:1} a 2:3.0
                        $peer crdt.zincrby zset6552 1 1000 1:7 a 2:5.0
                        $peer crdt.zrem zset6552 1 1000 1:2 3:1:a,1:2:2:1.0
                        
                    }
                    test "bad + bad  d fail" {
                        # 7
                        $master crdt.zadd zset6553 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6553 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6553 1 1000 1:3 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6553 1 1000 {1:6;2:1} a 2:3.0
                        $peer crdt.zincrby zset6553 1 1000 1:3 a 2:4.0
                        $peer crdt.zrem zset6553 1 1000 1:4 3:1:a,1:3:2:4.0
                    }
                    test "bad + bad  ba fail" {
                        # 8
                        $master crdt.zadd zset6554 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6554 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6554 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6554 1 1000 {1:4;2:1} a 2:3.0
                        $peer crdt.zincrby zset6554 1 1000 1:6 a 2:6.0
                        $peer crdt.zrem zset6554 1 1000 1:2 3:1:a,1:2:2:2.0

                    }
                    test "bad + bad  bd fail" {
                        # 6
                        $master crdt.zadd zset6555 1 1000 1:3 a 2:4.0
                        $master crdt.zincrby zset6555 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6555 1 1000 1:2 3:1:a,1:2:2:2.0
                        $peer crdt.zadd zset6555 1 1000 {1:8;2:1} a 2:3.0
                        $peer crdt.zincrby zset6555 1 1000 1:4 a 2:6.0
                        $peer crdt.zrem zset6555 1 1000 1:3 3:1:a,1:3:2:4.0
                    }
                    test "bad + bad  ad fail" {
                        # 6
                        $master crdt.zadd zset6556 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6556 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6556 1 1000 1:4 3:1:a,1:3:2:2.0
                        $peer crdt.zadd zset6556 1 1000 {1:2;2:1} a 2:3.0
                        $peer crdt.zincrby zset6556 1 1000 1:7 a 2:6.0
                        $peer crdt.zrem zset6556 1 1000 1:5 3:1:a,1:4:2:4.0
                    }
                    test "bad + bad  bad fail" {
                        # 7
                        $master crdt.zadd zset6557 1 1000 1:7 a 2:4.0
                        $master crdt.zincrby zset6557 1 1000 1:5 a 2:7.0
                        $master crdt.zrem zset6557 1 1000 1:4 3:1:a,1:4:2:2.0
                        $peer crdt.zadd zset6557 1 1000 {1:8;2:1} a 2:3.0
                        $peer crdt.zincrby zset6557 1 1000 1:6 a 2:6.0
                        $peer crdt.zrem zset6557 1 1000 1:5 3:1:a,1:5:2:2.0
                    }
                }
            }
        }
        
        $master crdt.set set_vcu vcu 1 1000 1:100000
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $master
       
        $peer peerof $master_gid $master_host $master_port
         wait_for_peer_sync $peer
        # after 5000
        # print_log_file  $peer_log
        test "after" {
            test "bad" {
                test "bad + null" {
                    assert_equal [$master crdt.datainfo zset6500] [$peer crdt.datainfo zset6500]
                }
                test "bad + a" {
                    test "bad + a success" {
                        # puts [$master crdt.datainfo zset6510]
                        $master zscore zset6510 a
                    } {10}
                    test "bad + a fail" {
                        # puts [$peer crdt.datainfo zset6511]
                        $master zscore zset6511 a
                    } {4}
                }
                test "bad + b" {
                    test "bad + b success" {
                        $master zscore zset6520 a
                    } {10}
                    test "bad + b fail" {
                        $master zscore zset6521 a
                    } {4}
                }
                test "bad + ad" {
                    test "bad + ad success" {
                        $master zscore zset6530 a
                    } {9}
                    test "bad + ad a fail" {
                        $master zscore zset6531 a
                    } {6}
                    test "bad + ad d fail" {
                        $master zscore zset6532 a
                    } {10}
                    test "bad + ad ad fail" {
                        $master zscore zset6533 a
                    } {7}
                }
                test "bad + ba" {
                    test "bad + ba success" {
                        $master zscore zset6540 a
                    } {9}
                    test "bad + ba b fail" {
                        $master zscore zset6541 a
                    } {8}
                    test "bad + ba a fail" {
                        $master zscore zset6542 a
                    } {7}
                    test "bad + ba ba fail" {
                        $master zscore zset6543 a
                    } {6}
                }
                test "bad + bad" {
                    test "bad + bad success" {
                        $master zscore zset6550 a
                    } {9}
                    test "bad + bad b fail" {
                        $master zscore zset6551 a
                    } {8}
                    test "bad + bad  a fail" {
                        $master zscore zset6552 a
                    } {7}
                    test "bad + bad  d fail" {
                        $master zscore zset6553 a
                    } {7}
                    test "bad + bad  ba fail" {
                        $master zscore zset6554 a
                    } {8}
                    test "bad + bad  bd fail" {
                        $master zscore zset6555 a
                    } {6}
                    test "bad + bad  ad fail" {
                        $master zscore zset6556 a
                    } {6}
                    test "bad + bad  bad fail" {
                        $master zscore zset6557 a
                    } {7}
                }
            }
        }
        
    }
}