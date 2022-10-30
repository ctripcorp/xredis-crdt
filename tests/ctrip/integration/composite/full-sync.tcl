
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}


set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {

    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}

    set slaves {}
    set slave_hosts {}
    set slave_ports {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids 1

    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1

    # Start to write random val(set k v and hmset and hset). for 5 sec
    # the data will be used in full-sync
    set load_handle0 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 3]
    set load_handle1 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 5]
    set load_handle2 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 20]
    set load_handle3 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 8]
    set load_handle4 [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 4]

    start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        lappend slaves [srv 0 client]
        lappend slave_hosts [srv 0 host]
        lappend slave_ports [srv 0 port]

        [lindex $slaves 0] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]

        after 500
        # Stop the write load
        stop_write_load $load_handle0
        stop_write_load $load_handle1
        stop_write_load $load_handle2
        stop_write_load $load_handle3
        stop_write_load $load_handle4

        after 1000
        # puts [format "%s: %d" {master1 key numbers} [[lindex $peers 0] dbsize]]
        # puts [format "%s: %d" {slave1 key numberss} [[lindex $slaves 0] dbsize]]
        wait_for_sync [lindex $slaves 0]
        start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 2

            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1

            # Start to write random val(set k v and hmset and hset). for 5 sec
            # the data will be used in full-sync
            set load_handle5 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 3]
            set load_handle6 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 5]
            set load_handle7 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 20]
            set load_handle8 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 8]
            set load_handle9 [start_write_load [lindex $peer_hosts 1] [lindex $peer_ports 1] 4]

            start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {

                lappend slaves [srv 0 client]
                lappend slave_hosts [srv 0 host]
                lappend slave_ports [srv 0 port]

                [lindex $slaves 1] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]

                after 500
                # Stop the write load
                stop_write_load $load_handle5
                stop_write_load $load_handle6
                stop_write_load $load_handle7
                stop_write_load $load_handle8
                stop_write_load $load_handle9

                after 1000
                # puts [format "%s: %d" {master2 key numbers} [[lindex $peers 1] dbsize]]
                # puts [format "%s: %d" {slave2 key numberss} [[lindex $slaves 1] dbsize]]
                wait_for_sync [lindex $slaves 1]
                test "TEST Master-Master + Master-Slave works together" {
                    # Send PEEROF commands to peers
                    [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                    [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    wait_for_peer_sync [lindex $peers 0]
                    wait_for_peer_sync [lindex $peers 1]
                    

                    # Wait that slaves acknowledge they are online so
                    # we are sure that DBSIZE and DEBUG DIGEST will not
                    # fail because of timing issues.
                    wait_for_condition 500 100 {
                        [lindex [[lindex $peers 0] crdt.role slave [lindex $peer_gids 1]] 3] eq {connected} &&
                        [lindex [[lindex $peers 1] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected}
                    } else {
                        fail "Peers still not connected after some time"
                    }


                    # puts [format "%s: %d" {master1 key numbers} [[lindex $peers 0] dbsize]]
                    # puts [format "%s: %d" {slave2 key numbers} [[lindex $slaves 1] dbsize]]
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

                # puts [format "%s: %d" {master1 key numbers} [[lindex $peers 0] dbsize]]
                # puts [format "%s: %d" {slave1 key numbers} [[lindex $slaves 0] dbsize]]
                # puts [format "%s: %d" {master2 key numbers} [[lindex $peers 1] dbsize]]
                # puts [format "%s: %d" {slave2 key numbers} [[lindex $slaves 1] dbsize]]


                start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {
                    lappend peers [srv 0 client]
                    lappend peer_hosts [srv 0 host]
                    lappend peer_ports [srv 0 port]
                    lappend peer_gids 3

                    [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
                    [lindex $peers 2] config set repl-diskless-sync-delay 1

                    # Start to write random val(set k v and hmset and hset). for 5 sec
                    # the data will be used in full-sync
                    set load_handle10 [start_write_load [lindex $peer_hosts 2] [lindex $peer_ports 2] 3]
                    set load_handle11 [start_write_load [lindex $peer_hosts 2] [lindex $peer_ports 2] 5]
                    set load_handle12 [start_write_load [lindex $peer_hosts 2] [lindex $peer_ports 2] 20]
                    set load_handle13 [start_write_load [lindex $peer_hosts 2] [lindex $peer_ports 2] 8]
                    set load_handle14 [start_write_load [lindex $peer_hosts 2] [lindex $peer_ports 2] 4]


                    start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {

                        lappend slaves [srv 0 client]
                        lappend slave_hosts [srv 0 host]
                        lappend slave_ports [srv 0 port]

                        [lindex $slaves 2] slaveof [lindex $peer_hosts 2] [lindex $peer_ports 2]

                        after 500
                        # Stop the write load
                        stop_write_load $load_handle10
                        stop_write_load $load_handle11
                        stop_write_load $load_handle12
                        stop_write_load $load_handle13
                        stop_write_load $load_handle14

                        after 1000
                        set retry 500
                        while {$retry} {
                            set info [[lindex $peers 2] info replication]
                            if {[string match {*slave0:*state=online*} $info]} {
                                break
                            } else {
                                incr retry -1
                                after 100
                            }
                        }
                        while {$retry} {
                            set info [[lindex $slaves 2] info replication]
                            if {[string match {*master_link_status:up*} $info]} {
                                break
                            } else {
                                incr retry -1
                                after 100
                            }
                        }
                        if {$retry == 0} {
                            error "assertion:Slave 3 not correctly synchronized"
                        }

                        # puts [format "%s: %d" {master3 key numbers} [[lindex $peers 2] dbsize]]
                        # puts [format "%s: %d" {slave3 key numbers} [[lindex $slaves 2] dbsize]]

                        test "TEST Third Redis Join" {
                            # Send PEEROF commands to peers
                            [lindex $peers 0] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]
                            [lindex $peers 1] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]
                            [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                            [lindex $peers 2] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]

                            # Wait for all the three slaves to reach the "online"
                            # state from the POV of the master.
                            set retry 500
                            while {$retry} {
                                set info [[lindex $peers 2] crdt.info replication]
                                if {[string match {*slave0:*state=online*} $info]} {
                                    break
                                } else {
                                    incr retry -1
                                    after 100
                                }
                            }
                            set retry 500
                            while {$retry} {
                                set info [[lindex $peers 2] crdt.info replication]
                                if {[string match {*slave0:*state=online*} $info]} {
                                    break
                                } else {
                                    incr retry -1
                                    after 100
                                }
                            }
                            if {$retry == 0} {
                                error "assertion:Peers not correctly synchronized"
                            }

                            # Wait that slaves acknowledge they are online so
                            # we are sure that DBSIZE and DEBUG DIGEST will not
                            # fail because of timing issues.
                            wait_for_condition 500 100 {
                                [lindex [[lindex $peers 2] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected} &&
                                [lindex [[lindex $peers 2] crdt.role slave [lindex $peer_gids 1]] 3] eq {connected} &&
                                [lindex [[lindex $peers 0] crdt.role slave [lindex $peer_gids 2]] 3] eq {connected} &&
                                [lindex [[lindex $peers 1] crdt.role slave [lindex $peer_gids 2]] 3] eq {connected}
                            } else {
                                fail "Peers still not connected after some time"
                            }

                            # puts [format "%s: %d" {master1 key numbers} [[lindex $peers 0] dbsize]]
                            # puts [format "%s: %d" {slave1 key numbers} [[lindex $slaves 0] dbsize]]
                            # puts [format "%s: %d" {master2 key numbers} [[lindex $peers 1] dbsize]]
                            # puts [format "%s: %d" {slave2 key numbers} [[lindex $slaves 1] dbsize]]
                            # puts [format "%s: %d" {master3 key numbers} [[lindex $peers 2] dbsize]]
                            # puts [format "%s: %d" {slave3 key numbers} [[lindex $slaves 2] dbsize]]

                            # Make sure that slaves and master have same
                            # number of keys
                            wait_for_condition 500 100 {
                                [[lindex $peers 0] dbsize] == [[lindex $slaves 2] dbsize] &&
                                [[lindex $peers 1] dbsize] == [[lindex $slaves 2] dbsize] &&
                                [[lindex $peers 2] dbsize] == [[lindex $slaves 2] dbsize] &&
                                [[lindex $peers 0] dbsize] == [[lindex $slaves 0] dbsize] &&
                                [[lindex $peers 1] dbsize] == [[lindex $slaves 0] dbsize] &&
                                [[lindex $peers 2] dbsize] == [[lindex $slaves 0] dbsize] &&
                                [[lindex $peers 0] dbsize] == [[lindex $slaves 1] dbsize] &&
                                [[lindex $peers 1] dbsize] == [[lindex $slaves 1] dbsize] &&
                                [[lindex $peers 2] dbsize] == [[lindex $slaves 1] dbsize]
                            } else {
                                fail "Different number of keys between masted and slave after too long time."
                            }

                        }

                        test "sync full should eq to 1" {
                            set sync_count_1 [status [lindex $peers 0] sync_full]
                            set sync_count_2 [status [lindex $peers 1] sync_full]
                            set sync_count_3 [status [lindex $peers 2] sync_full]

                            assert {$sync_count_1 eq 1}
                            assert {$sync_count_2 eq 1}
                            assert {$sync_count_3 eq 1}
                        }

                    }
                }
            }
        }
    }
}