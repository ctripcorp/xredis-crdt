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
proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
#when hash merged, double free will cause the program to carsh
start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdout {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdout [srv 0 stdout]
    lappend peer_gids 1

    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        lappend peer_stdout [srv 0 stdout]
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        start_server {config {crdt.conf} overrides {crdt-gid 3 repl-diskless-sync-delay 1} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 3
            lappend peer_stdout [srv 0 stdout]
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            [lindex $peers 1] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]
            wait [lindex $peers 2] 0 crdt.info
            test "value" {
                set time [clock milliseconds]
                [lindex $peers 1] hset key f1 v1
                [lindex $peers 1] crdt.hset key 3 $time "3:1;1:2" 2 f1 v2
                [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                wait [lindex $peers 1] 0 crdt.info
                # print_log_file [lindex $peer_stdout 0]
                assert_equal [[lindex $peers 0] hget key f1] v1
            }
            test "tombstone" {
                [lindex $peers 0] peerof [lindex $peer_gids 1] no one
                after 100
                [lindex $peers 1] crdt.rem_hash key 1 [clock milliseconds] "3:2;1:3" f1
                assert_equal [[lindex $peers 1] hget key f1] {}
                [lindex $peers 1] crdt.rem_hash key 3 [clock milliseconds] "3:3;1:3;4:1" f2
                [lindex $peers 1] crdt.hset key 1 100000 {1:1} 2 f2 v2
                # print_log_file [lindex $peer_stdout 1] 
                assert_equal [[lindex $peers 1] hget key f2] {}
                assert_equal [[lindex $peers 1] dbsize] 0
                [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                wait [lindex $peers 1] 0 crdt.info
                assert_equal [[lindex $peers 0] hget key f2] {}
            }
        }
    }
}
