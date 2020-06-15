
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
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
        wait [lindex $peers 1] 0 crdt.info
        wait [lindex $peers 0] 0 crdt.info
        test "mset" {
            [lindex $peers 0] mset k v k1 v2
            [lindex $peers 0] mset a 1 b 2 c 3 d 4 c 5 e 6 f 7 g 8 h 9 i 10 l 11 m 12 n 13 o 14 p 15 q 16
            after 1000
            assert_equal [[lindex $peers 1] get k ] v
            assert_equal [[lindex $peers 1] get k1 ] v2
            assert_equal [[lindex $peers 1] mget a b c d e f g h i l m n o p q] {1 2 5 4 6 7 8 9 10 11 12 13 14 15 16}
        }
        
    }
}