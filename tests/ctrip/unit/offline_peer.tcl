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
    
        assert_equal [lindex [$master config get crdt-offline-gid] 1] 52
    }

    
    test "rewrite config" {
        $master crdt.setOfflineGid 2 3 4 5
        $master config rewrite
        # restart server
        catch {$master shutdown} error 
        start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
            set master [redis $master_host $master_port]
            $master select 9
            after 2000
            assert_equal [$master crdt.getOfflineGid] "2 3 4 5"
            
        }
    }
}

start_server {
    tags {"gc"}
    overrides {crdt-gid 1 } config {crdt.conf} module {crdt.so} 
} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
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
                    $master set master_string master 
                    $peer2  set peer2_string peer2 
                    $peer3 set peer3_string peer3 

                    $master set k v1
                    $peer2 set k v2 
                    $peer3 set k v3 
                    
                    wait_for_condition 100 50 {
                        [$master get k ] == "v3"
                    } else {
                        assert_equal [$master get k ] "v3"
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
                    $peer3 slaveof 127.0.0.1 0
                    # puts [$peer3 crdt.info replication] 
                    # puts [$master crdt.info replication]
                    # puts [$peer2 crdt.info replication]
                    $master del master_string 
                    after 2000
                    assert_equal [$master tombstonesize ] $ts
                    assert_equal [$slave tombstonesize ] $ts
                    assert_equal [$peer2 tombstonesize ] $ts
                }

                test "offline gid (gc), step 3 (master/peer2) peerof 3" {
                    $master peerof 3 no one
                    $peer2 peerof 3 no one 
                    
                    assert_equal [$master tombstonesize ] $ts
                    assert_equal [$slave tombstonesize ] $ts
                    assert_equal [$peer2 tombstonesize ] $ts
                }

                test "offline gid (gc), step 3 (master/peer2) crdt.setOfflineGid 3" {
                    $master crdt.setOfflineGid 3 
                    $peer2 crdt.setOfflineGid 3
                    wait_for_condition 100 50 {
                        [$master tombstonesize ] == 0
                    } else {
                        assert_equal [$master tombstonesize ] 0
                    }
                    wait_for_condition 100 50 {
                        [$slave tombstonesize ] == 0
                    } else {
                        assert_equal [$slave tombstonesize ] 0
                    }
                    wait_for_condition 100 50 {
                        [$peer2 tombstonesize ] == 0
                    } else {
                        assert_equal [$peer2 tombstonesize ] 0
                    }
                }

                

            }
        }
    }
}