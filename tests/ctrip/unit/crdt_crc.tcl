proc read_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
    # puts $content
}

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
start_server {tags {"crdt-crc1"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    set peer_config_file {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_config_file [srv 0 config_file]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-crc1.1"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_config_file [srv 0 config_file]
        lappend peer_gids 1
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 1] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
        wait [lindex $peers 0] 0 info [lindex $peer_stdouts 0]
        test "set crc" {
            [lindex $peers 0] crdt.crc set 1
            assert_equal [[lindex $peers 0] crdt.crc get] 1
            assert_equal [read_file_matches [lindex $peer_config_file 0] "*crdt-crc 1*"] 1
            after 1000
            assert_equal [[lindex $peers 1] crdt.crc get] 1
        }
        start_server {tags {"crdt-crc1.2"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_config_file [srv 0 config_file]
            lappend peer_gids 1
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            [lindex $peers 2] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 1 info [lindex $peer_stdouts 0]
            test "full-sync get crc" {
                assert_equal [[lindex $peers 2] crdt.crc get] 1
            }
        }
    }
}

start_server {tags {"crdt-crc2"} overrides {crdt-gid 1 crdt-crc 1} config {crdt.conf} module {crdt.so} } {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    set peer_config_file {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_config_file [srv 0 config_file]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    test "get crc" {
        assert_equal [[lindex $peers 0] crdt.crc get] 1
    }

    start_server {tags {"crdt-crc2"} overrides {crdt-gid 2 crdt-crc 2} config {crdt.conf} module {crdt.so}}  {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_config_file [srv 0 config_file]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        test "after peerof get crc" {
            [lindex $peers 1] set k v
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            after 5000
            set info [ [lindex $peers 1] crdt.info replication ]
            set match_str ""
            append match_str "*slave" 0 ":*state=online*"
            assert_equal [string match $match_str $info] 0
            assert_equal [[lindex $peers 0] get k] {}
            [lindex $peers 1] crdt.crc set 1
            assert_equal [[lindex $peers 1] crdt.crc get] [[lindex $peers 0] crdt.crc get] 
            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 0]
            assert_equal [[lindex $peers 0] get k] v
        }
        test "after peerof set crc" {
            catch {[lindex $peers 1] crdt.crc set 2} error
            assert_equal [[lindex $peers 1] crdt.crc get] 1
            [lindex $peers 0] peerof [lindex $peer_gids 1] no one
            [lindex $peers 1] crdt.crc set 2
            assert_equal [[lindex $peers 1] crdt.crc get] 2
        }
        test "second peerof set crc" {
            [lindex $peers 0] set k1 v
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            after 5000
            set info [ [lindex $peers 0] crdt.info replication ]    
            set match_str ""
            append match_str "*slave" 0 ":*state=online*"
            assert_equal [string match $match_str $info] 0
            assert_equal [[lindex $peers 1] get k1] {} 
            [lindex $peers 1] crdt.crc set 1
             assert_equal [[lindex $peers 1] crdt.crc get] [[lindex $peers 0] crdt.crc get] 
            wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
            assert_equal [[lindex $peers 1] get k1] v
        }

    }
}