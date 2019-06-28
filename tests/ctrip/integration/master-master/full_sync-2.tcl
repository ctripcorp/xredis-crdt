
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

proc write_batch_data {host port} {
    # Start to write random val(set k v). for 1 sec
    # the data will be used in full-sync
    set load_handle0 [start_write_load $host $port 3]
    set load_handle1 [start_write_load $host $port 5]
    set load_handle2 [start_write_load $host $port 20]
    set load_handle3 [start_write_load $host $port 8]
    set load_handle4 [start_write_load $host $port 4]

    after 1000
    # Stop the write load
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    stop_write_load $load_handle2
    stop_write_load $load_handle3
    stop_write_load $load_handle4
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

    write_batch_data [srv 0 host] [srv 0 port]

    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids  2
        write_batch_data [srv 0 host] [srv 0 port]


        start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids  3
            write_batch_data [srv 0 host] [srv 0 port]

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
            puts {db size}
            puts [[lindex $peers 0] dbsize]
        }
    }
}