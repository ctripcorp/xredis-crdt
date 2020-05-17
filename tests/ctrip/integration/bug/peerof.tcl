proc write {host port} {
    set load_handle1 [start_write_load $host $port 3]
    set load_handle2 [start_write_load $host $port 5]
    set load_handle3 [start_write_load $host $port 20]
    set load_handle4 [start_write_load $host $port 8]
    set load_handle5 [start_write_load $host $port 4]
    after 5000
    stop_write_load $load_handle1
    stop_write_load $load_handle2
    stop_write_load $load_handle3
    stop_write_load $load_handle4
    stop_write_load $load_handle5
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

    # [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    # [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 1
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
    
        [lindex $peers 0] hset key field v0
        [lindex $peers 1] hset key field v1
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        after 3000
        assert {[[lindex $peers 0] ping] eq {PONG}}
        start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 2
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
        
            [lindex $peers 0] hset key field v0
            [lindex $peers 1] hset key field v1
            for {set i 0} {$i < 10} {incr i} {
                puts $i
                set k [expr $i%2]
                [lindex $peers 2] peerof [lindex $peer_gids  $k] [lindex $peer_hosts  $k] [lindex $peer_ports  $k]
                write [lindex $peer_hosts  $k] [lindex $peer_ports $k]
            }
            assert {[[lindex $peers 0] ping] eq {PONG}}
        }
    }
}
