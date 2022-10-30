
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

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

    start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        lappend slaves [srv 0 client]
        lappend slave_hosts [srv 0 host]
        lappend slave_ports [srv 0 port]

        [lindex $slaves 0] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]

        after 1000

        set conflict_num [randomInt 10000]
        set key_set [gen_key_set $conflict_num]
        wait_for_sync [lindex $slaves 0]
        test "test first master-slave ready" {

            # Wait for all the three slaves to reach the "online"
            # state from the POV of the master.
            set retry 500
            while {$retry} {
                set info [[lindex $peers 0] info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion: Master-Slave not correctly synchronized"
            }
        }

        set counter 0
        set redis_master [lindex $peers 0]
        foreach key $key_set {
            if {[r get $key] ne ""} {
                incr counter
            }
            $redis_master set $key [randstring 10 1024 alpha]
            if {[$redis_master get $key] eq ""} {
                error [format "key is nil: %s" $key]
            }
        }

        # puts [format "duplicate counter: %s" $counter]

        foreach key $key_set {
            if {[$redis_master get $key] eq ""} {
                error [format "key not exist: %s" $key]
            }
        }

        set conflict_num [[lindex $peers 0] dbsize]

        # puts [format "first pair, master: %d; slave: %d" [[lindex $peers 0] dbsize] [[lindex $slaves 0] dbsize]]

        start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 2

            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1

            start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {

                lappend slaves [srv 0 client]
                lappend slave_hosts [srv 0 host]
                lappend slave_ports [srv 0 port]

                [lindex $slaves 1] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]

                after 1000
                foreach key $key_set {
                    [lindex $peers 1] set $key [randstring 10 1024 alpha]
                }
                 wait_for_sync [lindex $slaves 1]
                test "test second master-slave ready" {

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    set retry 500
                    while {$retry} {
                        set info [[lindex $peers 0] info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
                    if {$retry == 0} {
                        error "assertion: Master-Slave not correctly synchronized"
                    }
                }
                # puts [format "second pair, master: %d; slave: %d" [[lindex $peers 1] dbsize] [[lindex $slaves 1] dbsize]]

                test "master-slave + master-slave composite" {
                    # Send PEEROF commands to peers
                    [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                    [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    wait_for_peer_sync [lindex $peers 0]
                    wait_for_peer_sync [lindex $peers 1]
                    set retry 500
                    while {$retry} {
                        set info [[lindex $peers 0] crdt.info replication]
                        if {[string match {*slave0:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
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
                test "concurrent conflict when full sync" {
                    set db_size [[lindex $slaves 1] dbsize]
                    assert {$conflict_num eq $db_size}
                }


                start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {
                    lappend peers [srv 0 client]
                    lappend peer_hosts [srv 0 host]
                    lappend peer_ports [srv 0 port]
                    lappend peer_gids 3

                    [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
                    [lindex $peers 2] config set repl-diskless-sync-delay 1

                    start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {

                        lappend slaves [srv 0 client]
                        lappend slave_hosts [srv 0 host]
                        lappend slave_ports [srv 0 port]

                        [lindex $slaves 2] slaveof [lindex $peer_hosts 2] [lindex $peer_ports 2]

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

                        foreach key $key_set {
                            [lindex $peers 2] set $key [randstring 10 1024 alpha]
                        }

                        # puts [format "third pair, master: %d; slave: %d" [[lindex $peers 2] dbsize] [[lindex $slaves 2] dbsize]]


                        test "test three redis pairs become peers" {
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

                        test "test three pairs concurrent conflict" {
                            # puts [format "conflict num: %d" $conflict_num]
                            set db_size [[lindex $slaves 1] dbsize]
                            # puts [format "db size: %d" $db_size]
                            assert {$conflict_num == $db_size}
                            set db_size [[lindex $slaves 2] dbsize]
                            assert {$conflict_num == $db_size}
                        }

                    }
                }
            }
        }
    }
}