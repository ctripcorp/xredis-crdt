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
            start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_stdouts [srv 0 stdout]
                lappend peer_gids 2
                [lindex $peers 3] config set repl-diskless-sync-delay 1
                [lindex $peers 3] config crdt.set repl-diskless-sync-delay 1
                test "peer add sync full" {
                    [lindex $peers 3] slaveof [lindex $peer_hosts 2] [lindex $peer_ports 2]
                    [lindex $peers 1] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
                    wait [lindex $peers 0] 0 info [lindex $peer_stdouts 0]
                    wait [lindex $peers 2] 0 info [lindex $peer_stdouts 2]
                    
                    [lindex $peers 2] set k v
                    [lindex $peers 0] peerof [lindex $peer_gids 3] [lindex $peer_hosts 3] [lindex $peer_ports 3]
                    wait [lindex $peers 3] 0 crdt.info [lindex $peer_stdouts 3]
                    assert_equal [crdt_stats [lindex $peers 3] sync_full] 1
                    after 1000
                    
                    assert_equal [[lindex $peers 0] get k]  v
                    [lindex $peers 2] slaveof [lindex $peer_hosts 3] [lindex $peer_ports 3]
                    [lindex $peers 3] slaveof no one
                    [lindex $peers 3] set k v1
                    wait [lindex $peers 3] 0 crdt.info [lindex $peer_stdouts 3]
                    assert_equal [[lindex $peers 0] get k] v1
                    check_peer_info  [lindex $peers 3] [lindex $peers 1] 0
                    [lindex $peers 0] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]
                    [lindex $peers 3] set k v2
                    [lindex $peers 1] slaveof no one
                    
                    wait [lindex $peers 3] 0 crdt.info [lindex $peer_stdouts 3]
                    
                    check_peer_info  [lindex $peers 3] [lindex $peers 1] 0
                    after 1000
                    assert_equal [[lindex $peers 1] get k] v2 
                    assert_equal [[lindex $peers 0] get k] v2 
                    assert_equal [[lindex $peers 2] get k] v2 
                    # print_file_matches [lindex $peer_stdouts 1]
                    # print_file_matches [lindex $peer_stdouts 3]
                    assert_equal [crdt_stats [lindex $peers 3] sync_full] 1
                    check_peer_info  [lindex $peers 3] [lindex $peers 1] 0
                }
            }
        }
    }
}