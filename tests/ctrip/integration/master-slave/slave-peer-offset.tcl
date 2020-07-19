proc print_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}
proc wait { client index type log}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            assert_equal [$client ping] PONG
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        assert_equal [$client ping] PONG
        print_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set test [srv 0 client]
    set test_host [srv 0 host]
    set test_port [srv 0 port]
    set test_log [srv 0 stdout]
    set test_gid 1
    $test config set repl-diskless-sync yes
    $test config set repl-diskless-sync-delay 1
    $test config crdt.set repl-diskless-sync-delay 1
    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_log [srv 0 stdout]
        set slave_gid 1
        $slave config set repl-diskless-sync yes
        $slave config set repl-diskless-sync-delay 1
        $slave config crdt.set repl-diskless-sync-delay 1
        
        start_server {overrides {crdt-gid 1} module {crdt.so}} {
            set master [srv 0 client]
            set master_host [srv 0 host]
            set master_port [srv 0 port]
            set master_log [srv 0 stdout]
            set master_gid 1
            $master config set repl-diskless-sync yes
            $master config set repl-diskless-sync-delay 1
            $master config crdt.set repl-diskless-sync-delay 1
            start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
                set peer_slave [srv 0 client]
                set peer_slave_host [srv 0 host]
                set peer_slave_port [srv 0 port]
                set peer_slave_log [srv 0 stdout]
                set peer_slave_gid 2
                $peer_slave config set repl-diskless-sync yes
                $peer_slave config set repl-diskless-sync-delay 1
                $peer_slave config crdt.set repl-diskless-sync-delay 1
                start_server {overrides {crdt-gid 2} module {crdt.so}} {
                    set peer [srv 0 client]
                    set peer_host [srv 0 host]
                    set peer_port [srv 0 port]
                    set peer_log [srv 0 stdout]
                    set peer_gid 2
                    $peer config set repl-diskless-sync yes
                    $peer config set repl-diskless-sync-delay 1
                    $peer config crdt.set repl-diskless-sync-delay 1
                    $peer_slave slaveof $peer_host $peer_port
                    $test peerof $peer_gid $peer_host $peer_port
                    wait $peer 0 crdt.info $peer_log
                    wait $peer 0 info $peer_log
                    $peer set k v
                    test "1" {
                        
                        $master peerof $peer_gid $peer_host $peer_port
                        $peer peerof $master_gid $master_host $master_port

                        proc check {m ms p ps} {
                            set pv [get_info_replication_attr_value $p crdt.info master_repl_offset]
                            assert_equal $pv [get_info_replication_attr_value $ps crdt.info master_repl_offset]
                            assert_equal $pv [get_info_replication_attr_value $m crdt.info peer0_repl_offset]
                            assert_equal $pv [get_info_replication_attr_value $ms crdt.info peer0_repl_offset] 
                        }
                        wait $master 0 crdt.info $master_log
                        wait $peer 1 crdt.info $peer_log
                        $slave slaveof $master_host $master_port
                        wait $master 0 info $slave_log
                        assert_equal [get_info_replication_attr_value $master crdt.info peer0_repl_offset] [get_info_replication_attr_value $slave crdt.info peer0_repl_offset] 
                        $peer set k v1
                        after 2000
                        assert_equal [$peer_slave get k] v1
                        check $master $slave $peer $peer_slave
                        # print_file_matches $peer_slave_log
                        $peer del k
                        after 2000 
                        check $master $slave $peer $peer_slave
                        # print_file_matches $slave_log
                        $peer hset h k v k1 v1
                        after 2000
                        assert_equal [$master hget h k1 ] v1
                        assert_equal [$slave hget h k1] v1
                        assert_equal [$peer_slave hget h k1] v1
                        $peer hdel h k k1 
                        after 2000
                        check $master $slave $peer $peer_slave
                        $peer hset h k v k1 v1
                        after 2000
                        check $master $slave $peer $peer_slave
                        $peer del h 
                        after 2000
                        check $master $slave $peer $peer_slave
                        $peer set k v 
                        $peer expire k 10
                        after 2000
                        check $master $slave $peer $peer_slave 
                        $peer mset k v k1 v1
                        after 2000
                        # puts [get_info_replication_attr_value $master crdt.info peer0_repl_offset]
                        # puts [get_info_replication_attr_value $slave crdt.info peer0_repl_offset]
                        puts [$peer crdt.info stats]
                        # $slave peerof $peer_gid $peer_host $peer_port

                        # puts [$peer crdt.info replication]
                        # puts [$slave crdt.info replication]
                        $slave slaveof no one 
                        # $peer del k v 


                        wait $peer 2 crdt.info $peer_log
                        puts [$peer crdt.info stats]
                        # print_file_matches $slave_log
                        # print_file_matches $peer_log
                    }
                    
                }
            }
        }
            
    }
}