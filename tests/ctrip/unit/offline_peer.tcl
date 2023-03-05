

start_server {
    tags {"offline command"}
    overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
} {
    set config_file [srv 0 config_file] 
    test "add offline peer" {
        assert_equal [r crdt.setOfflineGid 2 3 4 5] "OK"
        assert_equal [r crdt.getOfflineGid] "2 3 4 5"

        assert_equal [r crdt.setOfflineGid] "OK"
        assert_equal [r crdt.getOfflineGid] ""
    }

    test "add offline rewrite config file" {
        # Execute under root user privileges, the configuration file is still writable
        exec chmod 400 $config_file
        assert_equal [r crdt.setOfflineGid 2 3 4 5] "OK,but save config fail"
        exec chmod 777 $config_file

        assert_equal [r crdt.setOfflineGid] "OK"
        assert_equal [r crdt.getOfflineGid] ""
    }

    test "add offline peer param error - gid is not int" {
        catch {r crdt.setOfflineGid a} retval
        assert_equal $retval "ERR value is not an integer or out of range"
        catch {r crdt.setOfflineGid 1 a} retval
        assert_equal $retval "ERR value is not an integer or out of range"
    }

    test "add offline peer param error - gid > 16" {
        catch {r crdt.setOfflineGid 100} retval
        assert_equal $retval "ERR peer gid invalid"
    }
}

start_server {
    tags {" sync offlinegid (master-> slave)"}
    overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    test "sync offlinegid - partial sync " {
        start_server {
            tags {"slave"}
            overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
        } {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]

            $slave slaveof $master_host $master_port
            wait_for_sync $slave 
            assert_equal [$slave crdt.getOfflineGid] ""
            
            #set
            assert_equal [$master crdt.setOfflineGid 2 3 4] "OK"
            wait_for_condition 100 50 {
                [$slave crdt.getOfflineGid] == "2 3 4"
            } else {
                assert_equal [$slave crdt.getOfflineGid] "2 3 4"
            }
        
            assert_equal [$master crdt.setOfflineGid] "OK"
            wait_for_condition 100 50 {
                [$slave crdt.getOfflineGid] == ""
            } else {
                assert_equal [$slave crdt.getOfflineGid] ""
            }
        }
    }

    test "sync offlinegid - full sync " {
        $master crdt.setOfflineGid 2 3 4 5
        start_server {
            tags {"slave"}
            overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
        } {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]

            $slave slaveof $master_host $master_port
            wait_for_sync $slave 

            assert_equal [$slave crdt.getOfflineGid] "2 3 4 5"

        }
    }
}



# 1<<2 + 1<<4 + 1<<5 == 52
start_server {
    tags {" config offlinegid "}
    overrides {crdt-gid 1 crdt-offline-gid 52} config {crdt.conf} module {crdt.so} 
} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_config_file [srv 0 config_file]
    set master_config [srv 0 config]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    test "load config offline gid" {
        assert_equal [$master crdt.getOfflineGid] "2 4 5"
    
        assert_equal [lindex [$master config crdt.get crdt-offline-gid] 1] 52
    }


    test "rewrite config" {
        $master crdt.setOfflineGid 2 3 4 5
        $master config rewrite
        # restart server
        shutdown_will_restart_redis $master 
        start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
            set master [redis $master_host $master_port]
            $master select 9
            after 2000
            assert_equal [$master crdt.getOfflineGid] "2 3 4 5"
            
        }
    }
}

proc parse_vc_str {vc_str} {
    set vc [dict create]
    set list1 [split $vc_str ";"]
    foreach iter1 $list1 {
        set list2 [split $iter1 ":"]
        dict append vc [lindex $list2 0] [lindex $list2 1]
    }
    return $vc 
}

test "parse_vc_str" {
    set vc [parse_vc_str "1:2;3:4;5:6"]
    assert_equal [dict get $vc 1] 2
    assert_equal [dict exist $vc 2] 0
}

