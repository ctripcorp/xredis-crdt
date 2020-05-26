proc wait { client index}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client crdt.info replication ]
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
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}


set dl yes
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
        test "full sync hash and kv" {
            [lindex $peers 0] set key value
            [lindex $peers 1] hset key field value
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 0 
            wait [lindex $peers 1] 0 
            wait_for_condition 50 100 {
                [log_file_matches [lindex $peer_stdouts 0] "*local*"]
            } else {
                fail "master 0 no merge fail log"
            }
            assert {[[lindex $peers 0] get key] eq {value}}
            wait_for_condition 50 100 {
                [log_file_matches [lindex $peer_stdouts 1] "*local*"] 
            } else {
                fail "master 1 no merge fail log"
            }
            assert {[[lindex $peers 1] hget key field] eq {value}} 
        }
    }
}

set dl yes
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
        start_server {config {crdt.conf} overrides {crdt-gid 3 repl-diskless-sync-delay 1} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_gids 3
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            test "add sync hash and kv" {
                [lindex $peers 2] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                wait [lindex $peers 0] 0 
                wait [lindex $peers 1] 0 
                after 1000
                [lindex $peers 0] set key value
                [lindex $peers 1] hset key field value
                assert {[[lindex $peers 2] get key] eq {value}}
            }
        }
    }
}
