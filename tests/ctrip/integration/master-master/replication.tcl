proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so} } {
    set slave [srv 0 client]
    set slave_host [srv 0 host]
    set slave_port [srv 0 port]
    set slave_log [srv 0 stdout]
    set slave_gid 1
    test "gid" {
        set info [$slave crdt.info replication]
        assert_equal [string match "*gid:1*" $info] 1
    }
    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_gid 2

        # Configure the master in order to hang waiting for the BGSAVE
        # operation, so that the slave remains in the handshake state.
        $master config crdt.set repl-diskless-sync yes
        $master config crdt.set repl-diskless-sync-delay 1000

        # Use a short replication timeout on the slave, so that if there
        # are no bugs the timeout is triggered in a reasonable amount
        # of time.
        $slave config crdt.set repl-timeout 5

        # Start the replication process...
        $slave peerof $master_gid $master_host $master_port

        test {Slave enters handshake} {
            wait_for_condition 50 1000 {
                [string match *handshake* [$slave crdt.role slave $master_gid]]
            } else {
                fail "Slave does not enter handshake state"
            }
        }

        # But make the master unable to send
        # the periodic newlines to refresh the connection. The slave
        # should detect the timeout.
        $master debug sleep 10

        test {Slave is able to detect timeout during handshake} {
            wait_for_condition 50 1000 {
                [log_file_matches $slave_log "*Timeout connecting to the MASTER*"]
            } else {
                fail "Slave is not able to detect timeout"
            }
        }

    }
}



start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    set A [srv 0 client]
    set A_host [srv 0 host]
    set A_port [srv 0 port]
    set A_gid 1
    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        set B [srv 0 client]
        set B_host [srv 0 host]
        set B_port [srv 0 port]
        set B_gid 2

        $A config crdt.set repl-diskless-sync-delay 0
        $B config crdt.set repl-diskless-sync-delay 0

        set delay [lindex [$B config crdt.get repl-diskless-sync-delay] 1]
        assert { $delay eq 0 }

        test {Set instance A as slave of B} {
            $A peerof $B_gid $B_host $B_port
            after 1000
            wait_for_condition 50 100 {
                [string match {*peer0_link_status:up*} [$A crdt.info replication]]
            } else {
                fail "Can't turn the instance into a slave"
            }
        }
    }
}

start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so} } {
    r set mykey foo

    start_server { config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        test {Second server should have role master at first} {
            s role
        } {master}

        test {PEEROF should start with link status "down"} {
            r peerof 1 [srv -1 host] [srv -1 port]
            crdt_status r peer0_link_status
        } {down}

        wait_for_peer_sync r
        test {Sync should have transferred keys from master} {
            r get mykey
        } {foo}

        test {The link status should be up} {
            crdt_status r peer0_link_status
        } {up}

        test {SET on the master should immediately propagate} {
            r -1 set mykey bar

            wait_for_condition 500 100 {
                [r 0 get mykey] eq {bar}
            } else {
                fail "SET on master did not propagated on slave"
            }
        }


    }
}


set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    set master [srv 0 client]
    $master config set repl-diskless-sync $dl
    $master config crdt.set repl-diskless-sync $dl
    $master config crdt.set repl-diskless-sync-delay 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_gid  1
    set slaves {}
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $master_host $master_port 5]
    set load_handle2 [start_write_load $master_host $master_port 20]
    set load_handle3 [start_write_load $master_host $master_port 8]
    set load_handle4 [start_write_load $master_host $master_port 4]

    after 200
    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        lappend slaves [srv 0 client]
        start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {
            lappend slaves [srv 0 client]
            start_server {config {crdt.conf} overrides {crdt-gid 4} module {crdt.so}} {
                lappend slaves [srv 0 client]
                test "Connect multiple slaves at the same time (issue #141), diskless=$dl" {
                    # Send PEEROF commands to slaves
                    [lindex $slaves 0] peerof $master_gid $master_host $master_port
                    [lindex $slaves 1] peerof $master_gid $master_host $master_port
                    [lindex $slaves 2] peerof $master_gid $master_host $master_port

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    set retry 500
                    while {$retry} {
                        set info [r -3 crdt.info replication]
                        if {[string match {*slave0:*state=online*slave1:*state=online*slave2:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
                    if {$retry == 0} {
                        error "assertion:Slaves not correctly synchronized"
                    }

                    # Wait that slaves acknowledge they are online so
                    # we are sure that DBSIZE and DEBUG DIGEST will not
                    # fail because of timing issues.
                    puts [[lindex $slaves 2] crdt.role slave $master_gid]
                    wait_for_condition 500 100 {
                        [lindex [[lindex $slaves 0] crdt.role slave $master_gid] 3] eq {connected} &&
                        [lindex [[lindex $slaves 1] crdt.role slave $master_gid] 3] eq {connected} &&
                        [lindex [[lindex $slaves 2] crdt.role slave $master_gid] 3] eq {connected}
                    } else {
                        fail "Slaves still not connected after some time"
                    }

                    # Stop the write load
                    stop_write_load $load_handle0
                    stop_write_load $load_handle1
                    stop_write_load $load_handle2
                    stop_write_load $load_handle3
                    stop_write_load $load_handle4

                    # Make sure that slaves and master have same
                    # number of keys
                    wait_for_condition 500 100 {
                        [$master dbsize] == [[lindex $slaves 0] dbsize] &&
                        [$master dbsize] == [[lindex $slaves 1] dbsize] &&
                        [$master dbsize] == [[lindex $slaves 2] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                }
           }
        }
    }
}


