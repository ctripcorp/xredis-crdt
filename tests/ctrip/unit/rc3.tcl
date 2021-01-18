start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master crdt.debug_gc rc 0
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
            $peer crdt.debug_gc rc 0
            test "before" {
                test "b" {
                    test "b + null" {
                        $master crdt.rc rc7000 1 1000 1:1 3:3:1.0 -1 
                        $master crdt.del_rc rc7000 1 1000 1:2 
                        
                    }
                    test "b + ad" {
                        $master crdt.rc rc7010 1 1000 1:1 3:3:1.0 -1 
                        $master crdt.del_rc rc7010 1 1000 1:4 

                        $peer crdt.counter rc7010 1 1000 1:2 4 4:1.0 
                        $peer crdt.del_rc rc7010 1 1000 1:3  1:2:2:1.0 

    
                    }
                    test "b + bad" {
                        test "b + bad success" {
                            $master crdt.rc rc7020 1 1000 1:1 3:3:1.0 -1 
                            $master crdt.del_rc rc7020 1 1000 1:4   

                            $master crdt.rc rc7020 1 1000 1:1 3:3:1.0 -1 
                            $peer crdt.counter rc7020 1 1000 1:2 4 4:1.0 
                            $peer crdt.del_rc rc7020 1 1000 1:3  1:2:2:1.0 
                        }
                        test "b + bad fail" {
                            $master crdt.rc rc7021 1 1000 1:1 3:3:1.0 -1 
                            $master crdt.del_rc rc7021 1 1000 1:2   

                            $master crdt.rc rc7021 1 1000 1:1 3:3:1.0 -1 
                            $peer crdt.counter rc7021 1 1000 1:2 4 4:1.0 
                            $peer crdt.del_rc rc7021 1 1000 1:3  1:2:2:1.0
                        }
                        
                    }
                }
                test "ad" {
                    test "ad + null" {
                        
                        $master crdt.counter rc7100 1 1000 1:1 4 4:1.0 
                        $master crdt.del_rc rc7100 1 1000 1:2  1:2:2:1.0 
                    }
                    test "ad + b" {
                        $master crdt.counter rc7110 1 1000 1:2 4 4:1.0 
                        $master crdt.del_rc rc7110 1 1000 1:3  1:2:2:1.0 

                        $peer crdt.rc rc7110 1 1000 1:1 3:3:1.0 -1 
                        $peer crdt.del_rc rc7110 1 1000 1:4    
                        
                    }
                    test "ad + bad" {
                        test "ad + bad sucess" {
                            $master crdt.counter rc7120 1 1000 1:4 4 4:1.0 
                            $master crdt.del_rc rc7120 1 1000 1:5  1:4:2:1.0 

                            $peer crdt.rc rc7120 1 1000 1:1 3:3:1.0 -1 
                            $peer crdt.counter rc7120 1 1000 1:2 4 4:1.0
                            $peer crdt.del_rc rc7120 1 1000 1:3  1:2:2:1.0
                        }
                        test "ad + bad fail" {
                            $master crdt.counter rc7121 1 1000 1:2 4 4:1.0 
                            $master crdt.del_rc rc7121 1 1000 1:3  1:2:2:1.0 

                            $peer crdt.rc rc7121 1 1000 1:1 3:3:1.0 -1 
                            $peer crdt.counter rc7121 1 1000 1:4 4 4:1.0
                            $peer crdt.del_rc rc7121 1 1000 1:5  1:4:2:1.0
                            
                        }
                    }
                }
                test "bad" {
                    test "bad1 + null" {
                        $master crdt.rc rc7200 1 1000 1:1 3:3:1.0 -1 
                        $master crdt.counter rc7200 1 1000 1:2 4 4:1.0 
                        $master crdt.del_rc rc7200 1 1000 1:2  1:2:2:1.0
                    }
                    test "bad + b" {
                        test "bad + b success" {
                            $master crdt.rc rc7210 1 1000 1:5 3:3:1.0 -1 
                            $master crdt.counter rc7210 1 1000 1:2 4 4:1.0 
                            $master crdt.del_rc rc7210 1 1000 1:5  1:2:2:1.0

                            $peer crdt.rc rc7210 1 1000 1:1 3:3:1.0 -1 
                            $peer crdt.del_rc rc7210 1 1000 1:4   
                        }

                        test "bad + b fail" {
                            $master crdt.rc rc7211 1 1000 1:1 3:3:1.0 -1  
                            $master crdt.counter rc7211 1 1000 1:2 4 4:1.0 
                            $master crdt.del_rc rc7211 1 1000 1:2  1:2:2:1.0

                            $peer crdt.rc rc7211 1 1000 1:1 3:3:1.0 -1 
                            $peer crdt.del_rc rc7211 1 1000 1:4   
                        }
                        

                        
                    }
                    test "bad + ad" {
                        test "bad + ad success" {
                            $master crdt.rc rc7220 1 1000 1:1 3:3:1.0 -1 
                            $master crdt.counter rc7220 1 1000 1:7 4 4:1.0 
                            $master crdt.del_rc rc7220 1 1000 1:8  1:7:2:1.0

                            $master crdt.counter rc7220 1 1000 1:4 4 4:1.0 
                            $master crdt.del_rc rc7220 1 1000 1:5  1:4:2:1.0 
                        }   
                        test "bad + ad fail" {
                            $master crdt.rc rc7221 1 1000 1:1 3:3:1.0 -1 
                            $master crdt.counter rc7221 1 1000 1:2 4 4:1.0 
                            $master crdt.del_rc rc7221 1 1000 1:2  1:2:2:1.0

                            $master crdt.counter rc7221 1 1000 1:4 4 4:1.0 
                            $master crdt.del_rc rc7221 1 1000 1:5  1:4:2:1.0 
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
                        assert_equal [$master crdt.datainfo rc7000] [$peer crdt.datainfo rc7000]
                    }
                    test "b + ad" {
                        $peer crdt.rc rc7010 1 1000 1:2 3:3:1.0 -1 
                        $peer get rc7010 
                    } {}
                    test "b + bad" {
                        test "b + bad success" {
                            $peer crdt.rc rc7020 1 1000 1:4 3:3:1.0 -1  
                            $peer get rc7020 
                        } {}

                        test "b + bad fail" {
                            $peer crdt.rc rc7020 1 1000 1:3 3:3:1.0 -1 
                            $peer get rc7020 
                        } {}
                        
                    } 
                }
                test "ad" {
                    test "ad + null" {
                    assert_equal [$master crdt.datainfo rc7100] [$peer crdt.datainfo rc7100]
                    }
                    test "ad + b" {
                        $peer crdt.rc rc7110 1 1000 1:3 3:3:1.0 -1 
                        $peer get rc7110 
                        
                    } {}
                    test "ad + bad" {
                    test "ad + bad success" {
                        $peer crdt.rc rc7120 1 1000 1:2 3:3:1.0 -1 
                        $peer get rc7120 
                    } {}
                    test "ad + bad fail" {
                        $peer crdt.rc rc7121 1 1000 1:4 3:3:1.0 -1 
                        $peer get rc7121 
                    } {}
                    }
                }
                test "bad" {
                    test "bad1 + null" {
                        assert_equal [$master crdt.datainfo rc7200] [$peer crdt.datainfo rc7200]
                    }
                    test "bad + b" {
                        test "bad + b success" {
                            $peer crdt.rc rc7210 1 1000 1:5 3:3:1.0 -1 
                            $peer get rc7210 
                        } {}
                        test "bad + b fail" {
                            $peer crdt.rc rc7211 1 1000 1:4 3:3:1.0 -1 
                            $peer get rc7211 
                        } {}
                    }
                    test "bad + ad" {
                        test "bad + ad success" {
                            $peer crdt.rc rc7220 1 1000 1:8 3:3:1.0 -1  
                            $peer get rc7220 
                        } {}
                        test "bad + ad fail" {
                            $peer crdt.rc rc7221 1 1000 1:5 3:3:1.0 -1  
                            $peer get rc7221 
                        } {}
                    }
                }
            }

        }
    }
}