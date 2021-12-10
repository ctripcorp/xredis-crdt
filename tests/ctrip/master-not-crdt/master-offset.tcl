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

proc test_write_data_offset {CheckMasterSlave master slave slave_slave non_crdt_masternon_crdt_master_slave} {
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
            fail [format "%s non_crdt_masterand peer-slave offset error" $type]
        }
        wait_script { $pv == [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]
            fail [format "<%s>,slave-slave and peer-slave offset error" $type]
        }
        $m debug set-crdt-ovc 1
        $p debug set-crdt-ovc 1
    }
    
    check "before write" $CheckMasterSlave $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    $non_crdt_master set k v
    after $delay_time
    if {[$non_crdt_slave get k] != {v}} {
        puts [$non_crdt_slave get k]
        fail "get k != v"
    }
    
    check "set k v" $CheckMasterSlave $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    # print_file_matches $non_crdt_slave_log
    $non_crdt_master del k
    check "del k " $CheckMasterSlave $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    # print_file_matches $slave_log
    $non_crdt_master hset h k v k1 v2

    check "hset-1 h" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    $non_crdt_master hdel h k k1 

    check "hdel h" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    $non_crdt_master hset h k v k1 v1

    check "hset-2 h" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    $non_crdt_master del h 
    check "del h" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave

    $non_crdt_master mset k v2 k1 v1
    check "mset" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave 

    $non_crdt_master setex k1 2 v0
    check "setex k1" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave

    $non_crdt_master set k v1 
    $non_crdt_master expire k 1
    after $delay_time
    assert_equal [$master get k] {}
    check "expire k" $CheckMasterSlave  $master $slave $slave_slave $non_crdt_master $non_crdt_slave
    
    
}
proc test_slave_peer {slave non_crdt_masterlog} {
    set before_full_num [crdt_stats $non_crdt_master sync_full]
    set before_sync_partial_ok [crdt_stats $non_crdt_master sync_partial_ok]
    $slave slaveof no one 
    wait $non_crdt_master 1 crdt.info $log
    assert_equal [crdt_stats $non_crdt_master sync_full] $before_full_num
    # print_file_matches $log
    assert_equal [crdt_stats $non_crdt_master sync_partial_ok] [expr $before_sync_partial_ok + 1]
}



proc slave-peer-offset {type arrange} { 
    set server_path [tmpdir "master-offset"]
    
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
                    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
                        set non_crdt_slave [srv 0 client]
                        set non_crdt_slave_host [srv 0 host]
                        set non_crdt_slave_port [srv 0 port]
                        set non_crdt_slave_log [srv 0 stdout]
                        set non_crdt_slave_gid 2
                        $non_crdt_slave config set repl-diskless-sync yes
                        $non_crdt_slave config set repl-diskless-sync-delay 1
                        # $non_crdt_slave config crdt.set repl-diskless-sync-delay 1
                        # $non_crdt_slave config crdt.set repl-backlog-size 1M
                        start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
                            set non_crdt_master [srv 0 client]
                            set non_crdt_master_host [srv 0 host]
                            set non_crdt_master_port [srv 0 port]
                            set non_crdt_master_log [srv 0 stdout]
                            set non_crdt_master_gid 2
                            $non_crdt_master config set repl-diskless-sync yes
                            $non_crdt_master config set repl-diskless-sync-delay 1
                            # $non_crdt_master config crdt.set repl-diskless-sync-delay 1
                            # $non_crdt_master config crdt.set repl-backlog-size 1M
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


slave-peer-offset "maste-slave" {
    $non_crdt_slave slaveof $non_crdt_master_host $non_crdt_master_port
    wait_for_sync $non_crdt_slave 
    set load_handle1 [start_write_load_with_interval $non_crdt_master_host $non_crdt_master_port 1 20]
    after 1000
    stop_write_load $load_handle1
    $non_crdt_master set k1 v1 
    $master slaveof $non_crdt_slave_host $non_crdt_slave_port
    wait_for_sync $master 
    $non_crdt_master set k2 v2
    set load_handle1 [start_write_load_with_interval $non_crdt_master_host $non_crdt_master_port 1 20]
    after 1000
    stop_write_load $load_handle1
    assert_equal [$master get k1] v1
    assert_equal [$master get k2] v2
    $non_crdt_slave slaveof no one
    $master slaveof $non_crdt_master_host $non_crdt_master_port
    set load_handle1 [start_write_load_with_interval $non_crdt_master_host $non_crdt_master_port 1 20]
    after 1000
    stop_write_load $load_handle1
    $non_crdt_master set k3 v3
    wait_for_sync $master  
    after 1000
    assert_equal [$master get k3] v3
    after 1000
    assert_equal [$non_crdt_master dbsize] [$master dbsize]
    assert_equal [get_info_replication_attr_value $non_crdt_master info master_repl_offset] [get_info_replication_attr_value $master info slave_repl_offset]
    
}

