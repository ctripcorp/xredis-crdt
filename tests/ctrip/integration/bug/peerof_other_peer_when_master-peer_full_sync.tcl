proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc print_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait { client index type log}  {
    set retry 50
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
proc check-peer-offset {peers self index} {
    $peers debug set-crdt-ovc 0
    after 500
    assert_equal [crdt_status $peers master_repl_offset] [crdt_status $self [format "peer%s_repl_offset" $index]]
    $peers debug set-crdt-ovc 1
}

#before slaveof after peerof
start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_gids 2
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            test "peer add sync full" {
                [lindex $peers 1] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
                wait [lindex $peers 0] 0 info [lindex $peer_stdouts 0] 
                set load_handle0 [start_write_load [lindex $peer_hosts 0]  [lindex $peer_ports 0] 3]
                after 3000
                stop_write_load $load_handle0
                [lindex $peers 2] peerof [lindex $peer_gids 1]  [lindex $peer_hosts 1] [lindex $peer_ports 1]
                set retry 50
                while {$retry} {
                    if {[log_file_matches [lindex $peer_stdouts 2] "*crdtMergeStartCommand*"] == 1} {
                        break
                    } else {
                        assert_equal [[lindex $peers 2] ping] PONG
                        incr retry -1
                        after 100
                    }
                }
                if {$retry == 0} {
                    # error "assertion: Master-Slave not correctly synchronized"
                    assert_equal [[lindex $peers 2] ping] PONG
                    print_file_matches [lindex $peer_stdouts 2]
                    error "not start"
                }
                assert_equal [log_file_matches [lindex $peer_stdouts 2] "*crdtMergeEndCommand*"] 0
                [lindex $peers 2] peerof [lindex $peer_gids 0]  [lindex $peer_hosts 0] [lindex $peer_ports 0]
                wait_for_peer_sync [lindex $peers 2]
                puts [[lindex $peers 2] crdt.info replication]
                after 5000
                assert_equal [[lindex $peers 2] dbsize] [[lindex $peers 0] dbsize]
            }
        }
    }
}