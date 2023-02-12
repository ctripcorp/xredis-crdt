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
            $master crdt.set set_vcu vcu 1 1000 1:100000
            $peer peerof $master_gid $master_host $master_port
            wait_for_peer_sync $peer
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
