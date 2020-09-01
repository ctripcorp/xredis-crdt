# #107: https://github.com/ctripcorp/xredis-crdt/issues/107
proc print_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

proc wait_peer {client index} {
    set retry 50
    while {$retry} {
        set info [format "peer%d_link_status" $index]
        if {[crdt_repl $client $info] eq "up"} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        assert_equal [$client ping ] PONG
        error "assertion: peer not correctly synchronized"
    }

}

start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1

    set big_timestamp [expr [clock microseconds] + 20000]
    [lindex $peers 0] crdt.set key val1 1 $big_timestamp "1:1" -1

    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1

        # make sure A's timestamp is smaller than B
        set big_timestamp [expr [clock microseconds] + 21000]
        [lindex $peers 1] crdt.set key val2 2 $big_timestamp "2:1" -1

        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        wait_peer [lindex $peers 0] 0

        [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
        wait_peer [lindex $peers 1] 0

        test "peer full sync meta data might lose" {
            set info0 [[lindex $peers 0] crdt.get key ]
            set info1 [[lindex $peers 1] crdt.get key ]

            assert_equal [lindex $info0 0] [lindex $info1 0]
            assert_equal [lindex $info0 1] [lindex $info1 1]
            assert_equal [lindex $info0 2] [lindex $info1 2]
            assert_equal [lindex $info0 3] [lindex $info1 3]

        }

        start_server {config {crdt.conf} overrides {crdt-gid 3 repl-diskless-sync-delay 1} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 3
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            [lindex $peers 2] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]

            [lindex $peers 0] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]
            [lindex $peers 1] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]

            wait_peer [lindex $peers 2] 0
            wait_peer [lindex $peers 2] 1

            wait_peer [lindex $peers 0] 1
            wait_peer [lindex $peers 1] 1

            test "third node join, then data in-consist" {
                # now data should be val2, and its corresponding timestamp
                # we need to mock a client input as well as node-C timestmap is much more smaller
                [lindex $peers 2] set key val3

                assert_equal [[lindex $peers 0] get key ] [[lindex $peers 1] get key ]
                assert_equal [[lindex $peers 0] get key ] [[lindex $peers 2] get key ]

                set retry 50
                while {$retry} {
                    set val0 [[lindex $peers 0] get key]
                    set val1 [[lindex $peers 1] get key ]
                    set val2 [[lindex $peers 2] get key ]
                    if {$val0 eq $val1 && $val1 eq $val2} {
                        break
                    } else {
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    puts [[lindex $peers 0] get key]
                    puts [[lindex $peers 1] get key ]
                    puts [[lindex $peers 2] get key ]
                    error "data in-consist"
                }
            }
        }
    }
}