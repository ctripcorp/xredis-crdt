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
proc wait_script {script err} {
    set retry 50
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

proc test_write_data_offset {CheckMasterSlave master slave slave_slave peer peer_slave} {
    set delay_time 2000
    proc check {type CheckMasterSlave m ms mss p ps } {
        $m debug set-crdt-ovc 0
        $p debug set-crdt-ovc 0
        if {$CheckMasterSlave} {
            set mv [get_info_replication_attr_value $m crdt.info master_repl_offset]
            wait_script {$mv == [get_info_replication_attr_value $ms crdt.info master_repl_offset]} {
                puts $mv
                puts [get_info_replication_attr_value $ms crdt.info master_repl_offset]
                fail [format "%s master and slave offset error" $type]
            }
            wait_script  {$mv == [get_info_replication_attr_value $mss crdt.info master_repl_offset]} {
                puts $mv
                puts [get_info_replication_attr_value $mss crdt.info master_repl_offset]
                fail [format "%s master and slave-slave offset error " $type]
            }
        } else {
            set mv [get_info_replication_attr_value $ms crdt.info master_repl_offset]
            wait_script  {$mv == [get_info_replication_attr_value $mss crdt.info master_repl_offset]} {
                puts $mv
                puts [get_info_replication_attr_value $mss crdt.info master_repl_offset]
                fail [format "%s slave and slave-slave offset error " $type]
            }
        }
        
        set pv [get_info_replication_attr_value $p crdt.info master_repl_offset]
        wait_script {$pv == [get_info_replication_attr_value $ps crdt.info master_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $ps crdt.info master_repl_offset]
            fail [format "%s master and peer-slave offset error" $type]
        }
        wait_script  { $pv == [get_info_replication_attr_value $m crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $m crdt.info peer0_repl_offset]
            fail [format "%s master and peer-slave offset error" $type]
        }
        wait_script { $pv == [get_info_replication_attr_value $ms crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $ms crdt.info peer0_repl_offset]
            fail [format "%s peer and peer-slave offset error" $type]
        }
        wait_script { $pv == [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]
            fail [format "<%s>,slave-slave and peer-slave offset error" $type]
        }
        $m debug set-crdt-ovc 1
        $p debug set-crdt-ovc 1
    }
    
    check "before write" $CheckMasterSlave $master $slave $slave_slave $peer $peer_slave
    $peer set k v
    after $delay_time
    if {[$peer_slave get k] != {v}} {
        puts [$peer_slave get k]
        fail "get k != v"
    }
    
    check "set k v" $CheckMasterSlave $master $slave $slave_slave $peer $peer_slave
    # print_file_matches $peer_slave_log
    $peer del k
    check "del k " $CheckMasterSlave $master $slave $slave_slave $peer $peer_slave
    # print_file_matches $slave_log
    $peer hset h k v k1 v2

    check "hset-1 h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    $peer hdel h k k1 

    check "hdel h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    $peer hset h k v k1 v1

    check "hset-2 h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    $peer del h 
    check "del h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave

    $peer mset k v2 k1 v1
    check "mset" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave 

    $peer setex k1 2 v0
    check "setex k1" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave

    $peer set k v1 
    $peer expire k 1
    after $delay_time
    assert_equal [$master get k] {}
    check "expire k" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    
    
}
proc test_slave_peer {slave peer log} {
    set before_full_num [crdt_stats $peer sync_full]
    set before_sync_partial_ok [crdt_stats $peer sync_partial_ok]
    $slave slaveof no one 
    wait $peer 1 crdt.info $log
    assert_equal [crdt_stats $peer sync_full] $before_full_num
    # print_file_matches $log
    assert_equal [crdt_stats $peer sync_partial_ok] [expr $before_sync_partial_ok + 1]
}



proc slave-peer-offset {type arrange} {
    start_server {tags {"repl"} overrides {crdt-gid 3} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_log [srv 0 stdout]
        set peer2_gid 3
        $peer2 config set repl-diskless-sync yes
        $peer2 config set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-backlog-size 1M
        start_server {overrides {crdt-gid 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            set slave_gid 1
            $slave config set repl-diskless-sync yes
            $slave config set repl-diskless-sync-delay 1
            $slave config crdt.set repl-diskless-sync-delay 1
            $slave config crdt.set repl-backlog-size 1M
            start_server {overrides {crdt-gid 1} module {crdt.so}} {
                set slave_slave [srv 0 client]
                set slave_slave_host [srv 0 host]
                set slave_slave_port [srv 0 port]
                set slave_slave_log [srv 0 stdout]
                set slave_slave_gid 1
                $slave_slave config set repl-diskless-sync yes
                $slave_slave config set repl-diskless-sync-delay 1
                $slave_slave config crdt.set repl-diskless-sync-delay 1
                $slave_slave config crdt.set repl-backlog-size 1M
                start_server {overrides {crdt-gid 1} module {crdt.so}} {
                    set master [srv 0 client]
                    set master_host [srv 0 host]
                    set master_port [srv 0 port]
                    set master_log [srv 0 stdout]
                    set master_gid 1
                    $master config set repl-diskless-sync yes
                    $master config set repl-diskless-sync-delay 1
                    $master config crdt.set repl-diskless-sync-delay 1
                    $master config crdt.set repl-backlog-size 1M
                    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
                        set peer_slave [srv 0 client]
                        set peer_slave_host [srv 0 host]
                        set peer_slave_port [srv 0 port]
                        set peer_slave_log [srv 0 stdout]
                        set peer_slave_gid 2
                        $peer_slave config set repl-diskless-sync yes
                        $peer_slave config set repl-diskless-sync-delay 1
                        $peer_slave config crdt.set repl-diskless-sync-delay 1
                        $peer_slave config crdt.set repl-backlog-size 1M
                        start_server {overrides {crdt-gid 2} module {crdt.so}} {
                            set peer [srv 0 client]
                            set peer_host [srv 0 host]
                            set peer_port [srv 0 port]
                            set peer_log [srv 0 stdout]
                            set peer_gid 2
                            $peer config set repl-diskless-sync yes
                            $peer config set repl-diskless-sync-delay 1
                            $peer config crdt.set repl-diskless-sync-delay 1
                            $peer config crdt.set repl-backlog-size 1M
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


slave-peer-offset "1. master->slave full sync 2. peer -> master full sync" {
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $master_host $master_port 3]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    $slave slaveof $master_host $master_port 
    wait $master 0 info $master_log

    $master peerof $peer_gid $peer_host $peer_port
    
    wait $peer 0 crdt.info $peer_log

    after 1000
    assert_equal [crdt_stats $peer sync_full] 1
    assert_equal [status $master sync_full] 1
    check_peer_info $peer $slave 0
}


slave-peer-offset "1. peer -> master full sync 2. master->slave full sync " {
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $peer_host $peer_port 3]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1

    $master peerof $peer_gid $peer_host $peer_port
    wait_for_peer_sync $master
    $slave slaveof $master_host $master_port 
    wait $master 0 info $master_log
    
    after 1000
    assert_equal [crdt_stats $peer sync_full] 1
    assert_equal [status $master sync_full] 1
    check_peer_info $peer $slave 0
}


slave-peer-offset "1. peer -> master full sync and add data 2. master->slave full sync " {
    $master peerof $peer_gid $peer_host $peer_port
    wait $peer 0 crdt.info $peer_log

    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $peer_host $peer_port 3]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1

    $slave slaveof $master_host $master_port 
    wait $master 0 info $master_log
    after 1000
    assert_equal [crdt_stats $peer sync_full] 1
    assert_equal [status $master sync_full] 1
    check_peer_info $peer $slave 0
}

slave-peer-offset "1. peer -> master partial sync 2. master->slave full sync " {
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $peer_host $peer_port 3]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    $peer_slave slaveof $peer_host $peer_port
    wait $peer 0 info $peer_log
    after 1000
    #slave as peer only full-sync 
    $master peerof $peer_slave_gid $peer_slave_host $peer_slave_port
    wait $peer_slave 0 crdt.info $peer_slave_log
    
    $peer set k v 
    after 1000
    $master peerof $peer_gid $peer_host $peer_port
    wait $peer 0 crdt.info $peer_log
    assert_equal [crdt_stats $peer sync_full] 0
    assert_equal [crdt_stats $peer sync_partial_ok] 1

    $slave slaveof $master_host $master_port 
    wait $master 0 info $master_log
    after 1000
    check_peer_info $peer $slave 0
}


slave-peer-offset "1. master->slave full sync 2. peer -> master partial sync" {
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $peer_host $peer_port 3]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1

    $slave slaveof $master_host $master_port 
    $peer_slave slaveof $peer_host $peer_port
    wait $peer 0 info $peer_log
    wait $master 0 info $master_log
    wait_for_sync $peer_slave

    assert_equal [$peer_slave dbsize] [$peer dbsize]
    $master peerof $peer_slave_gid $peer_slave_host $peer_slave_port
    wait_for_peer_sync $master
    wait_for_sync $slave
    # puts [$master crdt.info replication]
    $master peerof $peer_gid $peer_host $peer_port
    $peer set k v0
    wait $peer 0 crdt.info $peer_log
    assert_equal [crdt_stats $peer sync_full] 0
    assert_equal [crdt_stats $peer sync_partial_ok] 1
    after 1000
    # puts [$master crdt.info replication]
    # print_file_matches $slave_log
    assert_equal [$slave get k] v0
    # print_file_matches $slave_log
    check_peer_info $peer $slave 0
}


slave-peer-offset "1. master->slave full sync 2. peer -> master full sync add data" {
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $peer_host $peer_port 3]
    after 3000
    stop_write_load $load_handle0
    stop_write_load $load_handle1

    $slave slaveof $master_host $master_port 
    wait $master 0 info $master_log
    after 1000

    $master peerof $peer_gid $peer_host $peer_port
    wait $peer 0 crdt.info $peer_log
    assert_equal [crdt_stats $peer sync_full] 1
    assert_equal [crdt_stats $peer sync_partial_ok] 0

    set load_handle2 [start_write_load $peer_host $peer_port 3]
    after 3000
    stop_write_load $load_handle2
    after 3000
    check_peer_info $peer $slave 0
}





