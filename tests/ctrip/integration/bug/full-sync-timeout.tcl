    proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {

    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}

    set slaves {}
    set slave_hosts {}
    set slave_ports {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids 1

    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    set load_handle [start_write_load [lindex $peer_hosts 0] [lindex $peer_ports 0] 10]
    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 1] config crdt.set repl-timeout 2
        after 10000
        stop_write_load $load_handle
        test "timeout" {
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait_for_condition 500 200 {
                [[lindex $peers 0] dbsize] == [[lindex $peers 1] dbsize]
            } else {
                puts [[lindex $peers 0] dbsize]
                puts [[lindex $peers 1] dbsize]
                fail "Peers still not connected after some time"
            }
        }
    }
}