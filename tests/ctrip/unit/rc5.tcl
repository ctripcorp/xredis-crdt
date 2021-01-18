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
        $master crdt.debug_gc rc 0
        $peer crdt.debug_gc rc 0
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1

        $master peerof $peer_gid $peer_host $peer_port
        $peer peerof $master_gid $master_host $master_port

        wait_for_peer_sync $master
        wait_for_peer_sync $peer
        test "before" {

       
            test "value" {
                test "b" {
                    test "b + b" {
                        test "b(int) + b(int)" {
                            $master set rc1000 1
                            $peer set rc1000 2
                        }
                        test "b(int) + b(string)" {
                            $master set rc1001 1
                            $peer set rc1001 2
                            $peer set rc1001 b
                        }
                        test "b(string) + b(int)" {
                            $master set rc1002 1
                            $master set rc1002 a
                            $peer set rc1002 2
                        }
                        test "b(string) + b(string)" {
                            $master set rc1003 1
                            $peer set rc1003 1
                            $master set rc1003 a
                            $peer set rc1003 b
                        }
                        
                    }
                    test "b + a" {
                        test "b + a(int)" {
                            test "b(int) + a(int)" {
                                $master set rc1010 1
                                $peer incr rc1010
                            }
                            test "b(string) + a(int)" {
                                
                                $master set rc1011 1
                                $peer incr rc1011
                                $master set rc1011 a

                                
                            }
                        }
                        test "b + a(float)" {
                            test "b(int) + a(float)" {
                                $master set rc1012 1
                                $peer incrbyfloat rc1012 1
                            }
                            test "b(string) + a(float)" {
                                $master set rc1013 1
                                $peer incrbyfloat rc1013 1
                                $master set rc1013 a
                                
                            }
                        }
                    }
                    test "b + ba" {
                        test "b + ba(int + int)" {
                            test "b(int) + ba(int + int) " {
                                $master set rc1020 1
                                $peer set rc1020 2
                                $peer incr rc1020 
                            }
                            test "b(string) + ba(int + int) " {
                                $master set rc1021 1
                                $master set rc1021 a
                                $peer set rc1021 2
                                $peer incr rc1021 
                            }
                        }
                        test "b + ba(int + float)" {
                            test "b(int) + ba(int + float) " {
                                $master set rc1022 1
                                $peer set rc1022 2
                                $peer incrbyfloat rc1022 2.0
                            }
                            test "b(string) + ba(int + float) " {
                                $master set rc1023 1
                                $master set rc1023 a
                                $peer set rc1023 2
                                $peer incrbyfloat rc1023 2.0
                            }
                        }
                        
                    }
                    test "b + bad" {
                        test "b + bad(int + int)" {
                            test "b(int) + bad(int + int) " {
                                $master set rc1030 1
                                $peer incrby rc1030 2
                                $peer set rc1030 2
                            }
                            test "b(string) + bad(int + int) " {
                                $master set rc1031 1
                                $peer incrby rc1031 2
                                $master set rc1031 a
                                $peer set rc1031 2                           
                            }
                        }
                        test "b + bad(int + float)" {
                            test "b(int) + bad(int + float) " {
                                $master set rc1032 1
                                $peer incrbyfloat rc1032 2.0
                                $peer set rc1032 2
                            }
                            test "b(string) + bad(int + float) " {
                                $master set rc1033 1
                                $peer incrbyfloat rc1033 2.0
                                $master set rc1033 a
                                
                                $peer set rc1033 2                           
                            }
                        }
                        test "b + bad(string + int)" {
                            test "b(int) + bad(string + int) " {
                                $master set rc1034 1
                                $peer incrby rc1034 2
                                $peer set rc1034 b
                            }
                            test "b(string) + bad(string + int) " {
                                $master set rc1035 1
                                $peer incrby rc1035 2
                                $master set rc1035 a
                                
                                $peer set rc1035 b                           
                            }
                        }
                        test "b + bad(string + float)" {
                            test "b(int) + bad(string + float) " {
                                $master set rc1036 1
                                $peer incrbyfloat rc1036 2
                                $peer set rc1036 b
                            }
                            test "b(string) + bad(string + float) " {
                                $master set rc1037 1
                                $peer incrbyfloat rc1037 2
                                $master set rc1037 a
                                
                                $peer set rc1037 b                           
                            }
                        }
                    }
                    test "b + tb" {
                        test "b(int) + tb(int) " {
                            test "b(int) + tb(int)" {
                                $master set rc1040 1
                                $peer set rc1040 2
                                $peer del rc1040
                            }
                            test "b(string) + tb(int)" {
                                $master set rc1041 1
                                $master set rc1041 a
                                $peer set rc1041 2
                                $peer del rc1041
                            }
                        }
                        test "b + tb(string) " {
                            test "b(int) + tb(string)" {
                                $master set rc1042 1
                                $peer set rc1042 2
                                $peer set rc1042 b
                                $peer del rc1042
                            }
                            test "b(string) + tb(string)" {
                                $master set rc1043 1
                                $master set rc1043 a
                                $peer set rc1043 2
                                $peer set rc1043 b
                                $peer del rc1043
                            }                           
                        }
                    }
                    test "b + tbad" {
                        test "b + tbad(int + int) " {
                            test "b(int) + tbad( int)" {
                                $master set rc1044 1
                                $peer set rc1044 2
                                $peer incrby rc1044 2
                                $peer del rc1044
                            }
                            test "b(string) + tbad( int)" {
                                $master set rc1045 1
                                $master set rc1045 a
                                $peer set rc1045 2
                                $peer incrby rc1045 2
                                $peer del rc1045
                            }
                        }
                        test "b + tbad(int + float) " {
                            test "b(int) + tbad(float)" {
                                $master set rc1046 1
                                $peer set rc1046 2
                                $peer incrbyfloat rc1045 2.0
                                $peer del rc1046
                            }
                            test "b(string) + tbad(float)" {
                                $master set rc1047 1
                                $master set rc1047 a
                                $peer set rc1047 2
                                $peer incrbyfloat rc1047 2.0
                                $peer del rc1047
                            }
                        }
                        
                    }
                }
                test "a" {
                    test "a + a" {
                        test "a(int) + a(int)" {
                            $master incrby rc1100 1
                            $peer incrby rc1100 2
                        }
                        test "a(int) + a(float)" {
                            $master incrby rc1101 1
                            $peer incrbyfloat rc1101 2.0
                        }
                        test "a(float) + a(float)" {
                            $master incrbyfloat rc1102 1.0
                            $peer incrbyfloat rc1102 2.0
                        }
                    }
                    test "a + ba" {
                        test "a + ba(int + int)" {
                            test "a(int) + ba(int + int)" {
                                $master incrby rc1110 1
                                $peer set rc1110 1
                                $peer incrby rc1110 1
                            }
                            test "a(float) + ba(int + int)" {
                                $master incrbyfloat rc1111 1.0
                                $peer set rc1111 1
                                $peer incrby rc1111 1
                            }
                        }
                        test "a + ba(int + float)" {
                            test "a(int) + ba(int + float)" {
                                $master incrby rc1112 1
                                $peer set rc1112 1
                                $peer incrbyfloat rc1112 1
                            }
                            test "a(float) + ba(int + float)" {
                                $master incrbyfloat rc1113 1.0
                                $peer set rc1113 1
                                $peer incrbyfloat rc1113 1
                            }
                        }
                        test "a + ba(float + float)" {
                            test "a(int) + ba(float + float)" {
                                $master incrby rc1114 1
                                $peer set rc1114 1.1
                                $peer incrbyfloat rc1114 1
                            }
                            test "a(float) + ba(float + float)" {
                                $master incrbyfloat rc1115 1.0
                                $peer set rc1115 1.1
                                $peer incrbyfloat rc1115 1
                            }
                        }
                    }
                    test "a + bad" {
                        test "a + bad(int + int)" {
                            test "a(int) + bad(int + int)" {
                                $master incrby rc1116 1
                                $peer incrby rc1116 1
                                $peer set rc1116 1
                                
                            }
                            test "a(float) + bad(int + int)" {
                                $master incrbyfloat rc1117 1.0
                                $peer incrby rc1117 1
                                $peer set rc1117 1
                            }
                        }
                        test "a + bad(int + float)" {
                            test "a(int) + bad(int + float)" {
                                $master incrby rc1118 1
                                $peer incrbyfloat rc1118 1
                                $peer set rc1118 1
                                
                            }
                            test "a(float) + bad(int + float)" {
                                $master incrbyfloat rc1119 1.0
                                $peer incrbyfloat rc1119 1
                                $peer set rc1119 1
                            }
                        }
                        test "a + bad(float + int)" {
                            test "a(int) + bad(float + int)" {
                                $master incrby rc1120 1
                                $peer incrby rc1120 1
                                $peer set rc1120 1.1
                                
                            }
                            test "a(float) + bad(float + int)" {
                                $master incrbyfloat rc1121 1.0
                                $peer incrby rc1121 1
                                $peer set rc1121 1.1
                            }
                        }
                        test "a + bad(float + float)" {
                            test "a(int) + bad(float + float)" {
                                $master incrby rc1122 1
                                $peer incrbyfloat rc1122 1
                                $peer set rc1122 1.1
                                
                            }
                            test "a(float) + bad(float + float)" {
                                $master incrbyfloat rc1123 1.0
                                $peer incrbyfloat rc1123 1
                                $peer set rc1123 1.1
                            }
                        }
                    }
                    test "a + tb" {
                        test "a(int) + tb" {
                            $master incrby rc1130 1
                            $peer set rc1130 1
                            $peer del rc1130 
                            
                        }
                        test "a(float) + tb" {
                            $master incrbyfloat rc1131 1.0
                            $peer set rc1131 1
                            $peer del rc1131 
                        }
                    }
                    test "a + tbad" {
                        test "a + bad(int)" {
                            test "a(int) + bad(int)" {
                                $master incrby rc1140 1
                                $peer incrby rc1140 1
                                $peer del rc1140 
                                
                            }
                            test "a(float) + bad(int)" {
                                $master incrbyfloat rc1141 1.0
                                $peer incrby rc1141 1
                                $peer del rc1141 
                            }
                        }
                        test "a + bad(float)" {
                            test "a(int) + bad(float)" {
                                $master incrby rc1142 1
                                $peer incrbyfloat rc1142 1
                                $peer del rc1142 
                                
                            }
                            test "a(float) + bad(float)" {
                                $master incrbyfloat rc1143 1.0
                                $peer incrbyfloat rc1143 1
                                $peer del rc1143 
                            }
                        }
                        
                    }
                }
                test "ba" {
                    
                    test "ba + ba" {
                        test "ba + ba(int + int)" {
                            test "ba(int + int) + ba(int + int)" {
                                $master set rc1200 1
                                $master incrby rc1200 1
                                $peer set rc1200 2
                                $peer incrby rc1200 2
                            }
                            test "ba(int + float) + ba(int + int)" {
                                $master set rc1201 1
                                $master incrbyfloat rc1201 1
                                $peer set rc1201 2
                                $peer incrby rc1201 2
                            }
                            test " ba(float + float) + ba(int + int)" {
                                $master set rc1202 1.1
                                $master incrbyfloat rc1202 1
                                $peer set rc1202 2
                                $peer incrby rc1202 2
                            }
                        }   
                        test "ba + ba(int + float)" {
                            test "ba(int + float) + ba(int + float)" {
                                $master set rc1203 1
                                $master incrbyfloat rc1203 1
                                $peer set rc1203 2
                                $peer incrbyfloat rc1203 2
                            }
                            test " ba(float + float) + ba(int + float)" {
                                $master set rc1204 1.1
                                $master incrbyfloat rc1204 1
                                $peer set rc1204 2
                                $peer incrbyfloat rc1204 2
                            }
                        }
                        test "ba + ba(float + float)" {
                            test " ba(float + float) + ba(float + float)" {
                                $master set rc1205 1.1
                                $master incrbyfloat rc1205 1
                                $peer set rc1205 2.0
                                $peer incrbyfloat rc1205 2
                            }
                        }
                    }
                    test "ba + bad" {
                        test "ba + bad(int + int)" {
                            test "ba(int + int) + bad(int + int)" {
                                $master set rc1210 1
                                $master incrby rc1210 1
                                $peer incrby rc1210 2
                                $peer set rc1210 2
                            }
                            test "ba(int + float) + bad(int + int)" {
                                $master set rc1211 1
                                $master incrbyfloat rc1211 1
                                $peer incrby rc1211 2
                                $peer set rc1211 2
                                
                            }
                            test " ba(float + float) + bad(int + int)" {
                                $peer incrby rc1212 2
                                $master set rc1212 1.1
                                $master incrbyfloat rc1212 1
                                
                                $peer set rc1212 2
                                
                            }
                        }
                        test "ba + bad(string + int)" {
                            test "ba(int + int) + bad(string + int)" {
                                $master set rc1213 1
                                $master incrby rc1213 1
                                $peer incrby rc1213 2
                                $peer set rc1213 b
                            }
                            test "ba(int + float) + bad(string + int)" {
                                $master set rc1214 1
                                $master incrbyfloat rc1214 1
                                $peer incrby rc1214 2
                                $peer set rc1214 b
                                
                            }
                            test " ba(float + float) + bad(string + int)" {
                                $peer incrby rc1215 2
                                $master set rc1215 1.1
                                $master incrbyfloat rc1215 1
                                
                                $peer set rc1215 b
                                
                            }
                        }
                        test "ba + bad(int + float)" {
                            test "ba(int + int) + bad(int + float)" {
                                $master set rc1216 1
                                $master incrby rc1216 1
                                $peer incrbyfloat rc1216 2
                                $peer set rc1216 2
                            }
                            test "ba(int + float) + bad(int + float)" {
                                $master set rc1217 1
                                $master incrbyfloat rc1217 1
                                $peer incrbyfloat rc1217 2
                                $peer set rc1217 2
                                
                            }
                            test " ba(float + float) + bad(int + float)" {
                                $master set rc1218 1.1
                                $master incrbyfloat rc1218 1
                                $peer incrbyfloat rc1218 2
                                $peer set rc1218 2
                                
                            }
                        }
                        test "ba + bad(string + float)" {
                            test "ba(int + int) + bad(string + float)" {
                                $master set rc1219 1
                                $master incrby rc1219 1
                                $peer incrbyfloat rc1219 2
                                $peer set rc1219 b
                            }
                            test "ba(int + float) + bad(string + float)" {
                                $master set rc1220 1
                                $master incrbyfloat rc1220 1
                                $peer incrbyfloat rc1220 2
                                $peer set rc1220 b
                                
                            }
                            test " ba(float + float) + bad(string + float)" {
                                $master set rc1221 1.1
                                $master incrbyfloat rc1221 1
                                $peer incrbyfloat rc1221 2
                                $peer set rc1221 b
                                
                            }
                        }
                    }
                    test "ba + tb" {
                        test "ba(int + int) + tb" {
                            $master set rc1230 1
                            $master incrby rc1230 1
                            $peer set rc1230 2
                            $peer del rc1230 
                        }
                        test "ba(int + float) + tb" {
                            $master set rc1231 1
                            $master incrbyfloat rc1231 1
                            $peer set rc1231 2
                            $peer del rc1231 
                        }
                        test "ba(float + float) + tb" {
                            $master set rc1232 1.1
                            $master incrbyfloat rc1232 1
                            $peer set rc1232 2
                            $peer del rc1232 
                        }
                    }
                    test "ba + tbad" {
                        test "ba + tbad(int)" {
                            test "ba(int + int) + tbad(int)" {
                                $master set rc1240 1
                                $master incrby rc1240 1
                                $peer incrby rc1240 2
                                $peer del rc1240 
                            }
                            test "ba(int + float) + tbad(int)" {
                                $master set rc1241 1
                                $master incrbyfloat rc1241 1
                                $peer incrby rc1241 2
                                $peer del rc1241 
                            }
                            test "ba(float + float) + tbad(int)" {
                                $peer incrby rc1242 2
                                $master set rc1242 1.1
                                $master incrbyfloat rc1242 1
                                
                                $peer del rc1242 
                            }
                        }
                        test "ba + tbad(float)" {
                            test "ba(int + int) + tbad(float)" {
                                $master set rc1250 1
                                $master incrby rc1250 1
                                $peer incrbyfloat rc1250 2
                                $peer del rc1250 
                            }
                            test "ba(int + float) + tbad(float)" {
                                $master set rc1251 1
                                $master incrbyfloat rc1251 1
                                $peer incrbyfloat rc1251 2
                                $peer del rc1251 
                            }
                            test "ba(float + float) + tbad(float)" {
                                $master set rc1252 1.1
                                $master incrbyfloat rc1252 1
                                $peer incrbyfloat rc1252 2
                                $peer del rc1252 
                            }
                            
                        }
                    }
                }
                test "bad" {
                    
                    test "bad + bad" {
                        test "bad + bad(int + int)" {
                            test "bad(int + int) + bad(int + int)" {
                                $master incrby rc1300 1
                                $master set rc1300 1
                                $peer incrby rc1300 1
                                $peer set rc1300 1
                            }
                            test "bad(string + int) + bad(int + int)" {
                                $master incrby rc1301 1
                                $peer incrby rc1301 1
                                $master set rc1301 a
                                
                                $peer set rc1301 1
                            }
                            test "bad(int + float) + bad(int + int)" {
                                $master incrbyfloat rc1302 1
                                $master set rc1302 1
                                $peer incrby rc1302 1
                                $peer set rc1302 1
                            }
                            test "bad(string + float) + bad(int + int)" {
                                $master incrbyfloat rc1303 1
                                $peer incrby rc1303 1
                                $master set rc1303 a
                                
                                $peer set rc1303 1
                            }
                        }
                        test "bad + bad(string + int)" {
                            test "bad(string + int) + bad(string + int)" {
                                $master incrby rc1310 1
                                $peer incrby rc1310 1
                                $master set rc1310 a
                                
                                $peer set rc1310 b
                            }
                            test "bad(int + float) + bad(string + int)" {
                                $master incrbyfloat rc1311 1
                                $master set rc1311 1
                                $peer incrby rc1311 1
                                $peer set rc1311 b
                            }
                            test "bad(string + float) + bad(string + int)" {
                                $peer incrby rc1312 1
                                $master incrbyfloat rc1312 1
                                $master set rc1312 a
                               
                                $peer set rc1312 b
                            }
                        }
                        test "bad + bad(int + float)" {
                            test "bad(int + float) + bad(int + float)" {
                                $master incrbyfloat rc1320 1
                                $master set rc1320 1
                                $peer incrbyfloat rc1320 1
                                $peer set rc1320 1
                            }
                            test "bad(string + float) + bad(int + float)" {
                                $master incrbyfloat rc1321 1
                                $peer incrbyfloat rc1321 1
                                $master set rc1321 a
                                
                                $peer set rc1321 1
                            }
                        }
                        test "bad + bad(string + float)" {
                            test "bad(string + float) + bad(string + float)" {
                                $peer incrbyfloat rc1322 1
                                $master incrbyfloat rc1322 1
                                $master set rc1322 a
                                $peer set rc1322 b
                            }
                        }
                    }
                    test "bad + tb" {
                        test "bad(string + int) + tb" {
                            $master incrby rc1330 1
                            $master set rc1330 a
                            $peer set rc1330 1
                            $peer del rc1330 
                        }
                        test "bad(int + float) + tb" {
                            $master incrbyfloat rc1331 1
                            $master set rc1331 1
                            $peer set rc1331 1
                            $peer del rc1331 
                        }
                        test "bad(string + float) + tb" {
                            $master incrbyfloat rc1332 1
                            $master set rc1332 a
                            $peer set rc1332 1
                            $peer del rc1332 
                        }
                    }
                    test "bad + tbad" {
                        test "bad + tbad(int)" {
                            test "bad(string + int) + tbad(int)" {
                                $master incrby rc1340 1
                                $peer incrby rc1340 1
                                $master set rc1340 a
                                $peer del rc1340 
                            }
                            test "bad(int + float) + tbad(int)" {
                                $master incrbyfloat rc1341 1
                                $master set rc1341 1
                                $peer incrby rc1341 1
                                $peer del rc1341 
                            }
                            test "bad(string + float) + tbad(int)" {
                                $master incrbyfloat rc1342 1
                                $peer incrby rc1342 1
                                $master set rc1342 a
                                
                                $peer del rc1342 
                            }
                        }
                        test "bad + tbad(float)" {
                            test "bad(string + int) + tbad(float)" {
                                $master incrby rc1350 1
                                $peer incrbyfloat rc1350 1
                                $master set rc1350 a
                                $peer del rc1350 
                            }
                            test "bad(int + float) + tbad(float)" {
                                $master incrbyfloat rc1351 1
                                $master set rc1351 1
                                $peer incrbyfloat rc1351 1
                                $peer del rc1351 
                            }
                            test "bad(string + float) + tbad(float)" {
                                $master incrbyfloat rc1352 1
                                $peer incrbyfloat rc1352 1
                                $master set rc1352 a
                                $peer del rc1352 
                            }
                        }
                    }
                }
            }
            test "tombstone" {
                test "tb" {
                    
                    test "tb + tb" {
                        $master set rc1400 1
                        $master del rc1400
                        $peer set rc1400 2
                        $peer del rc1400
                    }
                    test "tb + tbad" {
                        test "tb + tbad(int)" {
                            $master set rc1401 1
                            $master del rc1401
                            $peer incrby rc1401 2
                            $peer del rc1401
                        }
                        test "tb + tbad(float)" {
                            $master set rc1402 1
                            $master del rc1402
                            $peer incrbyfloat rc1402 2
                            $peer del rc1402
                        }
                    }
                }
                test "tbad" {
                    
                    test "tbad + tbad" {
                        test "tbad(int) + tbad(int)" {
                            $master incrby rc1500 1
                            $master del rc1500
                            $peer incrby rc1500 2
                            $peer del rc1500
                        }
                        test "tbad(int) + tbad(float)" {
                            $master incrby rc1501 1
                            $master del rc1501
                            $peer incrbyfloat rc1501 2
                            $peer del rc1501
                        }
                        test "tbad(float) + tbad(float)" {
                            $master incrbyfloat rc1502 1
                            $master del rc1502
                            $peer incrbyfloat rc1502 2
                            $peer del rc1502
                        }
                        
                    }
                }
            }
        }
        after 3000
        test "after" {
            test "value" {
                test "b" {
                    test "b + b" {
                        test "b(int) + b(int)" {
                            assert_equal [$master get rc1000 ] [$peer get rc1000 ]
                        }
                        test "b(int) + b(string)" {
                            assert_equal [$master get rc1001 ] [$peer get rc1001 ]
                        }
                        test "b(string) + b(int)" {
                            assert_equal [$master get rc1002 ] [$peer get rc1002 ]
                        }
                        test "b(string) + b(string)" {
                            assert_equal [$master get rc1003 ] [$peer get rc1003 ]
                        }
                        
                    }
                    test "b + a" {
                        test "b + a(int)" {
                            test "b(int) + a(int)" {
                                assert_equal [$master get rc1010 ] [$peer get rc1010 ]
                            }
                            test "b(string) + a(int)" {
                                assert_equal [$master get rc1011 ] [$peer get rc1011 ]
                            }
                        }
                        test "b + a(float)" {
                            test "b(int) + a(float)" {
                                assert_equal [$master get rc1012 ] [$peer get rc1012 ]
                            }
                            test "b(string) + a(float)" {
                                assert_equal [$master get rc1013 ] [$peer get rc1013 ]
                            }
                        }
                    }
                    test "b + ba" {
                        test "b + ba(int + int)" {
                            test "b(int) + ba(int + int) " {
                                assert_equal [$master get rc1020 ] [$peer get rc1020 ]
                            }
                            test "b(string) + ba(int + int) " {
                                assert_equal [$master get rc1021 ] [$peer get rc1021 ]
                            }
                        }
                        test "b + ba(int + float)" {
                            test "b(int) + ba(int + float) " {
                                assert_equal [$master get rc1022 ] [$peer get rc1022 ]
                            }
                            test "b(string) + ba(int + float) " {
                                assert_equal [$master get rc1023 ] [$peer get rc1023 ]
                            }
                        }
                        
                    }
                    test "b + bad" {
                        test "b + bad(int + int)" {
                            test "b(int) + bad(int + int) " {
                                assert_equal [$master get rc1030 ] [$peer get rc1030 ]
                            }
                            test "b(string) + bad(int + int) " {
                                assert_equal [$master get rc1031 ] [$peer get rc1031 ]                        
                            }
                        }
                        test "b + bad(int + float)" {
                            test "b(int) + bad(int + float) " {
                                assert_equal [$master get rc1032 ] [$peer get rc1032 ] 
                            }
                            test "b(string) + bad(int + float) " {
                                assert_equal [$master get rc1033 ] [$peer get rc1033 ]                           
                            }
                        }
                        test "b + bad(string + int)" {
                            test "b(int) + bad(string + int) " {
                                assert_equal [$master get rc1034 ] [$peer get rc1034 ]    
                            }
                            test "b(string) + bad(string + int) " {
                                assert_equal [$master get rc1035 ] [$peer get rc1035 ]                           
                            }
                        }
                        test "b + bad(string + float)" {
                            test "b(int) + bad(string + float) " {
                                assert_equal [$master get rc1036 ] [$peer get rc1036 ]  
                            }
                            test "b(string) + bad(string + float) " {
                                assert_equal [$master get rc1037 ] [$peer get rc1037 ]                          
                            }
                        }
                    }
                    test "b + tb" {
                        test "b(int) + tb(int) " {
                            test "b(int) + tb(int)" {
                                assert_equal [$master get rc1040 ] [$peer get rc1040 ]  
                            }
                            test "b(string) + tb(int)" {
                                assert_equal [$master get rc1041 ] [$peer get rc1041 ]
                            }
                        }
                        test "b + tb(string) " {
                            test "b(int) + tb(string)" {
                                assert_equal [$master get rc1042 ] [$peer get rc1042 ]
                            }
                            test "b(string) + tb(string)" {
                                assert_equal [$master get rc1043 ] [$peer get rc1043 ]
                            }                           
                        }
                    }
                    test "b + tbad" {
                        test "b + tbad(int + int) " {
                            test "b(int) + tbad( int)" {
                                assert_equal [$master get rc1044 ] [$peer get rc1044 ]
                            }
                            test "b(string) + tbad( int)" {
                                assert_equal [$master get rc1045 ] [$peer get rc1045 ]
                            }
                        }
                        test "b + tbad(int + float) " {
                            test "b(int) + tbad(float)" {
                                assert_equal [$master get rc1046 ] [$peer get rc1046 ]
                            }
                            test "b(string) + tbad(float)" {
                                assert_equal [$master get rc1047 ] [$peer get rc1047 ]
                            }
                        }
                        
                    }
                }
                test "a" {
                    test "a + a" {
                        test "a(int) + a(int)" {
                            assert_equal [$master get rc1100 ] [$peer get rc1100 ]
                        }
                        test "a(int) + a(float)" {
                            assert_equal [$master get rc1101 ] [$peer get rc1101 ]
                        }
                        test "a(float) + a(float)" {
                            assert_equal [$master get rc1102 ] [$peer get rc1102 ]
                        }
                    }
                    test "a + ba" {
                        test "a + ba(int + int)" {
                            test "a(int) + ba(int + int)" {
                                assert_equal [$master get rc1110 ] [$peer get rc1110 ]
                            }
                            test "a(float) + ba(int + int)" {
                                assert_equal [$master get rc1111 ] [$peer get rc1111 ]
                            }
                        }
                        test "a + ba(int + float)" {
                            test "a(int) + ba(int + float)" {
                                assert_equal [$master get rc1112 ] [$peer get rc1112 ]
                            }
                            test "a(float) + ba(int + float)" {
                                assert_equal [$master get rc1113 ] [$peer get rc1113 ]
                            }
                        }
                        test "a + ba(float + float)" {
                            test "a(int) + ba(float + float)" {
                                assert_equal [$master get rc1114 ] [$peer get rc1114 ]
                            }
                            test "a(float) + ba(float + float)" {
                                assert_equal [$master get rc1115 ] [$peer get rc1115 ]
                            }
                        }
                    }
                    test "a + bad" {
                        test "a + bad(int + int)" {
                            test "a(int) + bad(int + int)" {
                                assert_equal [$master get rc1116 ] [$peer get rc1116 ]
                            }
                            test "a(float) + bad(int + int)" {
                                assert_equal [$master get rc1117 ] [$peer get rc1117 ]
                            }
                        }
                        test "a + bad(int + float)" {
                            test "a(int) + bad(int + float)" {
                                assert_equal [$master get rc1118 ] [$peer get rc1118 ] 
                            }
                            test "a(float) + bad(int + float)" {
                                assert_equal [$master get rc1119 ] [$peer get rc1119 ] 
                                
                            }
                        }
                        test "a + bad(float + int)" {
                            test "a(int) + bad(float + int)" {
                                assert_equal [$master get rc1120 ] [$peer get rc1120 ] 
                                
                            }
                            test "a(float) + bad(float + int)" {
                                assert_equal [$master get rc1121 ] [$peer get rc1121 ] 
                            }
                        }
                        test "a + bad(float + float)" {
                            test "a(int) + bad(float + float)" {
                                assert_equal [$master get rc1122 ] [$peer get rc1122 ] 
                                
                            }
                            test "a(float) + bad(float + float)" {
                                 assert_equal [$master get rc1123 ] [$peer get rc1123 ] 
                            }
                        }
                    }
                    test "a + tb" {
                        test "a(int) + tb" {
                            assert_equal [$master get rc1130 ] [$peer get rc1130 ]
                            
                        }
                        test "a(float) + tb" {
                            assert_equal [$master get rc1131 ] [$peer get rc1131 ]
                        }
                    }
                    test "a + tbad" {
                        test "a + bad(int)" {
                            test "a(int) + bad(int)" {
                                assert_equal [$master get rc1140 ] [$peer get rc1140 ]
                                
                            }
                            test "a(float) + bad(int)" {
                                assert_equal [$master get rc1141 ] [$peer get rc1141 ]
                            }
                        }
                        test "a + bad(float)" {
                            test "a(int) + bad(float)" {
                                assert_equal [$master get rc1142 ] [$peer get rc1142 ]
                                
                            }
                            test "a(float) + bad(float)" {
                                assert_equal [$master get rc1143 ] [$peer get rc1143 ] 
                            }
                        }
                        
                    }
                }
                test "ba" {
                    
                    test "ba + ba" {
                        test "ba + ba(int + int)" {
                            test "ba(int + int) + ba(int + int)" {
                                assert_equal [$master get rc1200 ] [$peer get rc1200 ] 
                            }
                            test "ba(int + float) + ba(int + int)" {
                                assert_equal [$master get rc1201 ] [$peer get rc1201 ] 
                            }
                            test " ba(float + float) + ba(int + int)" {
                                assert_equal [$master get rc1202 ] [$peer get rc1202 ] 
                            }
                        }   
                        test "ba + ba(int + float)" {
                            test "ba(int + float) + ba(int + float)" {
                                assert_equal [$master get rc1203 ] [$peer get rc1203 ] 
                            }
                            test " ba(float + float) + ba(int + float)" {
                                assert_equal [$master get rc1204 ] [$peer get rc1204 ] 
                            }
                        }
                        test "ba + ba(float + float)" {
                            test " ba(float + float) + ba(float + float)" {
                                assert_equal [$master get rc1205 ] [$peer get rc1205 ] 
                            }
                        }
                    }
                    test "ba + bad" {
                        test "ba + bad(int + int)" {
                            test "ba(int + int) + bad(int + int)" {
                                assert_equal [$master get rc1210 ] [$peer get rc1210 ] 
                            }
                            test "ba(int + float) + bad(int + int)" {
                                assert_equal [$master get rc1211 ] [$peer get rc1211 ]
                                
                            }
                            test " ba(float + float) + bad(int + int)" {
                                assert_equal [$master get rc1212 ] [$peer get rc1212 ]
                                
                            }
                        }
                        test "ba + bad(string + int)" {
                            test "ba(int + int) + bad(string + int)" {
                                assert_equal [$master get rc1213 ] [$peer get rc1213 ]
                            }
                            test "ba(int + float) + bad(string + int)" {
                                assert_equal [$master get rc1214 ] [$peer get rc1214 ]
                                
                            }
                            test " ba(float + float) + bad(string + int)" {
                                assert_equal [$master get rc1215 ] [$peer get rc1215 ]
                                
                            }
                        }
                        test "ba + bad(int + float)" {
                            test "ba(int + int) + bad(int + float)" {
                                assert_equal [$master get rc1216 ] [$peer get rc1216 ]
                            }
                            test "ba(int + float) + bad(int + float)" {
                                assert_equal [$master get rc1217 ] [$peer get rc1217 ]
                                
                            }
                            test " ba(float + float) + bad(int + float)" {
                                assert_equal [$master get rc1218 ] [$peer get rc1218 ]
                                
                            }
                        }
                        test "ba + bad(string + float)" {
                            test "ba(int + int) + bad(string + float)" {
                                assert_equal [$master get rc1219 ] [$peer get rc1219 ]
                            }
                            test "ba(int + float) + bad(string + float)" {
                                assert_equal [$master get rc1220 ] [$peer get rc1220 ]
                                
                            }
                            test " ba(float + float) + bad(string + float)" {
                                assert_equal [$master get rc1221 ] [$peer get rc1221 ]
                                
                            }
                        }
                    }
                    test "ba + tb" {
                        test "ba(int + int) + tb" {
                            assert_equal [$master get rc1230 ] [$peer get rc1230 ]
                        }
                        test "ba(int + float) + tb" {
                            assert_equal [$master get rc1231 ] [$peer get rc1231 ]
                        }
                        test "ba(float + float) + tb" {
                            assert_equal [$master get rc1232 ] [$peer get rc1232 ]
                        }
                    }
                    test "ba + tbad" {
                        test "ba + tbad(int)" {
                            test "ba(int + int) + tbad(int)" {
                                assert_equal [$master get rc1240 ] [$peer get rc1240 ]
                            }
                            test "ba(int + float) + tbad(int)" {
                                assert_equal [$master get rc1241 ] [$peer get rc1241 ]
                            }
                            test "ba(float + float) + tbad(int)" {
                                 assert_equal [$master get rc1242 ] [$peer get rc1242 ]
                            }
                        }
                        test "ba + tbad(float)" {
                            test "ba(int + int) + tbad(float)" {
                                assert_equal [$master get rc1250 ] [$peer get rc1250 ] 
                            }
                            test "ba(int + float) + tbad(float)" {
                                assert_equal [$master get rc1251 ] [$peer get rc1251 ] 
                            }
                            test "ba(float + float) + tbad(float)" {
                                assert_equal [$master get rc1252 ] [$peer get rc1252 ] 
                            }
                            
                        }
                    }
                }
                test "bad" {
                    
                    test "bad + bad" {
                        test "bad + bad(int + int)" {
                            test "bad(int + int) + bad(int + int)" {
                                assert_equal [$master get rc1300 ] [$peer get rc1300 ] 
                            }
                            test "bad(string + int) + bad(int + int)" {
                                assert_equal [$master get rc1301 ] [$peer get rc1301 ] 
                            }
                            test "bad(int + float) + bad(int + int)" {
                                assert_equal [$master get rc1302 ] [$peer get rc1302 ] 
                            }
                            test "bad(string + float) + bad(int + int)" {
                                assert_equal [$master get rc1303 ] [$peer get rc1303 ] 
                            }
                        }
                        test "bad + bad(string + int)" {
                            test "bad(string + int) + bad(string + int)" {
                                assert_equal [$master get rc1310 ] [$peer get rc1310 ] 
                            }
                            test "bad(int + float) + bad(string + int)" {
                                assert_equal [$master get rc1311 ] [$peer get rc1311 ]
                            }
                            test "bad(string + float) + bad(string + int)" {
                                assert_equal [$master get rc1312 ] [$peer get rc1312 ]
                            }
                        }
                        test "bad + bad(int + float)" {
                            test "bad(int + float) + bad(int + float)" {
                                assert_equal [$master get rc1320 ] [$peer get rc1320 ]
                            }
                            test "bad(string + float) + bad(int + float)" {
                                 assert_equal [$master get rc1321 ] [$peer get rc1321 ]
                            }
                        }
                        test "bad + bad(string + float)" {
                            test "bad(string + float) + bad(string + float)" {
                                assert_equal [$master get rc1322 ] [$peer get rc1322 ]
                            }
                        }
                    }
                    test "bad + tb" {
                        test "bad(string + int) + tb" {
                            assert_equal [$master get rc1330 ] [$peer get rc1330 ]
                        }
                        test "bad(int + float) + tb" {
                            assert_equal [$master get rc1331 ] [$peer get rc1331 ]
                        }
                        test "bad(string + float) + tb" {
                            assert_equal [$master get rc1332 ] [$peer get rc1332 ]
                        }
                    }
                    test "bad + tbad" {
                        test "bad + tbad(int)" {
                            test "bad(string + int) + tbad(int)" {
                                assert_equal [$master get rc1340 ] [$peer get rc1340 ]
                            }
                            test "bad(int + float) + tbad(int)" {
                                assert_equal [$master get rc1341 ] [$peer get rc1341 ]
                            }
                            test "bad(string + float) + tbad(int)" {
                                assert_equal [$master get rc1342 ] [$peer get rc1342 ]
                            }
                        }
                        test "bad + tbad(float)" {
                            test "bad(string + int) + tbad(float)" {
   
                                assert_equal [$master get rc1350 ] [$peer get rc1350]
                            }
                            test "bad(int + float) + tbad(float)" {
                       
                                assert_equal [$master get rc1351 ] [$peer get rc1351 ] 
                            }
                            test "bad(string + float) + tbad(float)" {
                    
                                assert_equal [$master get rc1352 ] [$peer get rc1352 ] 
                            }
                        }
                    }
                }
            }
            test "tombstone" {
                test "tb" {
                    
                    test "tb + tb" {
                        assert_equal [$master get rc1400 ] [$peer get rc1400 ]
                    }
                    test "tb + tbad" {
                        test "tb + tbad(int)" {
                            assert_equal [$master get rc1401 ] [$peer get rc1401 ]
                        }
                        test "tb + tbad(float)" {
                           assert_equal [$master get rc1402 ] [$peer get rc1402 ]
                        }
                    }
                }
                test "tbad" {
                    
                    test "tbad + tbad" {
                        test "tbad(int) + tbad(int)" {
                            assert_equal [$master get rc1500 ] [$peer get rc1500 ]
                        }
                        test "tbad(int) + tbad(float)" {
                            assert_equal [$master get rc1501 ] [$peer get rc1501 ]
                        }
                        test "tbad(float) + tbad(float)" {
                            assert_equal [$master get rc1502 ] [$peer get rc1502 ]
                        }
                        
                    }
                }
            }
        }
    }
}