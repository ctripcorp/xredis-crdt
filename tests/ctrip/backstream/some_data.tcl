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


proc run_thread {peer2_host peer2_port time } {
    set _ [start_write_script $peer2_host $peer2_port $time  { 
        $r sadd [format "set-%s" [randomKey]] a b c
        $r srem [format "set-%s" [randomKey]] a
        $r del  [format "set-%s" [randomKey]]
        $r set [format "rc-%s" [randomKey]] [randomInt 123456789]
        $r set [format "reg-%s" [randomKey]] [randomKey]
        $r hset [format "hash-%s" [randomKey]] [randomKey] [randomValue]
        $r zadd [format "zset-%s" [randomKey]]  [randomFloat -99999999 999999999] mfield
        $r zadd [format "zset-%s" [randomKey]] [randomInt 9999999] [randomValue] [randomInt 9999999] [randomValue]
        $r incrby [format "rc-%s" [randomKey]] 10
        $r incrbyfloat [format "rc-%s" [randomKey]] 20.0
    } ]
    
}

# test "2peer shutdown" {
#     build_env {
#         set load_handle0 [run_thread $master_host $master_port 5000]
#         set load_handle1 [run_thread $peer_host $peer_port 5000]
#         after 5000
#         stop_write_load $load_handle0
#         stop_write_load $load_handle1
#         after 2000
#         assert_equal  [$master dbsize] [$peer dbsize]
#         assert_equal  [$peer2 dbsize] [$peer dbsize]
#         catch {$master shutdown} error 
#         catch {$peer2 shutdown} error2
        

#     }
# }
test "restart" {
    build_env {
        set load_handle0 [run_thread $master_host $master_port 5000]
        after 5000
        stop_write_load $load_handle0
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        after 20
        catch {$slave shutdown} error 
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        after 1000
        start_server_by_config [get_slave_srv config_file] [get_slave_srv config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
            set slave [redis $slave_host $slave_port]
            $slave select 9
            start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                set master [redis $master_host $master_port]
                $master select 9
                wait_for_peers_sync 1 $master 
                wait_for_sync $slave 
                assert_equal [$master dbsize] [$peer dbsize]
                assert_equal [$slave dbsize] [$master dbsize]
            }
        }
    }
}
test "change_master_when_start_master" {
    build_env {
        set load_handle0 [run_thread $master_host $master_port 5000]
        after 5000
        stop_write_load $load_handle0
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        after 20
        catch {$slave shutdown} error 
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        after 1000
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
                $master slaveof $slave_host $slave_port
                wait_for_sync $master 
                assert_equal [$master dbsize ] [$peer dbsize]
                assert_equal [$slave dbsize] [$master dbsize]

            }
        }
    }
}

proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

proc wait_start_peer {log} {
    set fp [open $log r]
    while {1} {
        set content [read $fp]
        puts $content
        if {[string match {*[CRDT][crdtMergeStartCommand][begin]*} $content]} {
            break;
        } else {
            after 1000
        }
        
    }
    close $fp
}
test "peering" {
    build_env {
        set load_handle0 [run_thread $master_host $master_port 5000]
        after 5000
        stop_write_load $load_handle0
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        after 20
        catch {$slave shutdown} error 
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        after 1000
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
                wait_start_peer $master_stdout
                $master slaveof $slave_host $slave_port
                wait_for_sync $master 
                assert_equal [$master dbsize ] [$peer dbsize]
                assert_equal [$slave dbsize] [$master dbsize]

            }
        }
    }
}
test "peerof over" {
    build_env {
        set load_handle0 [run_thread $master_host $master_port 5000]
        after 5000
        stop_write_load $load_handle0
        $slave slaveof $master_host $master_port
        wait_for_sync $slave 
        after 20
        catch {$slave shutdown} error 
        catch {$master shutdown} error
        assert_equal [get_slave_srv port] $slave_port
        assert_equal [get_master_srv port] $master_port
        set master_config_file [get_master_srv config_file]
        set master_config [get_master_srv config]
        after 1000
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
                after 3000
                wait_for_peers_sync 1 $master 
                $master slaveof $slave_host $slave_port
                wait_for_sync $master 
                assert_equal [$master dbsize ] [$peer dbsize]
                assert_equal [$slave dbsize] [$master dbsize]

            }
        }
    }
}