start_server {
    tags {"gc"}
    overrides {crdt-gid 1 } config {crdt.conf} module {crdt.so} 
} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master config crdt.set repl-ping-slave-period 1
    start_server {
        tags {"slave"}
        overrides {crdt-gid 1 } config {crdt.conf} module {crdt.so} 
    } {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        $slave config crdt.set repl-ping-slave-period 1
        start_server {
            tags {"peer2"}
            overrides {crdt-gid 2 } config {crdt.conf} module {crdt.so} 
        } {
            set peer2 [srv 0 client]
            set peer2_host [srv 0 host]
            set peer2_port [srv 0 port]
            set peer2_log [srv 0 stdout]
            $peer2 config crdt.set repl-ping-slave-period 1
            start_server {
                tags {"peer3"}
                overrides {crdt-gid 3 } config {crdt.conf} module {crdt.so} 
            } {
                set peer3 [srv 0 client]
                set peer3_host [srv 0 host]
                set peer3_port [srv 0 port]
                $peer3 config crdt.set repl-ping-slave-period 1
                test "offline gid (gc), build servers" {
                    $slave slaveof $master_host $master_port 
                    
                    $master peerof 2 $peer2_host $peer2_port
                    $master peerof 3 $peer3_host $peer3_port 

                    $peer2 peerof 1 $master_host $master_port 
                    $peer2 peerof 3 $peer3_host $peer3_port 

                    $peer3 peerof 1 $master_host $master_port 
                    $peer3 peerof 2 $peer2_host $peer2_port 

                    wait_for_sync $slave 
                    wait_for_peers_sync 0 $master 
                    wait_for_peers_sync 1 $master 
                    wait_for_peers_sync 0 $peer2 
                    wait_for_peers_sync 1 $peer2 
                    wait_for_peers_sync 0 $peer3 
                    wait_for_peers_sync 1 $peer3 

                }

                test "offline gid (gc), step 2 write data" {
                    
                    $peer2 set k v1
                    $peer3 set k v2 
                    $master set k v3

                    $peer3 set peer3_string peer3 
                    $master set master_string master 
                    $peer2  set peer2_string peer2 
                    
                    wait_for_condition 100 50 {
                        [$master get k ] == "v3"
                    } else {
                        assert_equal [$master get k ] "v3"
                    }
                    wait_for_condition 100 50 {
                        [$slave get k ] == "v3"
                    } else {
                        assert_equal [$slave get k ] "v3"
                    }
                    wait_for_condition 100 50 {
                        [$peer2 get k ] == "v3"
                    } else {
                        assert_equal [$peer2 get k ] "v3"
                    }
                    wait_for_condition 100 50 {
                        [$peer3 get k ] == "v3"
                    } else {
                        assert_equal [$peer3 get k ] "v3"
                    }
                }
                set ts 1
                test "offline gid (gc), step 3 (peer3) slaveof 127.0.0.1 0" {
                    
                    wait_for_condition 100 50 {
                        [$master  dbsize] == 4
                    } else {
                        fail "master sync data fail"
                    }

                    wait_for_condition 100 50 {
                        [$slave  dbsize] == 4
                    } else {
                        fail "slave sync data fail"
                    }

                    wait_for_condition 100 50 {
                        [$peer2  dbsize] == 4
                    } else {
                        fail "peer2 sync data fail"
                    }

                    wait_for_condition 100 50 {
                        [$peer3  dbsize] == 4
                    } else {
                        fail "peer3 sync data fail"
                    }
                    # assert_equal [$master dbsize ] [$peer3 dbsize]
                    # assert_equal [$slave dbsize ] [$peer3 dbsize]
                    # assert_equal [$peer2 dbsize ] [$peer3 dbsize]

                    $peer3 slaveof 127.0.0.1 0
                    # puts [$peer3 crdt.info replication] 
                    # puts [$master crdt.info replication]
                    # puts [$peer2 crdt.info replication]
                    $master set add_key1 v
                    set add_key1_vc_str [lindex [$master crdt.get add_key1] 3]
                    set add_key1_vc [parse_vc_str $add_key1_vc_str]
                    assert_equal [dict exist $add_key1_vc 3] 1                   

                    $master del k 
                    after 2000
                    assert_equal [$master tombstonesize ] $ts
                    assert_equal [$slave tombstonesize ] $ts
                    assert_equal [$peer2 tombstonesize ] $ts
                }

                test "offline gid (gc), step 4 (master/peer2) peerof 3" {
                    $master peerof 3 no one
                    $peer2 peerof 3 no one 
                    
                    assert_equal [$master tombstonesize ] $ts
                    assert_equal [$slave tombstonesize ] $ts
                    assert_equal [$peer2 tombstonesize ] $ts
                }

                test "offline gid (gc), step 5 (master/peer2) crdt.setOfflineGid 3" {
                    $master crdt.setOfflineGid 3 
                    set before_gc_hits [crdt_stats $peer2 stat_gc_hits]
                    set before_gc_misses [crdt_stats $peer2 stat_gc_misses]
                    $peer2 crdt.setOfflineGid 3
                    
                    wait_for_condition 100 50 {
                        [$master tombstonesize ] == 0
                    } else {
                        fail "master gc fail"
                    }
                    wait_for_condition 100 50 {
                        [$slave tombstonesize ] == 0
                    } else {
                        fail "slave gc fail"
                    }
                    wait_for_condition 100 50 {
                        [$peer2 tombstonesize ] == 0
                    } else {    
                        set fp [open $peer2_log r]
                        set content [read $fp]
                        close $fp
                        set fp [open $master_stdout r]
                        set content1 [read $fp]
                        close $fp
                        fail [format "peer gc fail:  dbsize (%s)(%s) before(%s,%s) now(%s,%s)\n ====== info\n%s\n  =====peer2 crdt.info replication\n%s\n ====== peer2 log\n%s\n ====== master crdt.info replication \n%s\n ====== master log \n%s\n " [$peer2 dbsize] [$master dbsize] $before_gc_hits $before_gc_misses  [crdt_stats $peer2 stat_gc_hits] [crdt_stats $peer2 stat_gc_misses] [$peer2 info] [$peer2 crdt.info replication] $content [$master crdt.info replication] $content1]
                    }
                }

                test "offline gid (gc), step 6 master/peer2 add new key  vc not exist gid(3)" {
                    $master set add_key2 v 
                    set add_key2_vc_str [lindex [$master crdt.get add_key2] 3]
                    set add_key2_vc [parse_vc_str $add_key2_vc_str]
                    assert_equal [dict exist $add_key2_vc 3] 0
                    wait_for_condition 100 50 {
                        [$peer2 get add_key2] == "v" 
                    } else {
                        assert_equal [$peer2 get add_key2] "v"
                    }
                    set add_key2_vc_str [lindex [$peer2 crdt.get add_key2] 3]
                    set add_key2_vc [parse_vc_str $add_key2_vc_str]
                    assert_equal [dict exist $add_key2_vc 3] 0
                }

                test "offline gid (gc), step 7 peer2 del new key  can gc" {
                    $peer2 del add_key2
                    wait_for_condition 100 50 {
                        [$peer2 tombstoneSize] == 0
                    } else {
                        fail "peer gc fail"
                    }
                    wait_for_condition 100 50 {
                        [$master get add_key2] == ""
                    } else {
                        fail "master sync del command fail"
                    }
                    wait_for_condition 100 50 {
                        [$master tombstoneSize] == 0
                    } else {
                        fail "master gc fail"
                    }
                }

                test "offline gid (gc) check ovc contains ovcc " {
                    proc check_ovc_and_ovcc {r} {
                        set ovc [parse_vc_str [crdt_status $r ovc]]
                        set ovc_cache [parse_vc_str [crdt_status $r ovcc]]
                        foreach gid [dict keys $ovc_cache] {
                            assert_equal [dict get $ovc $gid] [dict get $ovc_cache $gid]
                        }
                    }
                    check_ovc_and_ovcc $master
                    check_ovc_and_ovcc $slave
                    check_ovc_and_ovcc $peer2
                }

                test "peer new gid3 server (vcu = 0)  peerof fail" {
                    start_server {
                        tags {"npeer3"}
                        overrides {crdt-gid 3 } config {crdt.conf} module {crdt.so} 
                    } {
                        set npeer3 [srv 0 client]
                        set npeer3_host [srv 0 host]
                        set npeer3_port [srv 0 port]
                        $master peerof 3 $npeer3_host $npeer3_port
                        for {set j 0} {$j < 100} {incr j} {
                            assert_equal [crdt_status $master "peer1_link_status"]  "down"
                            after 50
                        }
                        assert_log_file $master_stdout "*-ERR CRDT.SYNC and CRDT.PSYNC Slave vectorClock*"
                    }
                }

            }
        }
    }
}