
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc get_vector_clock { client } {
    set info [ $client {crdt.info} {replication} ]
    regexp {\r\novc:(.*?)\r\n} $info match clock 
    set _ $clock
}
proc get_client_num { client } {
    set lines [split [string trim [$client client list]] "\r\n"]
    set len [llength $lines]
    set _ $len
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
# Full synchronization process,
# updated crdtServer.vectorClock in advance,
# if synchronization fails,
# there will be omissions in the next synchronization data
# pull request: https://github.com/ctripcorp/xredis-crdt/pull/10
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1

        test "master->slave(close redis 6379)" {
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            assert_equal [get_client_num [lindex $peers 0]] 1
            wait [lindex $peers 1] 0 crdt.info
            assert_equal [get_client_num [lindex $peers 0]] 2
            [lindex $peers 0] slaveof 127.0.0.1 6379
            assert_equal [get_client_num [lindex $peers 0]] 1
        }
        test "slave->master" {
           [lindex $peers 0] slaveof no one 
           wait [lindex $peers 1] 0 crdt.info
           assert_equal [get_client_num [lindex $peers 0]] 2
        }
        test "peerof no one" {
           [lindex $peers 0] peerof [lindex $peer_gids 1] no one 
           assert_equal [get_client_num [lindex $peers 0]] 1
        }
    }
}