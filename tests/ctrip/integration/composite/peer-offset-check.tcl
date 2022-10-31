proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc log_content {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}

proc crdt_status { client property } {
    set info [ $client crdt.info stats]
    if {[regexp "\r\n$property:(.*?)\r\n" $info _ value]} {
        set _ $value
    }
}

proc crdt_repl { client property } {
    set info [ $client crdt.info replication]
    if {[regexp "\r\n$property:(.*?)\r\n" $info _ value]} {
        set _ $value
    }
}

####################################### Stage1: Build Two Peer(Master-Slave) Replication ####################################################
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {

    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdout {}

    set slaves {}
    set slave_hosts {}
    set slave_ports {}
    set slave_stdout {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdout [srv 0 stdout]
    lappend peer_gids 1

    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    [lindex $peers 0] config crdt.set repl-backlog-size 32768

    # Start to write random val(set k v and hmset and hset, del, hdel, expire). for 2 sec
    # the data will be used in full-sync
    set load_handle0 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]
    set load_handle1 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]
    set load_handle2 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]
    set load_handle3 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]
    set load_handle4 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]

    start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        lappend slaves [srv 0 client]
        lappend slave_hosts [srv 0 host]
        lappend slave_ports [srv 0 port]
        lappend slave_stdout [srv 0 stdout]
        set slave0_log [srv 0 stdout]

        [lindex $slaves 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $slaves 0] config set repl-diskless-sync-delay 1
        [lindex $slaves 0] config crdt.set repl-backlog-size 32768

        [lindex $slaves 0] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]

        after 500
        # Stop the write load
        stop_write_load $load_handle0
        stop_write_load $load_handle1
        stop_write_load $load_handle2
        stop_write_load $load_handle3
        stop_write_load $load_handle4

        start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdout [srv 0 stdout]
            lappend peer_gids 2

            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            [lindex $peers 1] config crdt.set repl-backlog-size 32768

            # Start to write random val(set k v and hmset and hset). for 5 sec
            # the data will be used in full-sync
            set load_handle5 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 2]
            set load_handle6 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 2]
            set load_handle7 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 2]
            set load_handle8 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 2]
            set load_handle9 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 2]

            start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {

                lappend slaves [srv 0 client]
                lappend slave_hosts [srv 0 host]
                lappend slave_ports [srv 0 port]
                lappend slave_stdout [srv 0 stdout]

                [lindex $slaves 1] config crdt.set repl-diskless-sync-delay 1
                [lindex $slaves 1] config set repl-diskless-sync-delay 1
                [lindex $slaves 1] config crdt.set repl-backlog-size 32768

                [lindex $slaves 1] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]


                after 500
                # Stop the write load
                stop_write_load $load_handle5
                stop_write_load $load_handle6
                stop_write_load $load_handle7
                stop_write_load $load_handle8
                stop_write_load $load_handle9

                set retry 500
                while {$retry} {
                    set info [[lindex $peers 0] info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 50
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $slave_stdout 0]]
                    error "assertion:Peers not correctly synchronized"
                }

                set retry 500
                while {$retry} {
                    set info [[lindex $peers 1] info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 50
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $slave_stdout 1]]
                    error "assertion:Peers not correctly synchronized"
                }

                test "TEST Two-Peers Full-Sync Add-Slave-Before-PeerOf" {
                    # Send PEEROF commands to peers
                    [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                    [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    set retry 700
                    while {$retry} {
                        set info [[lindex $peers 0] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
                    if {$retry == 0} {
                        puts [log_content [lindex $peer_stdout 1]]
                        error "assertion:Peers not correctly synchronized"
                    }
                    set retry 500
                    while {$retry} {
                        set info [[lindex $peers 1] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 50
                        }
                    }
                    if {$retry == 0} {
                        puts [log_content [lindex $peer_stdout 0]]
                        error "assertion:Peers not correctly synchronized"
                    }

                    # Wait that slaves acknowledge they are online so
                    # we are sure that DBSIZE and DEBUG DIGEST will not
                    # fail because of timing issues.
                    wait_for_condition 500 100 {
                        [lindex [[lindex $peers 0] crdt.role slave [lindex $peer_gids 1]] 3] eq {connected} &&
                        [lindex [[lindex $peers 1] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected}
                    } else {
                        fail "Peers still not connected after some time"
                    }

                    # Make sure that slaves and master have same
                    # number of keys
                    wait_for_condition 500 100 {
                        [[lindex $peers 0] dbsize] == [[lindex $slaves 1] dbsize] &&
                        [[lindex $peers 1] dbsize] == [[lindex $slaves 0] dbsize] &&
                        [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize] &&
                        [[lindex $peers 1] dbsize] == [[lindex $slaves 1] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                }

                # Make sure that slaves and master have same
                # number of keys
                wait_for_condition 500 100 {
                    [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize]
                } else {
                    fail "Different number of keys between masted and slave after too long time."
                }

                test "Offset-Alignment Two-Peers-Full-Sync Add-Slave-Before-PeerOf" {
                    [lindex $peers 0] config crdt.set repl-timeout 600
                    [lindex $peers 1] config crdt.set repl-timeout 600
                    [lindex $peers 0] debug set-crdt-ovc 0
                    [lindex $peers 1] debug set-crdt-ovc 0
                    after 1000
                    [lindex $slaves 0] debug set-crdt-ovc 0
                    [lindex $slaves 1] debug set-crdt-ovc 0

                    after 100

                    wait_for_condition 500 100 {
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $peers 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 0] master_repl_offset] &&
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $peers 0] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 1] master_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 0] peer0_repl_offset]
                    } else {
                        puts [format "peer0 offset: %d" [crdt_status [lindex $peers 0] master_repl_offset]]
                        puts [format "slave0 offset: %d" [crdt_status [lindex $slaves 0] master_repl_offset]]
                        puts [format "peer1 offset: %d" [crdt_status [lindex $peers 1] peer0_repl_offset]]
                        puts [[lindex $peers 1] crdt.info replication]
                        puts [log_content [lindex $peer_stdout 1]]
                        fail "crdt repl offset not aligned."
                    }

                }

                test "VC-Alignment Two-Peers-Full-Sync Add-Slave-Before-PeerOf" {
                    [lindex $peers 0] config crdt.set repl-timeout 600
                    [lindex $peers 1] config crdt.set repl-timeout 600
                    [lindex $peers 0] debug set-crdt-ovc 0
                    [lindex $peers 1] debug set-crdt-ovc 0
                    after 1000
                    [lindex $slaves 0] debug set-crdt-ovc 0
                    [lindex $slaves 1] debug set-crdt-ovc 0

                    set peer_0_info [crdt_repl [lindex $peers 0] ovc]
                    set slave_0_info [crdt_repl [lindex $slaves 0] ovc]
                    set peer_1_info [crdt_repl [lindex $peers 1] ovc]
                    set slave_1_info [crdt_repl [lindex $slaves 1] ovc]
                    assert_equal $peer_0_info $slave_0_info
                    assert_equal $peer_1_info $slave_1_info
                    assert_equal $peer_0_info $slave_1_info
                    assert_equal $peer_1_info $slave_0_info
                    assert_equal $peer_0_info $peer_1_info
                }

                #######################################Stage2: Add New Slave After Peer Full Sync######################################################
                puts "Stage2: Add New Slave After Peer Full Sync"
                start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
                    lappend slaves [srv 0 client]
                    lappend slave_hosts [srv 0 host]
                    lappend slave_ports [srv 0 port]
                    lappend slave_stdout [srv 0 stdout]

                    [lindex $slaves 1] config crdt.set repl-diskless-sync-delay 1
                    [lindex $slaves 1] config set repl-diskless-sync-delay 1
                    [lindex $slaves 1] config crdt.set repl-backlog-size 32768

                    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
                        lappend slaves [srv 0 client]
                        lappend slave_hosts [srv 0 host]
                        lappend slave_ports [srv 0 port]
                        lappend slave_stdout [srv 0 stdout]

                        [lindex $slaves 1] config crdt.set repl-diskless-sync-delay 1
                        [lindex $slaves 1] config set repl-diskless-sync-delay 1
                        [lindex $slaves 1] config crdt.set repl-backlog-size 32768

                        [lindex $slaves 2] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
                        [lindex $slaves 3] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]

                        set retry 500
                        while {$retry} {
                            set info [[lindex $peers 0] info replication]
                            if {[string match {*slave1:*state=online*} $info]} {
                                break
                            } else {
                                incr retry -1
                                after 50
                            }
                        }
                        if {$retry == 0} {
                            puts [log_content [lindex $slave_stdout 2]]
                            error "assertion:Slave2 not correctly synchronized"
                        }

                        set retry 500
                        while {$retry} {
                            set info [[lindex $peers 1] info replication]
                            if {[string match {*slave1:*state=online*} $info]} {
                                break
                            } else {
                                incr retry -1
                                after 50
                            }
                        }
                        if {$retry == 0} {
                            puts [log_content [lindex $slave_stdout 3]]
                            error "assertion:Slave3 not correctly synchronized"
                        }

                        test "Offset-Alignment Two-Peers-Full-Sync Add-Slave-After-PeerOf" {

                            wait_for_condition 500 100 {
                                [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $peers 1] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 2] master_repl_offset] &&
                                [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 3] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $peers 0] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 2] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 3] master_repl_offset]
                            } else {
                                puts [format "peer0 master-offset: %lld" [crdt_repl [lindex $peers 0] master_repl_offset]]
                                puts [format "slave0 offset: %lld" [crdt_repl [lindex $slaves 0] master_repl_offset]]
                                puts [format "slave2 offset: %lld" [crdt_repl [lindex $slaves 2] master_repl_offset]]
                                puts [format "peer1 offset: %lld" [crdt_repl [lindex $peers 1] peer0_repl_offset]]

                                puts [format "peer1 master-offset: %lld" [crdt_repl [lindex $peers 1] master_repl_offset]]
                                puts [format "slave1 offset: %lld" [crdt_repl [lindex $slaves 1] master_repl_offset]]
                                puts [format "slave3 offset: %lld" [crdt_repl [lindex $slaves 3] master_repl_offset]]
                                puts [format "peer0 offset: %lld" [crdt_repl [lindex $peers 0] peer0_repl_offset]]

                                puts [log_content [lindex $slave_stdout 2]]
                                puts [log_content [lindex $slave_stdout 3]]
                                fail "crdt repl offset not aligned."
                            }

                        }

                        test "VC-Alignment Two-Peers-Full-Sync Add-Slave-After-PeerOf" {
                            set peer_0_info [crdt_repl [lindex $peers 0] ovc]
                            set slave_2_info [crdt_repl [lindex $slaves 2] ovc]
                            set peer_1_info [crdt_repl [lindex $peers 1] ovc]
                            set slave_3_info [crdt_repl [lindex $slaves 3] ovc]
                            assert_equal $peer_0_info $slave_2_info
                            assert_equal $peer_1_info $slave_3_info
                            assert_equal $peer_0_info $slave_3_info
                            assert_equal $peer_1_info $slave_2_info
                            assert_equal $peer_0_info $peer_1_info
                        }
                    }
                }


                ######################################### Stage 3: Peer Reconnect & Partial Sync ########################################
                puts "Stage 3: Peer Reconnect & Partial Sync"
                test "TEST Two-Peers-Partial-Sync Add-Slave-Before-PeerOf" {
                    set sync_partial_ok_0 [ crdt_status [lindex $peers 0] "sync_partial_ok" ]
                    set sync_partial_ok_1 [ crdt_status [lindex $peers 1] "sync_partial_ok" ]

                    [lindex $peers 0] debug set-crdt-ovc 1
                    [lindex $peers 1] debug set-crdt-ovc 1
                    [lindex $slaves 0] debug set-crdt-ovc 1
                    [lindex $slaves 1] debug set-crdt-ovc 1

                    set load_handle1 [start_write_load_with_interval [lindex $peer_hosts 1] [lindex $peer_ports 1] 1 20]
                    set load_handle2 [start_write_load_with_interval [lindex $peer_hosts 0] [lindex $peer_ports 0] 1 20]
                    after 40              
                    # client kill crdt-master => disturb peer sync
                    puts [format "killed clients: %d" [[lindex $peers 0] client kill type crdt.master]]
                    puts [format "killed clients: %d" [[lindex $peers 1] client kill type crdt.master]]

                    after 200
                    # Stop the write load
                    stop_write_load $load_handle1
                    stop_write_load $load_handle2

                    ### insensitive the redis peer-repl state
                    [lindex $peers 0] config crdt.set repl-timeout 600
                    [lindex $peers 1] config crdt.set repl-timeout 600
                    [lindex $peers 0] debug set-crdt-ovc 0
                    [lindex $peers 1] debug set-crdt-ovc 0
                    after 1000
                    [lindex $slaves 0] debug set-crdt-ovc 0
                    [lindex $slaves 1] debug set-crdt-ovc 0

                    set retry 700
                    while {$retry} {
                        set info [[lindex $peers 0] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
                    if {$retry == 0} {
                        puts [log_content [lindex $peer_stdout 1]]
                        error "assertion:Peers not correctly synchronized"
                    }
                    set retry 500
                    while {$retry} {
                        set info [[lindex $peers 1] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 50
                        }
                    }
                    if {$retry == 0} {
                        puts [log_content [lindex $peer_stdout 0]]
                        error "assertion:Peers not correctly synchronized"
                    }

                    # Send PEEROF commands to peers
                    set result_0 [[lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]]
                    set result_1 [[lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]]
                    assert_equal [string match "*Already*" $result_0] 1
                    assert_equal [string match "*Already*" $result_1] 1

                    set sync_partial_ok_now_0 [ crdt_status [lindex $peers 0] "sync_partial_ok" ]
                    set sync_partial_ok_now_1 [ crdt_status [lindex $peers 1] "sync_partial_ok" ]

                    # puts [format "sync_partial_ok-0: %d" $sync_partial_ok_now_0]
                    # puts [format "sync_partial_ok-1: %d" $sync_partial_ok_now_1]
                    # puts [format "sync_full_0: %d" [crdt_status [lindex $peers 0] "sync_full" ]]
                    # puts [format "sync_full_1: %d" [crdt_status [lindex $peers 1] "sync_full" ]]

                    set partil_incr_0 [expr $sync_partial_ok_now_0 - $sync_partial_ok_0]
                    set partil_incr_1 [expr $sync_partial_ok_now_1 - $sync_partial_ok_1]
                    
                    assert_equal $partil_incr_0 1
                    assert_equal $partil_incr_1 1

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    set retry 700
                    while {$retry} {
                        set info [[lindex $peers 0] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
                    if {$retry == 0} {
                        puts [log_content [lindex $peer_stdout 1]]
                        error "assertion:Peers not correctly synchronized"
                    }
                    set retry 500
                    while {$retry} {
                        set info [[lindex $peers 1] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 50
                        }
                    }
                    if {$retry == 0} {
                        puts [log_content [lindex $peer_stdout 0]]
                        error "assertion:Peers not correctly synchronized"
                    }

                    # Wait that slaves acknowledge they are online so
                    # we are sure that DBSIZE and DEBUG DIGEST will not
                    # fail because of timing issues.
                    wait_for_condition 500 100 {
                        [lindex [[lindex $peers 0] crdt.role slave [lindex $peer_gids 1]] 3] eq {connected} &&
                        [lindex [[lindex $peers 1] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected}
                    } else {
                        fail "Peers still not connected after some time"
                    }

                    # Make sure that slaves and master have same
                    # number of keys
                    wait_for_condition 500 100 {
                        [[lindex $peers 0] dbsize] == [[lindex $slaves 1] dbsize] &&
                        [[lindex $peers 1] dbsize] == [[lindex $slaves 0] dbsize] &&
                        [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize] &&
                        [[lindex $peers 1] dbsize] == [[lindex $slaves 1] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                }

                # Make sure that slaves and master have same
                # number of keys
                wait_for_condition 500 100 {
                    [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize]
                } else {
                    fail "Different number of keys between masted and slave after too long time."
                }

                test "Offset-Alignment Two-Peers-Partial-Sync Add-Slave-Before-PeerOf" {

                    wait_for_condition 500 100 {
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $peers 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 0] master_repl_offset] &&
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $peers 0] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 1] master_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 0] peer0_repl_offset]
                    } else {
                        puts [format "peer0 offset: %d" [crdt_repl [lindex $peers 0] master_repl_offset]]
                        puts [format "slave0 offset: %d" [crdt_repl [lindex $slaves 0] master_repl_offset]]
                        puts [format "peer1 offset: %d" [crdt_repl [lindex $peers 1] peer0_repl_offset]]
                        puts [[lindex $peers 1] crdt.info replication]
                        puts [log_content [lindex $peer_stdout 1]]
                        fail "crdt repl offset not aligned."
                    }

                }

                test "VC-Alignment Two-Peers-Partial-Sync Add-Slave-Before-PeerOf" {
                    set peer_0_info [crdt_repl [lindex $peers 0] ovc]
                    set slave_0_info [crdt_repl [lindex $slaves 0] ovc]
                    set peer_1_info [crdt_repl [lindex $peers 1] ovc]
                    set slave_1_info [crdt_repl [lindex $slaves 1] ovc]
                    assert_equal $peer_0_info $slave_0_info
                    assert_equal $peer_1_info $slave_1_info
                    assert_equal $peer_0_info $slave_1_info
                    assert_equal $peer_1_info $slave_0_info
                    assert_equal $peer_0_info $peer_1_info
                }

                ####################################### Stage 4: Add New Slave During Peer Partial######################################################
                puts "Stage 4: Add New Slave During Peer Partial"
                set load_handle0 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]
                set load_handle1 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 2]
                set load_handle2 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 1] 2]
                set load_handle3 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 1] 2]

                [lindex $peers 0] debug set-crdt-ovc 1
                [lindex $peers 1] debug set-crdt-ovc 1
                [lindex $slaves 0] debug set-crdt-ovc 1
                [lindex $slaves 1] debug set-crdt-ovc 1
                start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
                    lappend slaves [srv 0 client]
                    lappend slave_hosts [srv 0 host]
                    lappend slave_ports [srv 0 port]
                    lappend slave_stdout [srv 0 stdout]

                    [lindex $slaves 1] config crdt.set repl-diskless-sync-delay 1
                    [lindex $slaves 1] config set repl-diskless-sync-delay 1
                    [lindex $slaves 1] config crdt.set repl-backlog-size 32768

                    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
                        lappend slaves [srv 0 client]
                        lappend slave_hosts [srv 0 host]
                        lappend slave_ports [srv 0 port]
                        lappend slave_stdout [srv 0 stdout]

                        [lindex $slaves 1] config crdt.set repl-diskless-sync-delay 1
                        [lindex $slaves 1] config set repl-diskless-sync-delay 1
                        [lindex $slaves 1] config crdt.set repl-backlog-size 32768

                        [lindex $slaves 4] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
                        [lindex $slaves 5] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]

                        set retry 500
                        while {$retry} {
                            set info [[lindex $peers 0] info replication]
                            if {[string match {*slave1:*state=online*} $info]} {
                                break
                            } else {
                                incr retry -1
                                after 50
                            }
                        }
                        if {$retry == 0} {
                            puts [log_content [lindex $slave_stdout 4]]
                            error "assertion:Slave4 not correctly synchronized"
                        }

                        set retry 500
                        while {$retry} {
                            set info [[lindex $peers 1] info replication]
                            if {[string match {*slave1:*state=online*} $info]} {
                                break
                            } else {
                                incr retry -1
                                after 50
                            }
                        }
                        if {$retry == 0} {
                            puts [log_content [lindex $slave_stdout 5]]
                            error "assertion:Slave5 not correctly synchronized"
                        }

                        [lindex $peers 0] debug set-crdt-ovc 0
                        [lindex $peers 1] debug set-crdt-ovc 0
                        after 1000
                        [lindex $slaves 0] debug set-crdt-ovc 0
                        [lindex $slaves 1] debug set-crdt-ovc 0
                        after 300
                        # Stop the write load
                        stop_write_load $load_handle0
                        stop_write_load $load_handle1
                        stop_write_load $load_handle2
                        stop_write_load $load_handle3

                        after 200
                        test "Offset-Alignment Two-Peers-Partial-Sync Add-Slave-After-PeerOf" {

                            wait_for_condition 500 100 {
                                [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $peers 1] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 4] master_repl_offset] &&
                                [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 5] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $peers 0] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 4] peer0_repl_offset] &&
                                [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 5] master_repl_offset]
                            } else {
                                puts [format "peer0 master-offset: %lld" [crdt_repl [lindex $peers 0] master_repl_offset]]
                                puts [format "slave0 offset: %lld" [crdt_repl [lindex $slaves 0] master_repl_offset]]
                                puts [format "slave4 offset: %lld" [crdt_repl [lindex $slaves 4] master_repl_offset]]
                                puts [format "peer1 offset: %lld" [crdt_repl [lindex $peers 1] peer0_repl_offset]]

                                puts [format "peer1 master-offset: %lld" [crdt_repl [lindex $peers 1] master_repl_offset]]
                                puts [format "slave1 offset: %lld" [crdt_repl [lindex $slaves 1] master_repl_offset]]
                                puts [format "slave5 offset: %lld" [crdt_repl [lindex $slaves 5] master_repl_offset]]
                                puts [format "peer0 offset: %lld" [crdt_repl [lindex $peers 0] peer0_repl_offset]]

                                puts [log_content [lindex $slave_stdout 4]]
                                puts [log_content [lindex $slave_stdout 5]]
                                fail "crdt repl offset not aligned."
                            }

                        }

                        test "VC-Alignment Two-Peers-Partial-Sync Add-Slave-After-PeerOf" {
                            set peer_0_info [crdt_repl [lindex $peers 0] ovc]
                            set slave_4_info [crdt_repl [lindex $slaves 4] ovc]
                            set peer_1_info [crdt_repl [lindex $peers 1] ovc]
                            set slave_5_info [crdt_repl [lindex $slaves 5] ovc]
                            assert_equal $peer_0_info $slave_4_info
                            assert_equal $peer_1_info $slave_5_info
                            assert_equal $peer_0_info $slave_5_info
                            assert_equal $peer_1_info $slave_4_info
                            assert_equal $peer_0_info $peer_1_info
                        }
                    }
                }

                ####################################### Stage 5: Master-Slave Switch ######################################################
                puts "Stage 5: Master-Slave Switch"
                set sync_partial_ok_0 [ crdt_status [lindex $slaves 0] "sync_partial_ok" ]
                set sync_partial_ok_1 [ crdt_status [lindex $peers 1] "sync_partial_ok" ]

                set load_handle0 [start_write_load_with_interval [lindex $peer_hosts 1] [lindex $peer_ports 1] 1 100]

                [lindex $slaves 0] slaveof no one
                [lindex $peers 0] slaveof [lindex $slave_hosts 0] [lindex $slave_ports 0]

                [lindex $peers 0] debug set-crdt-ovc 1
                [lindex $peers 1] debug set-crdt-ovc 1
                [lindex $slaves 0] debug set-crdt-ovc 1
                [lindex $slaves 1] debug set-crdt-ovc 1

                after 20

                [lindex $peers 1] peerof 1 [lindex $slave_hosts 0] [lindex $slave_ports 0]

                set retry 500
                while {$retry} {
                    set info [[lindex $peers 1] crdt.info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $peer_stdout 1]]
                    error "Stage5-1: assertion:Peers not correctly synchronized"
                }
                set retry 500
                while {$retry} {
                    set info [[lindex $slaves 0] crdt.info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 50
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $slave_stdout 0]]
                    error "Stage5-2: assertion:Peers not correctly synchronized"
                }


                set load_handle1 [start_write_load_with_interval [lindex $slave_hosts 0] [lindex $slave_ports 0] 1 20]
                after 40

                set retry 500
                while {$retry} {
                    set info [[lindex $peers 1] info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 50
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $slave_stdout 3]]
                   # error "assertion:Slave3 not correctly synchronized"
                }
                test "Master-Slave-Switch Peer-Partial-Sync" {
                    set sync_partial_ok_now_0 [ crdt_status [lindex $slaves 0] "sync_partial_ok" ]
                    set sync_partial_ok_now_1 [ crdt_status [lindex $peers 1] "sync_partial_ok" ]

                    # puts [format "sync_full_0: %d" [crdt_status [lindex $slaves 0] "sync_full" ]]
                    # puts [format "sync_full_1: %d" [crdt_status [lindex $peers 1] "sync_full" ]]

                    set partil_incr_0 [expr $sync_partial_ok_now_0 - $sync_partial_ok_0]
                    set partil_incr_1 [expr $sync_partial_ok_now_1 - $sync_partial_ok_1]

                    assert_equal $partil_incr_0 1
                    assert_equal $partil_incr_1 1

                    ### insensitive the redis peer-repl state
                    [lindex $peers 0] config crdt.set repl-timeout 600
                    [lindex $peers 1] config crdt.set repl-timeout 600
                    [lindex $peers 0] debug set-crdt-ovc 0
                    [lindex $peers 1] debug set-crdt-ovc 0
                    after 1000
                    [lindex $slaves 0] debug set-crdt-ovc 0
                    [lindex $slaves 1] debug set-crdt-ovc 0

                    # Stop the write load
                    stop_write_load $load_handle0
                    stop_write_load $load_handle1
                }
                after 200

                test "Offset-Alignment Master-Slave-Switch Peer-Partial-Sync" {
                    # Make sure that slaves and master have same
                    # number of keys
                    wait_for_condition 500 100 {
                        [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                    wait_for_condition 500 100 {
                        [[lindex $peers 1] dbsize] == [[lindex $slaves 1] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                    wait_for_condition 500 100 {
                        [crdt_repl [lindex $slaves 0] master_repl_offset] == [crdt_repl [lindex $peers 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $slaves 0] master_repl_offset] == [crdt_repl [lindex $peers 0] master_repl_offset] &&
                        [crdt_repl [lindex $slaves 0] master_repl_offset] == [crdt_repl [lindex $slaves 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $peers 0] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 1] master_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 0] peer0_repl_offset]
                    } else {
                        puts [format "peer0 master-offset: %d" [crdt_repl [lindex $slaves 0] master_repl_offset]]
                        puts [format "slave0 master-offset: %d" [crdt_repl [lindex $peers 0] master_repl_offset]]
                        puts [format "peer1 offset: %d" [crdt_repl [lindex $peers 1] peer0_repl_offset]]
                        puts [format "slave1 offset: %d" [crdt_repl [lindex $slaves 1] peer0_repl_offset]]

                        puts [format "peer1 master-offset: %d" [crdt_repl [lindex $peers 1] master_repl_offset]]
                        puts [format "slave1 master-offset: %d" [crdt_repl [lindex $slaves 1] master_repl_offset]]
                        puts [format "peer0 offset: %d" [crdt_repl [lindex $slaves 0] peer0_repl_offset]]
                        puts [format "slave0 offset: %d" [crdt_repl [lindex $peers 0] peer0_repl_offset]]
                        fail "crdt repl offset not aligned."
                    }

                }

                test "VC-Alignment Master-Slave-Switch Peer-Partial-Sync" {
                    set peer_0_info [crdt_repl [lindex $peers 0] ovc]
                    set slave_0_info [crdt_repl [lindex $slaves 0] ovc]
                    set peer_1_info [crdt_repl [lindex $peers 1] ovc]
                    set slave_1_info [crdt_repl [lindex $slaves 1] ovc]
                    assert_equal $peer_0_info $slave_0_info
                    assert_equal $peer_1_info $slave_1_info
                    assert_equal $peer_0_info $slave_1_info
                    assert_equal $peer_1_info $slave_0_info
                    assert_equal $peer_0_info $peer_1_info
                }


                ####################################### Stage 6: Master-Slave Switch - Peer Full Sync######################################################
                puts "Stage 6: Master-Slave Switch - Peer Full Sync"
                set sync_full_0 [ crdt_status [lindex $peers 0] "sync_full" ]
                set sync_full_1 [ crdt_status [lindex $peers 1] "sync_full" ]

                set load_handle0 [start_write_load_with_interval [lindex $peer_hosts 1] [lindex $peer_ports 1] 1 100]

                [lindex $peers 0] slaveof no one
                [lindex $slaves 0] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]

                [lindex $peers 1] peerof 1 no one
                [lindex $peers 0] peerof 2 no one

                [lindex $peers 0] debug set-crdt-ovc 1
                [lindex $peers 1] debug set-crdt-ovc 1
                [lindex $slaves 0] debug set-crdt-ovc 1
                [lindex $slaves 1] debug set-crdt-ovc 1

                after 100

                [lindex $peers 0] peerof 2 [lindex $peer_hosts 1] [lindex $peer_ports 1]
                [lindex $peers 1] peerof 1 [lindex $peer_hosts 0] [lindex $peer_ports 0]

                set retry 500
                while {$retry} {
                    set info [[lindex $peers 1] crdt.info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $peer_stdout 1]]
                    error "Stage6-1: assertion:Peers not correctly synchronized"
                }
                set retry 500
                while {$retry} {
                    set info [[lindex $peers 0] crdt.info replication]
                    if {[string match {*slave0:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 50
                    }
                }
                if {$retry == 0} {
                    puts [log_content [lindex $peer_stdout 0]]
                    error "Stage6-2: assertion:Peers not correctly synchronized"
                }


                set load_handle1 [start_write_load_with_interval [lindex $peer_hosts 0] [lindex $peer_ports 0] 1 20]
                after 40


                test "Master-Slave-Switch Peer-Full-Sync" {
                    stop_write_load $load_handle0
                    stop_write_load $load_handle1

                    set sync_full_now_0 [ crdt_status [lindex $peers 0] "sync_full" ]
                    set sync_full_now_1 [ crdt_status [lindex $peers 1] "sync_full" ]

                    # puts [format "sync_full_0: %d" [crdt_status [lindex $slaves 0] "sync_full" ]]
                    # puts [format "sync_full_1: %d" [crdt_status [lindex $peers 1] "sync_full" ]]

                    set full_incr_0 [expr $sync_full_now_0 - $sync_full_0]
                    set full_incr_1 [expr $sync_full_now_1 - $sync_full_1]

                    assert_equal $full_incr_0 1
                    assert_equal $full_incr_1 1

                    ### insensitive the redis peer-repl state
                    [lindex $peers 0] config crdt.set repl-timeout 600
                    [lindex $peers 1] config crdt.set repl-timeout 600
                    [lindex $peers 0] debug set-crdt-ovc 0
                    [lindex $peers 1] debug set-crdt-ovc 0
                    after 1000
                    [lindex $slaves 0] debug set-crdt-ovc 0
                    [lindex $slaves 1] debug set-crdt-ovc 0
                }

                test "Offset-Alignment Master-Slave-Switch Peer-Full-Sync" {
                    # Make sure that slaves and master have same
                    # number of keys
                    wait_for_condition 500 100 {
                        [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                    wait_for_condition 500 100 {
                        [[lindex $peers 1] dbsize] == [[lindex $slaves 1] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                    wait_for_condition 500 100 {
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $peers 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 0] master_repl_offset] &&
                        [crdt_repl [lindex $peers 0] master_repl_offset] == [crdt_repl [lindex $slaves 1] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $peers 0] peer0_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 1] master_repl_offset] &&
                        [crdt_repl [lindex $peers 1] master_repl_offset] == [crdt_repl [lindex $slaves 0] peer0_repl_offset]
                    } else {
                        puts [format "peer0 master-offset: %d" [crdt_repl [lindex $slaves 0] master_repl_offset]]
                        puts [format "slave0 master-offset: %d" [crdt_repl [lindex $peers 0] master_repl_offset]]
                        puts [format "peer1 offset: %d" [crdt_repl [lindex $peers 1] peer0_repl_offset]]
                        puts [format "slave1 offset: %d" [crdt_repl [lindex $slaves 1] peer0_repl_offset]]

                        puts [format "peer1 master-offset: %d" [crdt_repl [lindex $peers 1] master_repl_offset]]
                        puts [format "slave1 master-offset: %d" [crdt_repl [lindex $slaves 1] master_repl_offset]]
                        puts [format "peer0 offset: %d" [crdt_repl [lindex $slaves 0] peer0_repl_offset]]
                        puts [format "slave0 offset: %d" [crdt_repl [lindex $peers 0] peer0_repl_offset]]
                        fail "crdt repl offset not aligned."
                    }

                }

                test "VC-Alignment Master-Slave-Switch Peer-Full-Sync" {
                    set peer_0_info [crdt_repl [lindex $peers 0] ovc]
                    set slave_0_info [crdt_repl [lindex $slaves 0] ovc]
                    set peer_1_info [crdt_repl [lindex $peers 1] ovc]
                    set slave_1_info [crdt_repl [lindex $slaves 1] ovc]
                    assert_equal $peer_0_info $slave_0_info
                    assert_equal $peer_1_info $slave_1_info
                    assert_equal $peer_0_info $slave_1_info
                    assert_equal $peer_1_info $slave_0_info
                    assert_equal $peer_0_info $peer_1_info
                }
            }
        }
    }
}