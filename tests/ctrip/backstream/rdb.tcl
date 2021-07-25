proc build_env {code} {
    start_server {tags {"backstreaming, peer"} overrides {crdt-gid 2} config {crdt_no_save.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        $peer config crdt.set repl-diskless-sync-delay 1
        start_server {tags {"backstreaming, peer2"} overrides {crdt-gid 3} config {crdt_no_save.conf} module {crdt.so} } {
            set peer2 [srv 0 client]
            set peer2_gid 3
            set peer2_host [srv 0 host]
            set peer2_port [srv 0 port]
            set peer2_stdout [srv 0 stdout]
            set peer2_stderr [srv 0 stderr]
            $peer2 config crdt.set repl-diskless-sync-delay 1
            start_server {tags {"backstreaming, master"} overrides {crdt-gid 1} config {crdt_no_save.conf} module {crdt.so} } {
                set master [srv 0 client]
                set master_gid 1
                set master_host [srv 0 host]
                set master_port [srv 0 port]
                set master_stdout [srv 0 stdout]
                set master_stderr [srv 0 stderr]
                set master_config_file [srv 0 config_file]
                set master_config [srv 0 config]
                $master config crdt.set repl-diskless-sync-delay 1
                start_server {tags {"backstreaming, slave"} overrides {crdt-gid 1} config {crdt_no_save.conf} module {crdt.so} } {
                    set slave [srv 0 client]
                    set slave_gid 1
                    set slave_host [srv 0 host]
                    set slave_port [srv 0 port]
                    set slave_stdout [srv 0 stdout]
                    set slave_stderr [srv 0 stderr]
                    $slave config crdt.set repl-diskless-sync-delay 1
                    
                        # run before
                        $peer peerof $master_gid $master_host $master_port
                        $peer peerof $peer2_gid $peer2_host $peer2_port
                        $peer2 peerof $master_gid $master_host $master_port
                        $peer2 peerof $peer_gid $peer_host $peer_port
                        $master peerof $peer_gid $peer_host $peer_port
                        $master peerof $peer2_gid $peer2_host $peer2_port
                        wait_for_peers_sync 1 $peer 
                        wait_for_peers_sync 1 $peer2
                        wait_for_peers_sync 1 $master 

                    proc get_master_srv value {
                        return [srv -1 $value]
                    }
                    proc get_slave_srv value {
                        return [srv 0 $value]
                    }
                    proc get_peer_srv value {
                        return [srv -3 $value]
                    }

                    proc get_peer2_srv value {
                        return [srv -2 $value]
                    }

                    test "run" {
                         #run code
                        if {[catch [uplevel 0 $code ] result]} {
                            puts $result
                        }
                    }                    
                }
            }
        }
    }
}

proc wait_backstream {r} {
    while 1 {
        if {[crdt_status $r backstreaming] eq 1} {
            after 100
        } else {
            break;
        }
    }
}

test "master-rdb-backstream" {
    build_env {
        $master set k v 
        $slave slaveof $master_host $master_port
        $slave config rewrite
        wait_for_sync $slave 
        after 1000
        $master bgsave
        waitForBgsave $master 
        $master config rewrite
        $master set k1 v1
        after 500
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$master shutdown} error 
        after 1000
        assert_equal [get_master_srv port] $master_port
        start_server_by_config [get_master_srv config_file] [get_master_srv config] $master_host $master_port $master_stdout $master_stderr 1 {
            set master [redis $master_host $master_port]
            $master select 9
            
            wait_for_peers_sync 1 $master 
            wait_backstream $master 
            assert_equal [$master get k] [$peer get k]
            wait_for_sync $slave 
            assert_equal [$master get k] [$slave get k]

        }
    }
}

test "master-rdb-nobackstream" {
    build_env {
        $master set k v 
        after 1000
        $slave slaveof $master_host $master_port
        $slave config rewrite
        wait_for_sync $slave 
        $master set k1 v1
        assert_equal [$peer get k] [$master get k]
        after 1000
        $master bgsave
        waitForBgsave $master 
        $master config rewrite
        
        catch {$master shutdown} error 
        after 1000
        assert_equal [get_master_srv port] $master_port
        start_server_by_config [get_master_srv config_file] [get_master_srv config] $master_host $master_port $master_stdout $master_stderr 1 {
            set master [redis $master_host $master_port]
            $master select 9
            
            wait_for_peers_sync 1 $master 
            wait_backstream $master 
            assert_equal [$master get k] [$peer get k]
            wait_for_sync $slave 
            assert_equal [$master get k] [$slave get k]

        }
    }
}


test "slave-add-sync" {
    build_env {
        
        $slave slaveof $master_host $master_port
        $slave config rewrite
        wait_for_sync $slave 
        $master set k v 
        after 2000
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        after 1000
        assert_equal [get_slave_srv port] $slave_port
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            set slave [redis $slave_host $slave_port]
            $slave select 9
            wait_for_sync $slave 
            puts [$slave info replication]
            puts [$master info replication]
            assert_equal [$slave get k] [$master get k]
        }
    }
}


