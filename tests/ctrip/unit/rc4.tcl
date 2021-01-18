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
                test "value + tomstone" {
                    test "a" {
                        test "a + tb " {
                            $master crdt.counter rc8000 1 1000 1:2 4 4:1.0 
                            $peer crdt.rc rc8000 1 1000 1:3 3:3:1.0 -1
                            $peer crdt.del_rc rc8000 1 1000 1:4  
                        }
                        test "a + tad" {
                            test "a + tad success" {
                                $master crdt.counter rc8010 1 1000 1:4 4 4:5.0 
                                $peer crdt.counter rc8010 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8010 1 1000 1:3  1:2:4:1.0 
                            }
                            test "a + tad fail" {
                                $master crdt.counter rc8011 1 1000 1:1 4 4:2.0 
                                $peer crdt.counter rc8011 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8011 1 1000 1:3  1:2:4:1.0 
                            }
                            
                        }
                        test "a + tbad" {
                            test "a + tbad success" {
                                # 4
                                $master crdt.counter rc8020 1 1000 1:4 4 4:5.0 
                                $peer crdt.rc rc8020 1 1000 1:1 3:3:4.0 -1
                                $peer crdt.counter rc8020 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8020 1 1000 1:3  1:2:4:1.0 
                            }
                            test "a + tbad fail" {
                                # {}
                                $master crdt.counter rc8021 1 1000 1:1 4 4:5.0 
                                $peer crdt.rc rc8021 1 1000 1:2 3:3:4.0 -1
                                $peer crdt.counter rc8021 1 1000 1:3 4 4:1.0 
                                $peer crdt.del_rc rc8021 1 1000 1:4  1:3:4:1.0 
                            }
                        }
                    }
                    test "b" {
                        test "b + tb " {
                            test "b + tb success" {
                                # 5
                                $master crdt.rc rc8100 1 1000 1:5 3:1:5 -1
                                $peer crdt.rc rc8100 1 1000 1:3 3:3:1.0 -1
                                $peer crdt.del_rc rc8100 1 1000 1:4  
                                
                                
                            } 
                            test "b + tb fail" {
                                # {}
                                $master crdt.rc rc8101 1 1000 1:1 3:3:3.0 -1
                                $peer crdt.rc rc8101 1 1000 1:3 3:3:1.0 -1
                                $peer crdt.del_rc rc8101 1 1000 1:4  
                                
                            }
                        }
                        test "b + ad" {
                            $master crdt.rc rc8110 1 1000 1:5 3:3:5.0 -1
                            $peer crdt.counter rc8110 1 1000 1:2 4 4:1.0 
                            $peer crdt.del_rc rc8110 1 1000 1:3  1:2:4:1.0 
                        }
                        test "b + bad" {
                            test "b + tbad success" {
                                $master crdt.rc rc8120 1 1000 1:5 3:3:7.0 -1
                                $peer crdt.rc rc8120 1 1000 1:1 3:3:4.0 -1
                                $peer crdt.counter rc8120 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8120 1 1000 1:3  1:2:4:1.0 
                            }
                            test "b + tbad fail" {
                                $master crdt.rc rc8121 1 1000 1:1 3:3:5.0 -1
                                $peer crdt.rc rc8121 1 1000 1:2 3:3:4.0 -1
                                $peer crdt.counter rc8121 1 1000 1:3 4 4:1.0 
                                $peer crdt.del_rc rc8121 1 1000 1:4  1:3:4:1.0 
                            }
                        }
                    }
                    test "ba" {
                        test "ba + tb " {
                            test "ba + tb success" {

                                # 6
                                $master crdt.rc rc8200 1 1000 1:5 3:3:5.0 -1
                                $master crdt.counter rc8200 1 1000 1:2 4 4:1.0 

                                $peer crdt.rc rc8200 1 1000 1:3 3:3:1.0 -1
                                $peer crdt.del_rc rc8200 1 1000 1:4  
                                
                                
                            } 
                            test "ba + tb fail" {
                                # 1
                                $master crdt.rc rc8201 1 1000 1:2 3:3:3.0 -1
                                $master crdt.counter rc8201 1 1000 1:2 4 4:1.0 
                                $peer crdt.rc rc8201 1 1000 1:3 3:3:1.0 -1
                                $peer crdt.del_rc rc8201 1 1000 1:4  
                                
                                
                            }
                        }
                        test "ba + tad" {
                            test "ba + tad success" {
                                # 6
                                $master crdt.rc rc8210 1 1000 1:5 3:3:5.0 -1
                                $master crdt.counter rc8210 1 1000 1:4 4 4:2.0 
                                $peer crdt.counter rc8210 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8210 1 1000 1:3  1:2:4:1.0 
                            }
                            test "ba + tad fail" {
                                # 7
                                $master crdt.rc rc8211 1 1000 1:5 3:3:7.0 -1
                                $master crdt.counter rc8211 1 1000 1:1 4 4:2.0 
                                $peer crdt.counter rc8211 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8211 1 1000 1:3  1:2:4:1.0 
                                
                            }
                            
                        }
                        test "ba + bad" {
                            test "ba + tbad success" {
                                # 8
                                $master crdt.rc rc8220 1 1000 1:5 3:3:7.0 -1
                                $master crdt.counter rc8220 1 1000 1:4 4 4:2.0 
                                $peer crdt.rc rc8220 1 1000 1:1 3:3:4.0 -1
                                $peer crdt.counter rc8220 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8220 1 1000 1:3  1:2:4:1.0 
                                
                            }
                            test "ba + tbad b fail" {
                                # 1
                                $master crdt.rc rc8221 1 1000 1:1 3:3:5.0 -1
                                $master crdt.counter rc8221 1 1000 1:4 4 4:2.0 
                                $peer crdt.rc rc8221 1 1000 1:2 3:3:4.0 -1
                                $peer crdt.counter rc8221 1 1000 1:3 4 4:1.0 
                                $peer crdt.del_rc rc8221 1 1000 1:4  1:3:4:1.0 
                                
                            }
                            test "ba + tbad a fail" {
                                # 5
                                $master crdt.rc rc8222 1 1000 1:5 3:3:5.0 -1
                                $master crdt.counter rc8222 1 1000 1:1 4 4:2.0 
                                $peer crdt.rc rc8222 1 1000 1:2 3:3:4.0 -1
                                $peer crdt.counter rc8222 1 1000 1:3 4 4:1.0 
                                $peer crdt.del_rc rc8222 1 1000 1:4  1:3:4:1.0 
                                
                            }
                            test "ba + tbad ba fail" {
                                #  {}
                                $master crdt.rc rc8223 1 1000 1:2 3:3:5.0 -1
                                $master crdt.counter rc8223 1 1000 1:1 4 4:2.0 
                                $peer crdt.rc rc8223 1 1000 1:3 3:3:4.0 -1
                                $peer crdt.counter rc8223 1 1000 1:4 4 4:1.0 
                                $peer crdt.del_rc rc8223 1 1000 1:5  1:4:4:1.0 
                                
                            }
                        }
                    }
                    test "ad" {
                        test "ad + tb " {
                            test "ad + tb success" {

                                # 3
                                $master crdt.counter rc8300 1 1000 1:7 4 4:5.0
                                $master crdt.del_rc rc8300 1 1000 1:6  1:6:4:2.0 

                                $peer crdt.rc rc8300 1 1000 1:3 3:3:1.0 -1
                                $peer crdt.del_rc rc8300 1 1000 1:4  
                                
                                
                            } 
                        }
                        test "ad + tad" {
                            test "ad + tad success" {
                                # 3
                                $master crdt.counter rc8310 1 1000 1:7 4 4:5.0
                                $master crdt.del_rc rc8310 1 1000 1:6  1:6:4:2.0 
                                $peer crdt.counter rc8310 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8310 1 1000 1:3  1:2:4:1.0 
                                
                            }
                            test "ad + tad ad fail" {
                                # {}
                                $master crdt.counter rc8311 1 1000 1:5 4 4:5.0
                                $master crdt.del_rc rc8311 1 1000 1:4  1:4:4:2.0 
                                $peer crdt.counter rc8311 1 1000 1:7 4 4:1.0 
                                $peer crdt.del_rc rc8311 1 1000 1:8  1:7:4:1.0 
    
                            }
                            test "ad + tad a success" {
                                # {}
                                $master crdt.counter rc8312 1 1000 1:10 4 4:5.0
                                $master crdt.del_rc rc8312 1 1000 1:4  1:4:4:2.0 
                                $peer crdt.counter rc8312 1 1000 1:7 4 4:1.0 
                                $peer crdt.del_rc rc8312 1 1000 1:8  1:7:4:1.0 
    
                            }
                            
                        }
                        test "ad + tbad" {
                            test "ad + tbad success" {
                                # 3
                                $master crdt.counter rc8320 1 1000 1:5 4 4:5.0
                                $master crdt.del_rc rc8320 1 1000 1:4  1:3:4:2.0 
                                $peer crdt.rc rc8320 1 1000 1:1 3:3:4.0 -1
                                $peer crdt.counter rc8320 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8320 1 1000 1:3  1:2:4:1.0 
                                
                                
                            }
                            test "ad + tbad ad fail" {
                                #  {}
                                $master crdt.counter rc8321 1 1000 1:2 4 4:5.0
                                $master crdt.del_rc rc8321 1 1000 1:1  1:1:4:2.0 
                                $peer crdt.rc rc8321 1 1000 1:3 3:3:4.0 -1
                                $peer crdt.counter rc8321 1 1000 1:4 4 4:1.0 
                                $peer crdt.del_rc rc8321 1 1000 1:5  1:4:4:1.0 
                                
                            }
                            test "ad + tbad a success" {
                                #  {}
                                $master crdt.counter rc8322 1 1000 1:10 4 4:5.0
                                $master crdt.del_rc rc8322 1 1000 1:1  1:1:4:2.0 
                                $peer crdt.rc rc8322 1 1000 1:3 3:3:4.0 -1
                                $peer crdt.counter rc8322 1 1000 1:4 4 4:1.0 
                                $peer crdt.del_rc rc8322 1 1000 1:5  1:4:4:1.0 
                                
                            }
                        }
                    }
                    test "bad" {
                        test "bad + tb" {
                            test "bad + tb success" {

                                # 4
                                $master crdt.rc rc8400 1 1000 1:8 3:3:1.0 -1
                                $master crdt.counter rc8400 1 1000 1:7 4 4:5.0
                                $master crdt.del_rc rc8400 1 1000 1:6  1:6:4:2.0 

                                $peer crdt.rc rc8400 1 1000 1:3 3:3:1.0 -1
                                $peer crdt.del_rc rc8400 1 1000 1:4  

                                
                                
                            }
                            test "bad + tb fail" {
                                # {}
                                $master crdt.rc rc8401 1 1000 1:5 3:3:3.0 -1
                                $master crdt.counter rc8401 1 1000 1:2 4 4:4.0
                                $master crdt.del_rc rc8401 1 1000 1:3  1:1:4:5.0 
                                
                                $peer crdt.rc rc8401 1 1000 1:6 3:3:1.0 -1
                                $peer crdt.del_rc rc8401 1 1000 1:7  
                                
                            }
                        }
                        test "bad + tad" {
                            test "bad + tad success" {

                                # 4
                                $master crdt.rc rc8410 1 1000 1:8 3:3:1.0 -1
                                $master crdt.counter rc8410 1 1000 1:7 4 4:5.0
                                $master crdt.del_rc rc8410 1 1000 1:6  1:6:4:2.0 

                                $peer crdt.counter rc8410 1 1000 1:2 4 4:1.0 
                                $peer crdt.del_rc rc8410 1 1000 1:3  1:2:4:1.0 
                                
                                
                            }
                            test "bad + tad fail" {
                                # 3
                                $master crdt.rc rc8411 1 1000 1:5 3:3:3.0 -1
                                $master crdt.counter rc8411 1 1000 1:2 4 4:4.0
                                $master crdt.del_rc rc8411 1 1000 1:3  1:1:4:5.0 
                                
                                $peer crdt.counter rc8411 1 1000 1:3 4 4:1.0 
                                $peer crdt.del_rc rc8411 1 1000 1:4  1:3:4:1.0 
                            }
                            test "bad + tad a success" {
                                # 3
                                $master crdt.rc rc8412 1 1000 1:5 3:3:3.0 -1
                                $master crdt.counter rc8412 1 1000 1:6 4 4:4.0
                                $master crdt.del_rc rc8412 1 1000 1:3  1:1:4:5.0 
                                
                                $peer crdt.counter rc8412 1 1000 1:3 4 4:1.0 
                                $peer crdt.del_rc rc8412 1 1000 1:4  1:3:4:1.0 
                            }

                        }
                        test "bad + tbad" {
                            test "bad + tad success" {

                                # 4
                                $master crdt.rc rc8420 1 1000 1:8 3:3:1.0 -1
                                $master crdt.counter rc8420 1 1000 1:7 4 4:5.0
                                $master crdt.del_rc rc8420 1 1000 1:6  1:6:4:2.0 

                                $peer crdt.rc rc8420 1 1000 1:3 3:3:4.0 -1
                                $peer crdt.counter rc8420 1 1000 1:4 4 4:1.0 
                                $peer crdt.del_rc rc8420 1 1000 1:5  1:4:4:1.0 
                                
                                
                            }
                            test "bad + tbad b fail" {
                                # 3
                                $master crdt.rc rc8421 1 1000 1:5 3:3:3.0 -1
                                $master crdt.counter rc8421 1 1000 1:8 4 4:4.0
                                $master crdt.del_rc rc8421 1 1000 1:4  1:1:4:5.0 
                                
                                $peer crdt.rc rc8421 1 1000 1:3 3:3:4.0 -1
                                $peer crdt.counter rc8421 1 1000 1:4 4 4:1.0 
                                $peer crdt.del_rc rc8421 1 1000 1:5  1:4:4:1.0 
                                
                                
                            }
                            test "bad + tbad ad fail" {
                                # 3
                                $master crdt.rc rc8422 1 1000 1:7 3:3:3.0 -1
                                $master crdt.counter rc8422 1 1000 1:2 4 4:4.0
                                $master crdt.del_rc rc8422 1 1000 1:3  1:1:4:5.0 
                                
                                $peer crdt.rc rc8422 1 1000 1:3 3:3:4.0 -1
                                $peer crdt.counter rc8422 1 1000 1:4 4 4:1.0 
                                $peer crdt.del_rc rc8422 1 1000 1:5  1:4:4:1.0 

                                
                                
                            }
                            test "bad + tbad bad fail" {
                                # 3
                                $master crdt.rc rc8423 1 1000 1:5 3:3:3.0 -1
                                $master crdt.counter rc8423 1 1000 1:2 4 4:4.0
                                $master crdt.del_rc rc8423 1 1000 1:3  1:1:4:5.0 
                                
                                $peer crdt.rc rc8423 1 1000 1:6 3:3:4.0 -1
                                $peer crdt.counter rc8423 1 1000 1:7 4 4:1.0 
                                $peer crdt.del_rc rc8423 1 1000 1:8  1:7:4:1.0 
                                
                                
                            }
                        }
                    }
                }

                test "tombstone + value" {
                    test "b" {
                        test "tb + a" {
                            $master crdt.rc rc9000 1 1000 1:3 3:3:1.0 -1
                            $master crdt.del_rc rc9000 1 1000 1:4  
                            $peer crdt.counter rc9000 1 1000 1:2 4 4:1.0 
                            
                        }
                        test "tb + b" {
                            test "tb + b success" {
                                $master crdt.rc rc9010 1 1000 1:3 3:3:1.0 -1
                                $master crdt.del_rc rc9010 1 1000 1:4  

                                $peer crdt.rc rc9010 1 1000 1:2 3:3:5.0 -1
                            } 
                            test "tb + b fail " {
                                $master crdt.rc rc9011 1 1000 1:3 3:3:1.0 -1
                                $master crdt.del_rc rc9011 1 1000 1:4  
                                $peer crdt.rc rc9011 1 1000 1:5 3:1:5 -1
                            } 
                            
                        }
                        test "tb + ad" {
                            $master crdt.rc rc9020 1 1000 1:3 3:3:1.0 -1
                            $master crdt.del_rc rc9020 1 1000 1:4  

                            $peer crdt.counter rc9020 1 1000 1:7 4 4:5.0
                            $peer crdt.del_rc rc9020 1 1000 1:6  1:6:4:2.0 
                            
                        }
                        test "tb + ba" {
                            test "tb + ba success" {
                                # 1
                                $master crdt.rc rc9030 1 1000 1:7 3:3:1.0 -1
                                $master crdt.del_rc rc9030 1 1000 1:8  

                                $peer crdt.rc rc9030 1 1000 1:5 3:3:5.0 -1
                                $peer crdt.counter rc9030 1 1000 1:2 4 4:1.0 
                                
                            }
                            test "tb + ba fail" {
                                $master crdt.rc rc9031 1 1000 1:3 3:3:1.0 -1
                                $master crdt.del_rc rc9031 1 1000 1:4  

                                $peer crdt.rc rc9031 1 1000 1:5 3:3:5.0 -1
                                $peer crdt.counter rc9031 1 1000 1:2 4 4:1.0 
                                
                            }
                        }
                        test "tb + bad" {
                            test "tb + bad success" {
                                $master crdt.rc rc9040 1 1000 1:10 3:3:1.0 -1
                                $master crdt.del_rc rc9040 1 1000 1:11  

                                $peer crdt.rc rc9040 1 1000 1:8 3:3:2.0 -1
                                $peer crdt.counter rc9040 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9040 1 1000 1:6  1:6:4:2.0 

                            }
                            test "tb + bad fail" {
                                $master crdt.rc rc9041 1 1000 1:1 3:3:1.0 -1
                                $master crdt.del_rc rc9041 1 1000 1:2  

                                $peer crdt.rc rc9041 1 1000 1:8 3:3:2.0 -1
                                $peer crdt.counter rc9041 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9041 1 1000 1:6  1:6:4:2.0 
                                
                            }
                            
                        }
                    }
                    test "tad" {
                        test "tad + a" {
                            test "tad + a success" {
                                $master crdt.counter rc9100 1 1000 1:5 4 4:1.0 
                                $master crdt.del_rc rc9100 1 1000 1:6  1:5:4:1.0 
                                $peer crdt.counter rc9100 1 1000 1:4 4 4:5.0 
                            }
                            test "tad + a fail" {
                                $master crdt.counter rc9101 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9101 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.counter rc9101 1 1000 1:4 4 4:5.0 
                            }
                        }
                        test "tad + b" {
                            
                            $master crdt.counter rc9110 1 1000 1:5 4 4:1.0 
                            $master crdt.del_rc rc9110 1 1000 1:6  1:5:2:1.0 

                            $peer crdt.rc rc9110 1 1000 1:4 3:3:5.0  -1
                            

                        }
                        test "tad + ad" {
                            test "tad + ad success" {
                                $peer crdt.counter rc9120 1 1000 1:3 4 4:5.0
                                $peer crdt.del_rc rc9120 1 1000 1:2  1:1:4:2.0 
                                $master crdt.counter rc9120 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9120 1 1000 1:7  1:6:4:1.0 

                            
                            }
                            test "tad + ad d success" {
                                # 4
                                $peer crdt.counter rc9121 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9121 1 1000 1:1  1:1:4:2.0 
                                $master crdt.counter rc9121 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9121 1 1000 1:3  1:2:4:1.0 
                                
                            }
                            test "tad + ad d fail" {
                                $peer crdt.counter rc9122 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9122 1 1000 1:6  1:6:4:2.0 
                                $master crdt.counter rc9122 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9122 1 1000 1:3  1:2:4:1.0 
                                
                            }
                            
                        }
                        test "tad + ba" {
                            
                            test "tad + ba success" {
                                $peer crdt.rc rc9130 1 1000 1:5 3:3:5.0 -1
                                $peer crdt.counter rc9130 1 1000 1:4 4 4:2.0 
                                $master crdt.counter rc9130 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9130 1 1000 1:7  1:6:4:1.0 
                            
                            }
                            test "tad + ba fail" {
                                $peer crdt.rc rc9131 1 1000 1:5 3:3:5.0 -1
                                $peer crdt.counter rc9131 1 1000 1:4 4 4:2.0 
                                $master crdt.counter rc9131 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9131 1 1000 1:3  1:2:4:1.0 
                                
                            }
                        }
                        test "tad + bad" {
                            test "tad + bad success" {
                                $master crdt.counter rc9140 1 1000 1:10 4 4:1.0 
                                $master crdt.del_rc rc9140 1 1000 1:11  1:10:4:1.0

                                $peer crdt.rc rc9140 1 1000 1:8 3:3:1.0 -1
                                $peer crdt.counter rc9140 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9140 1 1000 1:6  1:6:4:2.0 
                                
                            }
                            test "tad + bad d success" {
                                $master crdt.counter rc9141 1 1000 1:3 4 4:1.0 
                                $master crdt.del_rc rc9141 1 1000 1:4  1:3:4:1.0

                                $peer crdt.rc rc9141 1 1000 1:8 3:3:1.0 -1
                                $peer crdt.counter rc9141 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9141 1 1000 1:2  1:1:4:2.0 
                                
                            }
                            test "tad + bad fail" {
                                $master crdt.counter rc9142 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9142 1 1000 1:3  1:2:4:1.0

                                $peer crdt.rc rc9142 1 1000 1:8 3:3:1.0 -1
                                $peer crdt.counter rc9142 1 1000 1:7 4 4:5.0
                                $peer crdt.del_rc rc9142 1 1000 1:6  1:6:4:2.0 
                            
                            }
                            
                        }
                    }
                    test "tbad" {
                        test "tbad + a" {
                            test "tbad + a success" {
                                $master crdt.rc rc9200 1 1000 1:5 3:3:4.0 -1
                                $master crdt.counter rc9200 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9200 1 1000 1:7  1:6:4:1.0 
                                $peer crdt.counter rc9200 1 1000 1:4 4 4:5.0 
                                
                            } 
                            test "tbad + a fail" {
                                $master crdt.rc rc9201 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9201 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9201 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.counter rc9201 1 1000 1:4 4 4:5.0 
                                
                            }
                        }
                        test "tbad + b" {
                            test "tbad + b success" {
                                $master crdt.rc rc9210 1 1000 1:5 3:3:4.0 -1
                                $master crdt.counter rc9210 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9210 1 1000 1:7  1:6:4:1.0 
                                $peer crdt.rc rc9210 1 1000 1:4 3:3:5.0  -1
                                
                                
                            } 
                            test "tbad + b fail" {
                                $master crdt.rc rc9211 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9211 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9211 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.rc rc9211 1 1000 1:4 3:3:5.0  -1
                                
                            }
                        }
                        test "tbad + ad" {
                            test "tbad + ad success" {
                                $master crdt.rc rc9220 1 1000 1:5 3:3:4.0 -1
                                $master crdt.counter rc9220 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9220 1 1000 1:7  1:6:4:1.0 
                                $peer crdt.counter rc9220 1 1000 1:4 4 4:5.0 
                                $peer crdt.del_rc rc9220 1 1000 1:3  1:2:4:1.0 
                                
                            } 
                            test "tbad + ad d suceess" {
                                $master crdt.rc rc9221 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9221 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9221 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.counter rc9221 1 1000 1:4 4 4:5.0 
                                $peer crdt.del_rc rc9221 1 1000 1:2  1:1:4:1.0 
                                
                            }
                            test "tbad + ad fail" {
                                $master crdt.rc rc9222 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9222 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9222 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.counter rc9222 1 1000 1:5 4 4:5.0 
                                $peer crdt.del_rc rc9222 1 1000 1:4  1:3:4:2.0 
                                
                            }
                        }
                        test "tbad + ba" {
                            test "tbad + ba success" {
                                $master crdt.rc rc9230 1 1000 1:5 3:3:4.0 -1
                                $master crdt.counter rc9230 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9230 1 1000 1:7  1:6:4:1.0 
                                $peer crdt.rc rc9230 1 1000 1:4 3:3:5.0  -1
                                $peer crdt.counter rc9230 1 1000 1:3 4 4:1.0
                                
                            } 
                            test "tbad + ba b suceess" {
                                $master crdt.rc rc9231 1 1000 1:4 3:3:4.0 -1
                                $master crdt.counter rc9231 1 1000 1:4 4 4:1.0 
                                $master crdt.del_rc rc9231 1 1000 1:5  1:4:4:1.0 
                                $peer crdt.rc rc9231 1 1000 1:3 3:3:5.0  -1
                                $peer crdt.counter rc9231 1 1000 1:7 4 4:3.0 
                                
                            }
                            test "tbad + ba a suceess" {
                                $master crdt.rc rc9232 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9232 1 1000 1:7 4 4:2.0 
                                $master crdt.del_rc rc9232 1 1000 1:8  1:7:4:2.0 
                                $peer crdt.rc rc9232 1 1000 1:9 3:3:5.0  -1
                                $peer crdt.counter rc9232 1 1000 1:2 4 4:1.0
                                
                            }
                            test "tbad + ba fail" {
                                $master crdt.rc rc9233 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9233 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9233 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.rc rc9233 1 1000 1:5 3:3:5.0  -1
                                $peer crdt.counter rc9233 1 1000 1:4 4 4:3.0
                                
                            }
                        }
                        test "tbad + bad" {
                            test "tbad + bad success" {
                                $master crdt.rc rc9240 1 1000 1:5 3:3:4.0 -1
                                $master crdt.counter rc9240 1 1000 1:6 4 4:1.0 
                                $master crdt.del_rc rc9240 1 1000 1:7  1:6:4:1.0 
                                $peer crdt.rc rc9240 1 1000 1:4 3:3:5.0  -1
                                $peer crdt.counter rc9240 1 1000 1:3 4 4:3.0
                                $peer crdt.del_rc rc9240 1 1000 1:2  1:1:4:1.0 
                                
                            } 
                            test "tbad + bad b success" {
                                $master crdt.rc rc9241 1 1000 1:2 3:3:4.0 -1
                                $master crdt.counter rc9241 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9241 1 1000 1:7  1:2:4:1.0 
                                $peer crdt.rc rc9241 1 1000 1:1 3:3:5.0  -1
                                $peer crdt.counter rc9241 1 1000 1:9 4 4:3.0 
                                $peer crdt.del_rc rc9241 1 1000 1:8  1:7:4:2.0
                            }
                            test "tbad + bad ad success" {
                                $master crdt.rc rc9242 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9242 1 1000 1:3 4 4:2.0 
                                $master crdt.del_rc rc9242 1 1000 1:4  1:3:4:2.0 
                                $peer crdt.rc rc9242 1 1000 1:5 3:3:5.0  -1
                                $peer crdt.counter rc9242 1 1000 1:1 4 4:1.0
                                $peer crdt.del_rc rc9242 1 1000 1:2  1:1:4:1.0
                            }
                            test "tbad + bad  d success" {
                                $master crdt.rc rc9243 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9243 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9243 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.rc rc9243 1 1000 1:5 3:3:5.0  -1
                                $peer crdt.counter rc9243 1 1000 1:4 4 4:3.0
                                $peer crdt.del_rc rc9243 1 1000 1:1  1:1:4:1.0
                            }
                            test "tbad + bad  bd success" {
                                $master crdt.rc rc9244 1 1000 1:4 3:3:4.0 -1
                                $master crdt.counter rc9244 1 1000 1:5 4 4:1.0 
                                $master crdt.del_rc rc9244 1 1000 1:6  1:5:4:1.0 
                                $peer crdt.rc rc9244 1 1000 1:2 3:3:5.0  -1
                                $peer crdt.counter rc9244 1 1000 1:7 4 4:3.0
                                $peer crdt.del_rc rc9244 1 1000 1:1  1:1:4:1.0
                                
                            }
                            test "tbad + bad  bad fail" {
                                $master crdt.rc rc9245 1 1000 1:1 3:3:4.0 -1
                                $master crdt.counter rc9245 1 1000 1:2 4 4:1.0 
                                $master crdt.del_rc rc9245 1 1000 1:3  1:2:4:1.0 
                                $peer crdt.rc rc9245 1 1000 1:6 3:3:5.0  -1
                                $peer crdt.counter rc9245 1 1000 1:7 4 4:3.0
                                $peer crdt.del_rc rc9245 1 1000 1:5  1:5:4:1.0
                            }
                        }
                    }
                }
                
            }
            $peer peerof $master_gid $master_host $master_port
            # wait_for_peer_sync $peer
            after 5000
            print_log_file $peer_log
            test "after" {
                test "value + tomstone" {
                    test "a" {
                        test "a + tb " {
                            $peer  get rc8000 
                        } {1}
                        test "a + tad " {
                            test "a + tad success" {
                                $peer  get rc8010 
                            } {4}
                            test "a + tad fail" {
                                $peer  get rc8011 
                            } {}
                            
                        }
                        test "a + tbad" {
                            test "a + tbad success" {
                                $peer  get rc8020 
                            } {4}
                            test "a + tbad fail" {
                                $peer  get rc8021 
                            } {}
                        }
                    }
                    test "b" {
                        test "b + tb " {
                            test "b + tb success" {
                                
                                $peer  get rc8100 
                                
                            } {5}
                            test "b + tb fail" {
                                
                                $peer  get rc8101 
                            } {}
                        }
                        test "b + tad" {
                            test "b + tad success" {
                                $peer  get rc8110 
                            } {5}
                        }
                        test "b + tbad" {
                            test "b + tbad success" {
                                # puts [$peer crdt.datainfo rc8120]
                                $peer  get rc8120 
                            } {7}
                            test "b + tbad fail" {
                                $peer  get rc8121 
                            } {}
                        }
                    }
                    test "ba" {
                        test "ba + tb " {
                            test "ba + tb success" {
                                $peer  get rc8200 
                            } {6}
                            test "ba + tb fail" {
                                
                                $peer  get rc8201 
                            } {1}
                        }
                        test "ba + tad" {
                            test "ba + tad success" {
                                
                                $peer  get rc8210 
                            } {6}
                            test "ba + tad fail" {
                                $peer  get rc8211 
                            } {7}
                        }
                        test "ba + bad" {
                            test "ba + tbad success" {
                                # 8
                                $peer  get rc8220 
                            } {8}
                            test "ba + tbad b fail" {
                                # 1
                                $peer  get rc8221 
                            } {1}
                            test "ba + tbad a fail" {
                                # 5
                                $peer  get rc8222 
                            } {5}
                            test "ba + tbad ba fail" {
                                #  {}
                                $peer  get rc8223 
                            } {}
                        }
                        
                    }
                    test "ad" {
                        test "ad + tb " {
                            test "ad + tb success" {

                                # 3

                                
                                $peer  get rc8300 
                            } {3}
                        }
                        test "ad + tad" {
                            test "ad + tad success" {
                                # 7
                                $peer  get rc8310 
                            } {3}
                            test "ad + tad ad fail" {
                                # {}
                                $peer  get rc8311 
                                
                            } {}
                            test "ad + tad a success" {
                                $peer  get rc8312 
                            } {4}
                        }
                        test "ad + tbad" {
                            test "ad + tbad success" {
                                # 6
                                $peer  get rc8320 
                                
                            } {3}
                            test "ad + tbad ad fail" {
                                #  {}
                                $peer  get rc8321 
                                
                            } {}
                            test "ad + tbad a success" {
                                #  {}
                                $peer  get rc8322 
                                
                            } {4}
                        }
                    }
                    test "bad" {
                        test "bad + tb" {
                            test "bad + tb success" {
                                # 4
                                $peer  get rc8400 
                            } {4}
                            test "bad + tb fail" {
                                $peer  get rc8401 
                            } {-1}
                        }
                        test "bad + tad" {
                            test "bad + tad success" {
                                
                                $peer  get rc8410 
                                
                            } {4}
                            test "bad + tad fail" {
                                # 3
                                $peer  get rc8411 
                            } {3}
                            test "bad + tad a success" {
                                # 3
                                $peer  get rc8412 
                            } {6}
                        }
                        test "bad + tbad" {
                            test "bad + tad success" {
                                # 4
                                $peer  get rc8420      
                            } {4}
                            test "bad + tbad b fail" {
                                # 3
                                
                                $peer  get rc8421 
                                
                                
                                
                            } {3}
                            test "bad + tbad ad fail" {
                                # 3
                                $peer  get rc8422 
                            } {3}
                            test "bad + tbad bad fail" {
                                $peer  get rc8423 
                                
                                
                            } {}
                        }
                    }
                    
                }

                test "tombstone + value" {
                    test "b" {
                        test "tb + a" {
                            $peer  get rc9000 
                        } {1}
                        test "tb + b" {
                            test "tb + b success" {
                                $peer  get rc9010 
                            } {}
                            test "tb + b fail" {
                                $peer  get rc9011   
                            } {5}
                        }
                        test "tb + ad" {
                            $peer  get rc9020 
                        } {3}
                        test "tb + ba" {
                            test "tb + ba success" {
                                # puts [$peer crdt.datainfo rc9030]
                                $peer  get rc9030 
                            } {1}
                            test "tb + ba fail" {
                                $peer  get rc9031 
                            } {6}
                        }
                        test "tb + bad" {
                            test "tb + bad success" {
                                $peer  get rc9040 
                            } {3}
                            test "tb + bad fail" {
                                $peer  get rc9041 
                            } {5}
                        }
                    }
                    test "ad" {
                        test "tad + a" {
                            test "tad + a success" {
                                $peer  get rc9100 
                            } {}
                            test "tad + a fail" {
                                $peer  get rc9101 
                            } {4}
                        }
                        test "tad + b" {
                            $peer  get rc9110 
                        } {}
                        test "tad + ad" {
                            test "tad + ad success" {
                                $peer  get rc9120 
                            } {}
                            test "tad + ad  d success" {
                                $peer  get rc9121 
                            } {4}
                            test "tad + ad  d fail" {
                                $peer  get rc9122 
                            } {3}
                        } 
                        test "tad + ba" {
                            test "tad + ba success" {
                                $peer  get rc9130 
                            } {}
                            test "tad + ba fail" {
                                $peer  get rc9131 
                            } {6}
                            
                        }
                        test "tad + bad" {
                            test "tad + bad success" {
                                
                                $peer  get rc9140 
                            } {}
                            test "tad + bad d success" {
                                $peer  get rc9141 
                            } {5}
                            test "tad + bad fail" {
                                $peer  get rc9142 
                            } {4}
                        }
                    }
                    test "tbad" {
                        test "tbad + a" {
                            test "tbad + a success" {
                                $peer  get rc9200 
                            } {}
                            test "tbad + a fail" {
                                $peer  get rc9201 
                            } {4}
                        }
                        test "tbad + b" {
                            test "tbad + b success" {
                                $peer  get rc9210 
                            } {}
                            test "tbad + b fail" {
                                $peer  get rc9211 
                            } {5}
                        }
                        test "tbad + ad" {
                            test "tbad + ad success" {
                                $peer  get rc9220 
                            } {}
                            test "tbad + ad d suceess" {
                                $peer  get rc9221 
                            } {4}
                            test "tbad + ad fail" {
                                $peer  get rc9222 
                            } {3}
                        }
                        test "tbad + ba" {
                            test "tbad + ba success" {
                                $peer  get rc9230 
                            } {}
                            test "tbad + ba b suceess" {
                                $peer  get rc9231 
                            } {2}
                            test "tbad + ba a suceess" {
                                $peer  get rc9232 
                            } {5}
                            test "tbad + ba fail" {
                                $peer  get rc9233 
                            } {7}
                        }
                        test "tbad + bad" {
                            test "tbad + bad success" {
                                $peer  get rc9240 
                                
                            } {}
                            test "tbad + bad b suceess" {
                                $peer  get rc9241 
                                
                            } {1}
                            test "tbad + bad ad suceess" {
                                $peer  get rc9242 
                            } {5}
                            test "tbad + bad  d sucess" {
                                $peer  get rc9243 
                            }  {7}
                            test "tbad + bad  bd success" {
                                $peer  get rc9244 
                            } {2}
                            test "tbad + bad  bad fail" {
                                $peer  get rc9245 
                            } {7}
                        }
                    }
                }
            }

        }
    }
}
