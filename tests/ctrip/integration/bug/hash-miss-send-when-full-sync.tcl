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
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        
        [lindex $peers 1] hset key f1 v1
        [lindex $peers 1] crdt.hset key 3 [clock milliseconds] "3:1;1:2" 2 f2 v2
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        wait [lindex $peers 1] 0 crdt.info
        assert_equal [[lindex $peers 0] hget key f1] v1
        
    }
}
