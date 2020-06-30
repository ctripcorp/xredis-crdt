
proc log_file_matches {log} {
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
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        log_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
start_server {tags {"crdt-namespace1"} overrides {crdt-gid  1} config {crdt.conf} module {crdt.so} namespace "xredis"} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    set peer_config_file {}
    set peer_namespace {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_config_file [srv 0 config_file]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    test "set namespace" {
        [lindex $peers 0] config crdt.set crdt-gid "test"
        assert_equal [lindex [[lindex $peers 0] config crdt.get crdt-gid] 1]  "test 1"
        [lindex $peers 0] config crdt.set crdt-gid "xredis" 
        assert_equal [lindex [[lindex $peers 0] config crdt.get crdt-gid] 1]  "xredis 1"
    }
    start_server {tags {"crdt-namespace2"} overrides {crdt-gid 2 } config {crdt.conf} module {crdt.so} namespace }  {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_config_file [srv 0 config_file]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        test "after peerof get namepsace" {
            [lindex $peers 1] set k v
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            after 5000
            set info [ [lindex $peers 1] crdt.info replication ]
            set match_str ""
            append match_str "*slave" 0 ":*state=online*"
            assert_equal [string match $match_str $info] 0
            assert_equal [[lindex $peers 0] get k] {}
            [lindex $peers 1] config crdt.set crdt-gid "xredis"
            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 0]
            assert_equal [[lindex $peers 0] get k] v
        }
        
    
        start_server {tags {"crdt-slave"} overrides {crdt-gid  2 } config {crdt.conf} module {crdt.so}}  {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_config_file [srv 0 config_file]
            set slave_gid 2
            $slave slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
            after 5000
            set info [ [lindex $peers 0] info replication ]    
            set match_str ""
            append match_str "*slave" 0 ":*state=online*"
            assert_equal [string match $match_str $info] 0
            
        }
        start_server {tags {"crdt-slave2"} overrides {crdt-gid  1} config {crdt.conf} module {crdt.so}}  {
            set slave2 [srv 0 client]
            set slave2_host [srv 0 host]
            set slave2_port [srv 0 port]
            set slave2_stdout [srv 0 stdout]
            set slave2_config_file [srv 0 config_file]
            set slave2_gid 1
            $slave2 slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 0 info $slave2_stdout
            assert {[$slave2 config crdt.get crdt-gid] != [[lindex $peers 0] config crdt.get crdt-gid]}
        }
        
    }
}

