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
    set retry 500
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
proc write_diff_db {type arrange} {
    start_redis {tags {"r"} config {redis/redis.conf} overrides {repl-diskless-sync-delay 1}} {
        set r [srv 0 client]
        set r_host [srv 0 host]
        set r_port [srv 0 port]
        set r_log [srv 0 stdout]
        $r config set repl-diskless-sync yes
        $r config set repl-diskless-sync-delay 1
        start_server {tags {"repl"} overrides {crdt-gid 3} module {crdt.so} } {
            set peer2 [srv 0 client]
            set peer2_host [srv 0 host]
            set peer2_port [srv 0 port]
            set peer2_log [srv 0 stdout]
            set peer2_gid 3
            $peer2 config set repl-diskless-sync yes
            $peer2 config set repl-diskless-sync-delay 1
            $peer2 config crdt.set repl-diskless-sync-delay 1
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
                    set slave_slave [srv 0 client]
                    set slave_slave_host [srv 0 host]
                    set slave_slave_port [srv 0 port]
                    set slave_slave_log [srv 0 stdout]
                    set slave_slave_gid 1
                    $slave_slave config set repl-diskless-sync yes
                    $slave_slave config set repl-diskless-sync-delay 1
                    $slave_slave config crdt.set repl-diskless-sync-delay 1
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
                                test $type {
                                    if {[catch [uplevel 0 $arrange ] result]} {
                                        puts $result
                                    }
                                    
                                }
                            }
                        }
                    }
                } 
            }
        }
    }
}
proc wait_script {script err} {
    set retry 100
    while {$retry} {
        set conditionCmd [list expr $script] 
        if {[uplevel 1 $conditionCmd]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        catch [uplevel 1 $err] error
    }
}
proc check {m ms mss p  ps p2 } {
    set mv [get_info_replication_attr_value $m crdt.info master_repl_offset]
    wait_script {$mv == [get_info_replication_attr_value $ms crdt.info master_repl_offset]} {
        puts $mv
        puts [get_info_replication_attr_value $ms crdt.info master_repl_offset]
        fail "master and slave offset error "
    }
    wait_script {$mv == [get_info_replication_attr_value $mss crdt.info master_repl_offset]} {
        puts $mv
        puts [get_info_replication_attr_value $mss crdt.info master_repl_offset]
        fail "master and slave-slave offset error "
    }
    set pv [get_info_replication_attr_value $p crdt.info master_repl_offset]
    wait_script {$pv == [get_info_replication_attr_value $ps crdt.info master_repl_offset]} {
        puts $pv
        puts [get_info_replication_attr_value $ps crdt.info master_repl_offset]
        fail "peer and peer-slave offset error"
    }
    wait_script {$pv == [get_info_replication_attr_value $m crdt.info peer0_repl_offset]} {
        puts $pv
        puts [get_info_replication_attr_value $m crdt.info peer0_repl_offset]
        fail "peer and master offset error"
    }
    wait_script {$pv == [get_info_replication_attr_value $ms crdt.info peer0_repl_offset]} {
        puts $pv
        puts [get_info_replication_attr_value $ms crdt.info peer0_repl_offset]
        fail "peer and master-slave offset error"
    }
    wait_script {$pv == [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]} {
        puts $pv
        puts [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]
        fail "slave-slave and peer offset error"
    }
    set p2v [get_info_replication_attr_value $p2 crdt.info master_repl_offset]
    wait_script {$p2v == [get_info_replication_attr_value $m crdt.info peer1_repl_offset]} {
        puts $p2v
        puts [get_info_replication_attr_value $m crdt.info peer1_repl_offset]
        fail "master and peer2 offset error"
    }
    wait_script {$p2v == [get_info_replication_attr_value $ms crdt.info peer1_repl_offset]} {
        puts $p2v
        puts [get_info_replication_attr_value $ms crdt.info peer1_repl_offset]
        fail "slave and peer2 offset error "
    }
    wait_script {$p2v == [get_info_replication_attr_value $mss crdt.info peer1_repl_offset]} {
        puts $p2v
        puts [get_info_replication_attr_value $mss crdt.info peer1_repl_offset]
        fail "slave-slave and peer2 offset error "
    }
}
proc get_keys {client db} {
    set info [$client info keyspace]
    set regstr [format "\r\ndb%s:(.*?)\r\n" $db]
    regexp $regstr $info match value
    set _ $value
}
write_diff_db "write db0 and db5 " {
    $peer_slave slaveof $peer_host $peer_port
    set load_handle0 [start_write_db_load $r_host $r_port 10 0]
    set load_handle1 [start_write_db_load $r_host $r_port 6 1]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    
    $peer slaveof $r_host $r_port
    wait $r 0 info $r_log
    after 5000
    $master peerof $peer_gid $peer_host $peer_port
    $master peerof $peer2_gid $peer2_host $peer2_port
    after 5000
    wait $peer 0 crdt.info $master_log
    wait $peer2 0 crdt.info $master_log

    puts [$r info Keyspace]
    puts [$peer info Keyspace]

    $slave slaveof $master_host $master_port
    
    after 5000
    wait $master 0 info $slave_log
    wait $peer 0 info $peer_slave_log

    $slave_slave slaveof $slave_host $slave_port
    after 5000
    wait $slave 0 info $slave_slave_log
    

    set load_handle2 [start_write_db_load $r_host $r_port 20 2]
    set load_handle3 [start_write_db_load $peer2_host $peer2_port 8 3]
    set load_handle4 [start_write_db_load $peer2_host $peer2_port 4 4]

    after 5000
    # # Stop the write load
    
    stop_write_load $load_handle2
    stop_write_load $load_handle3
    stop_write_load $load_handle4
    after 5000
    $master debug set-crdt-ovc 0
    # print_file_matches $peer_log
    $peer debug set-crdt-ovc 0
    $peer2 debug set-crdt-ovc 0
    # print_file_matches $peer_slave_log
    check $master $slave $slave_slave $peer  $peer_slave $peer2
    puts [$peer info Keyspace]
    puts [$master info Keyspace]
    assert_equal [get_keys $master 0] [get_keys $peer 0]
    assert_equal [get_keys $master 1] [get_keys $peer 1]
    assert_equal [get_keys $master 2] [get_keys $peer 2]
    assert_equal [get_keys $master 3] [get_keys $peer2 3]
    assert_equal [get_keys $master 4] [get_keys $peer2 4]

}