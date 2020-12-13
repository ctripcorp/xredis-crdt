start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master crdt.debug_gc zset 0
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
            $peer crdt.debug_gc zset 0
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
                    test "bad1 + null" {
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
            # wait_for_peer_sync $peer
            after 5000
            print_log_file $peer_log
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
                    test "bad1 + null" {
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