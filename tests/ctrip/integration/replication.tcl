proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set slave [srv 0 client]
    set slave_host [srv 0 host]
    set slave_port [srv 0 port]
    set slave_log [srv 0 stdout]
    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]

        # Configure the master in order to hang waiting for the BGSAVE
        # operation, so that the slave remains in the handshake state.
        $master config set repl-diskless-sync yes
        $master config set repl-diskless-sync-delay 1000

        # Use a short replication timeout on the slave, so that if there
        # are no bugs the timeout is triggered in a reasonable amount
        # of time.
        $slave config set repl-timeout 5

        # Start the replication process...
        $slave slaveof $master_host $master_port

        test {Slave enters handshake} {
            wait_for_condition 50 1000 {
                [string match *handshake* [$slave role]]
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

start_server {tags {"repl"} } {
    set A [srv 0 client]
    set A_host [srv 0 host]
    set A_port [srv 0 port]
    start_server {overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set B [srv 0 client]
        set B_host [srv 0 host]
        set B_port [srv 0 port]

        test {Set instance A as slave of B} {
            $A slaveof $B_host $B_port
            wait_for_condition 50 100 {
                [lindex [$A role] 0] eq {slave} &&
                [string match {*master_link_status:up*} [$A info replication]]
            } else {
                fail "Can't turn the instance into a slave"
            }
        }
    }
}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    r set mykey foo

    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        test {Second server should have role master at first} {
            s role
        } {master}

        test {SLAVEOF should start with link status "down"} {
            r slaveof [srv -1 host] [srv -1 port]
            s master_link_status
        } {down}

        test {The role should immediately be changed to "slave"} {
            s role
        } {slave}

        wait_for_sync r
        test {Sync should have transferred keys from master} {
            r get mykey
        } {foo}

        test {The link status should be up} {
            s master_link_status
        } {up}

        test {SET on the master should immediately propagate} {
            r -1 set mykey bar

            wait_for_condition 500 100 {
                [r  0 get mykey] eq {bar}
            } else {
                fail "SET on master did not propagated on slave"
            }
        }

        test {ROLE in master reports master with a slave} {
            set res [r -1 role]
            lassign $res role offset slaves
            assert {$role eq {master}}
            assert {$offset > 0}
            assert {[llength $slaves] == 1}
            lassign [lindex $slaves 0] master_host master_port slave_offset
            assert {$slave_offset <= $offset}
        }

        test {ROLE in slave reports slave in connected state} {
            set res [r role]
            lassign $res role master_host master_port slave_state slave_offset
            assert {$role eq {slave}}
            assert {$slave_state eq {connected}}
        }
    }
}


