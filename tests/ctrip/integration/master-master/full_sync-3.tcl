
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


            [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1

            puts [format "A: %s%lld" {db size: } [[lindex $peers 0] dbsize]]
            puts [format "B: %s%lld" {db size: } [[lindex $peers 1] dbsize]]
            puts [format "C: %s%lld" {db size: } [[lindex $peers 2] dbsize]]

            test "sync request while del happend" {

                # Send PEEROF commands to all redis
                [lindex $peers 0] peerof [lindex $peer_gids 1]  [lindex $peer_hosts 1] [lindex $peer_ports 1]
                [lindex $peers 1] peerof [lindex $peer_gids 0]  [lindex $peer_hosts 0] [lindex $peer_ports 0]

                [lindex $peers 0] peerof [lindex $peer_gids 2]  [lindex $peer_hosts 2] [lindex $peer_ports 2]
                [lindex $peers 1] peerof [lindex $peer_gids 2]  [lindex $peer_hosts 2] [lindex $peer_ports 2]
                # Make sure that slaves and master have same
                # number of keys
                wait_for_condition 500 100 {
                    [[lindex $peers 0] dbsize] == [[lindex $peers 1] dbsize]
                } else {
                    fail "Different number of keys between masted and slave after too long time."
                }

                puts [format "A: %s%lld" {db size: } [[lindex $peers 0] dbsize]]
                puts [format "B: %s%lld" {db size: } [[lindex $peers 1] dbsize]]
                puts [format "C: %s%lld" {db size: } [[lindex $peers 2] dbsize]]

                [lindex $peers 0] config crdt.set repl-diskless-sync-delay 0
                [lindex $peers 1] config crdt.set repl-diskless-sync-delay 0

                # A: set k v
                [lindex $peers 0] set special-k v
                wait_for_condition 500 100 {
                    [[lindex $peers 1] get special-k] eq "v"
                } else {
                    fail "special k not propagated"
                }

                # C: sync with A/B
                # B: del k simultaneously
                [lindex $peers 2] peerof [lindex $peer_gids 0]  [lindex $peer_hosts 0] [lindex $peer_ports 0]
                after 1500
                [lindex $peers 1] del special-k
                [lindex $peers 2] peerof [lindex $peer_gids 1]  [lindex $peer_hosts 1] [lindex $peer_ports 1]

                # Wait that slaves acknowledge they are online so
                # we are sure that DBSIZE and DEBUG DIGEST will not
                # fail because of timing issues.
                wait_for_condition 500 100 {
                    [lindex [[lindex $peers 2] crdt.role slave [lindex $peer_gids 0]] 3] eq {connected}
                } else {
                    fail "C: Peer A still not connected after some time"
                }

                # Wait that slaves acknowledge they are online so
                # we are sure that DBSIZE and DEBUG DIGEST will not
                # fail because of timing issues.
                wait_for_condition 500 100 {
                    [lindex [[lindex $peers 2] crdt.role slave [lindex $peer_gids 1]] 3] eq {connected}
                } else {
                    fail "C: Peer B still not connected after some time"
                }

                # Make sure that slaves and master have same
                # number of keys
                wait_for_condition 500 100 {
                    [[lindex $peers 0] dbsize] <= [[lindex $peers 2] dbsize]
                } else {
                    fail "Different number of keys between masted and slave after too long time."
                }
                [lindex $peers 2] get special-k

            } {}

            puts [format "A: %s%lld" {db size: } [[lindex $peers 0] dbsize]]
            puts [format "B: %s%lld" {db size: } [[lindex $peers 1] dbsize]]
            puts [format "C: %s%lld" {db size: } [[lindex $peers 2] dbsize]]

        }
    }
}