start_server {tags {"crdt-gc"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    test {"[crdt_gc.tcl]gc"} {
        r set key-del val
        r del key-del
        set tombstoneSize [r tombstonesize]
        assert { $tombstoneSize eq 1 }
        # Make sure that all tombstone keys will be gc ed
        wait_for_condition 500 100 {
            [r tombstonesize] == 0
        } else {
            fail "Can't gc the tombstone keys"
        }
    }
}


start_server {tags {"gc"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
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

        test {Set instance A as peer of B} {
            $A peerof $B_gid $B_host $B_port
            after 1000
            wait_for_condition 1000 100 {
                [string match {*peer0_link_status:up*} [$A crdt.info replication]]
            } else {
                fail "Can't turn the instance into a slave"
            }
        }

        test {Set instance B as peer of A} {
            $B peerof $A_gid $A_host $A_port
            after 1000
            wait_for_condition 1000 100 {
                [string match {*peer0_link_status:*} [$A crdt.info replication]]
            } else {
                fail "Can't turn the instance into a slave"
            }
        }

        test {set in A} {
            $A set key val
            $A get key
        } {val}

        test {get in B} {
            wait_for_condition 1000 100 {
                [$B get key] eq {val}
            } else {
                fail "Can't turn the instance into a slave"
            }
        }

        test {del in B} {
            $B del key
            $B get key
        } {}

        test {also del in A} {
            wait_for_condition 1000 100 {
                [$A get key] eq {}
            } else {
                fail "Can't propagate the del to A"
            }
        }

        $B set key val2

        test {gc in B} {
            wait_for_condition 1000 100 {
                [$B tombstonesize] eq 0
            } else {
                fail "source(B) not gc the tombstone"
            }
        }

        after 500
        test {also gc in A} {
            wait_for_condition 1000 100 {
                [$A tombstonesize] eq 0
            } else {
                fail "other(A) not gc the tombstone"
            }
        }
    }
}

set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids  1

    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids  2


        start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids  3

            [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1

            test "3 peers connect each other at the same time" {
                # Send PEEROF commands to all redis
                [lindex $peers 0] peerof [lindex $peer_gids 1]  [lindex $peer_hosts 1] [lindex $peer_ports 1]
                [lindex $peers 0] peerof [lindex $peer_gids 2]  [lindex $peer_hosts 2] [lindex $peer_ports 2]

                [lindex $peers 1] peerof [lindex $peer_gids 0]  [lindex $peer_hosts 0] [lindex $peer_ports 0]
                [lindex $peers 1] peerof [lindex $peer_gids 2]  [lindex $peer_hosts 2] [lindex $peer_ports 2]

                [lindex $peers 2] peerof [lindex $peer_gids 0]  [lindex $peer_hosts 0] [lindex $peer_ports 0]
                [lindex $peers 2] peerof [lindex $peer_gids 1]  [lindex $peer_hosts 1] [lindex $peer_ports 1]

                # Wait for all the three redis to reach the "online"
                # state from the POV of the master.
                set retry 500
                while {$retry} {
                    set info [r -2 crdt.info replication]
                    if {[string match {*slave0:*state=online*slave1:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    error "assertion:Slaves not correctly synchronized"
                }

                set retry 500
                while {$retry} {
                    set info [r -1 crdt.info replication]
                    if {[string match {*slave0:*state=online*slave1:*state=online*} $info]} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    error "assertion:Slaves not correctly synchronized"
                }

                set retry 500
                while {$retry} {
                    set info [r crdt.info replication]
                    if {[string match {*slave0:*state=online*slave1:*state=online*} $info]} {
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
                wait_for_condition 500 100 {
                    [lindex [[lindex $peers 0] crdt.role slave [lindex $peer_gids 1]] 3] eq {connected} &&
                    [lindex [[lindex $peers 1] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected} &&
                    [lindex [[lindex $peers 2] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected}
                } else {
                    fail "Peers still not connected after some time"
                }

            }

            test "All Redis Share the same keys" {
                # Make sure that slaves and master have same
                # number of keys
                wait_for_condition 500 100 {
                    [[lindex $peers 0] dbsize] == [[lindex $peers 1] dbsize] &&
                    [[lindex $peers 0] dbsize] == [[lindex $peers 2] dbsize] &&
                    [[lindex $peers 1] dbsize] == [[lindex $peers 2] dbsize]
                } else {
                    fail "Different number of keys between masted and slave after too long time."
                }
            }

            test "GC in all redis" {
                [lindex $peers 0] set key-peer-1 val-1
                [lindex $peers 1] set key-peer-2 val-2
                [lindex $peers 2] del key-peer-1 key-peer-2
                # make sure all deleted keys went into tombstone
                wait_for_condition 500 100 {
                    [[lindex $peers 0] tombstonesize] == 2 ||
                    [[lindex $peers 1] tombstonesize] == 2 ||
                    [[lindex $peers 2] tombstonesize] == 2
                } else {
                    fail "Gc not happend in all redis"
                }

                # update the vector clock
                [lindex $peers 2] set hello world
                wait_for_condition 500 100 {
                    [[lindex $peers 0] tombstonesize] == 0 &&
                    [[lindex $peers 1] tombstonesize] == 0 &&
                    [[lindex $peers 2] tombstonesize] == 0
                } else {
                    fail "Gc not happend in all redis"
                }
            }
        }
    }
}