test "slave-full-sync" {
    build_env {
        $master set k v 
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        $slave config rewrite
        after 2000
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        after 1000
        assert_equal [get_slave_srv port] $slave_port
        $master set k2 v
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            set slave [redis $slave_host $slave_port]
            $slave select 9
            wait_for_sync $slave 
            
            assert_equal [$slave get k] [$master get k]
        }
    }
}



test "master + slave-add-sync-backstream" {
    build_env {
        
        $slave slaveof $master_host $master_port
        $slave config rewrite
        wait_for_sync $slave 
        $master set k v 
        after 2000
        $master bgsave 
        after 500
        waitForBgsave $master 
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        $master set k1 v1
        catch {$master shutdown} error
        after 1000
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
             start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                set slave [redis $slave_host $slave_port]
                set master [redis $master_host $master_port]
                $master select 9
                $slave select 9
                wait_for_sync $slave 
                assert_equal [$master get k] [$peer get k]
                assert_equal [$slave get k] [$master get k]
                assert_equal [$slave get k1] [$master get k1]
                assert_equal [$slave get k1] [$master get k1]
            }
        }
    }
}


test "master + slave-full-sync-backstream" {
    build_env {
        $master set k v 
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        $slave config rewrite
        after 2000
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        
        after 1000
        assert_equal [get_slave_srv port] $slave_port
        $master set k1 v1
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                set slave [redis $slave_host $slave_port]
                set master [redis $master_host $master_port]
                $master select 9
                $slave select 9
                wait_for_sync $slave 
                assert_equal [$master get k] [$peer get k]
                assert_equal [$slave get k] [$master get k]
                assert_equal [$slave get k1] [$master get k1]
                assert_equal [$slave get k1] [$master get k1]
            }
        }
    }
}

proc wait_clean_data {log} {
    set fp [open $log r]
    while {1} {
        set content [read $fp]
        if {[string match {*\[backstream\]\ clean data*} $content]} {
            break;
        }
    }
    close $fp
}

test "change-slave(add-sync)" {
    build_env {
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        $master set k v 
        $slave config rewrite
        after 2000
        $master bgsave
        waitForBgsave $master
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        assert_equal [get_slave_srv port] $slave_port
        $master set k1 v1
        after 20
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            set slave [redis $slave_host $slave_port]
            $slave select 9
            $slave slaveof no one 
            wait_for_peers_sync 1 $slave 
            assert_equal [$slave get k] [$peer get k]

            assert_equal [$slave get k1] [$peer get k1]
            start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                set master [redis $master_host $master_port]
                $master select 9
                wait_clean_data $master_stdout
                $master slaveof $slave_host $slave_port
                wait_for_sync $master 
                assert_equal [$master get k] [$peer get k]
                assert_equal [$slave get k] [$master get k]
                assert_equal [$slave get k1] [$master get k1]
                assert_equal [$slave get k1] [$master get k1]
            }
        }
    }
}


test "change-slave(full-sync)" {
    build_env {
        $master set k v 
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        $slave config rewrite
        after 2000
        $master bgsave
        waitForBgsave $master
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        assert_equal [get_slave_srv port] $slave_port
        $master set k1 v1
        after 20
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            set slave [redis $slave_host $slave_port]
            $slave select 9
            $slave slaveof no one 
            wait_for_peers_sync 1 $slave 
            assert_equal [$slave get k] [$peer get k]

            assert_equal [$slave get k1] [$peer get k1]
            start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                set master [redis $master_host $master_port]
                $master select 9
                wait_clean_data $master_stdout
                $master slaveof $slave_host $slave_port
                wait_for_sync $master 
                assert_equal [$master get k] [$peer get k]
                assert_equal [$slave get k] [$master get k]
                assert_equal [$slave get k1] [$master get k1]
                assert_equal [$slave get k1] [$master get k1]
            }
        }
    }
}

test "change-slave(full-sync)-no-backstream" {
    build_env {
        $master set k v 
        
        $slave config rewrite
        after 2000
        $master bgsave
        waitForBgsave $master
        assert_equal [get_slave_srv port] $slave_port
        $master set k1 v1
        after 20
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        assert_equal [$peer get k] [$master get k]
        assert_equal [$slave get k] [$master get k]
        catch {$slave shutdown} error 
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            set slave [redis $slave_host $slave_port]
            $slave select 9
            $slave slaveof no one 
            wait_for_peers_sync 1 $slave 
            assert_equal [$slave get k] [$peer get k]

            assert_equal [$slave get k1] [$peer get k1]
            start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                set master [redis $master_host $master_port]
                $master select 9
                wait_clean_data $master_stdout
                $master slaveof $slave_host $slave_port
                wait_for_sync $master 
                assert_equal [$master get k] [$peer get k]
                assert_equal [$slave get k] [$master get k]
                assert_equal [$slave get k1] [$master get k1]
                assert_equal [$slave get k1] [$master get k1]
            }
        }
    }
}