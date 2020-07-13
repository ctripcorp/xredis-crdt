proc wait { client index type}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
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
proc wait_peer {client index} {
    set retry 50
    while {$retry} {
        set info [format "peer%d_link_status" $index]
        if {[crdt_status $client $info] eq "up"} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        assert_equal [$client ping ] PONG
        error "assertion: Master-Slave not correctly synchronized"
    }
    
}
proc wait_slave {client} {
    set retry 50
    while {$retry} {
        if {[status $client master_link_status] eq "up"} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        assert_equal [$client ping ] PONG
        error "assertion: Master-Slave not correctly synchronized"
    }
}
proc wait_load_rdb_over {client} {
    set retry 50
    while {$retry} {
        set a [catch { $client dbsize } error]
        if {$error == "LOADING Redis is loading the dataset in memory"} {
            incr retry -1
            after 100
        } else {
            break
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        # assert_equal [$client ping] PONG
        # log_file_matches $log
        $client dbsize
    }

}
#when hash merged, double free will cause the program to carsh
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
    [lindex $peers 0] crdt.set key val 1 1000 "1:10000000000000"
    for {set i 0} {$i < 100000} {incr i} {
        [lindex $peers 0] set $i $i
    }
    # [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    # [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 1
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 1] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
        # wait [lindex $peers 0] 0 info 
        wait_slave [lindex $peers 1] 
        wait_load_rdb_over [lindex $peers 1]
        for {set i 0} {$i < 100000} {incr i} {
            set info  [[lindex $peers 1] crdt.get $i ]
            assert_equal [lindex $info 0] $i
            assert_equal [lindex $info 1] 1
            
            assert_equal [lindex $info 3] [format "1:%d" [expr 10000000000001 + $i]]
            assert_equal [[lindex $peers 1] type $i] "crdt_regr"
        } 
        start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 2
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            # wait [lindex $peers 0] 0 crdt.info 
            wait_peer [lindex $peers 2] 0
            wait_load_rdb_over [lindex $peers 2]
            for {set i 0} {$i < 100000} {incr i} {
                set  info   [[lindex $peers 2] crdt.get $i]
                assert_equal [lindex $info 0] $i
                assert_equal [lindex $info 1] 1
                assert_equal [lindex $info 3] [format "1:%d" [expr 10000000000001 + $i]]
                # puts [[lindex $peers 2] crdt.get $i ]
                assert_equal [[lindex $peers 2] type $i] "crdt_regr"
            } 
        }
    }
}

