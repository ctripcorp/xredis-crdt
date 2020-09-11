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
            set master [srv 0 client]
            set master_host [srv 0 host]
            set master_port [srv 0 port]
            set master_log [srv 0 stdout]
            set master_gid 1
            $master config set repl-diskless-sync yes
            $master config set repl-diskless-sync-delay 1
            $master config crdt.set repl-diskless-sync-delay 1
            $master config crdt.set repl-backlog-size 1M
            
            test $type {
                if {[catch [uplevel 0 $arrange ] result]} {
                    puts $result
                }
            }
            
        }
        
    }
    
}


slave-peer-offset "maste-slave" {

    $slave slaveof $master_host $master_port
    wait_for_sync $slave
    $master slaveof $slave_host $slave_port
    $master config set slave-read-only no
    $master set k v0
    $master slaveof no one
    wait_for_sync $slave
    assert_equal [$slave get k] {}
}

