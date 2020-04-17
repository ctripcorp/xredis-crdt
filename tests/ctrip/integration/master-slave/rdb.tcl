
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
            assert_equal [$client ping] PONG
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        assert_equal [$client ping] PONG
        log_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
proc wait_save { client log}  {
    set retry 50
    append match_str1 "*rdb_bgsave_in_progress:0*"
    append match_str2 "*rdb_last_bgsave_status:ok*"
    while {$retry} {
        set info [ $client info persistence ]
        if {[string match $match_str1 $info]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        puts [ $client info persistence ]
        error "assertion: Master-Slave not correctly synchronized"
    }
    set info [ $client info persistence ]
    if {![string match $match_str2 $info]} {
        log_file_matches $log
        error "save fail"
    } 
}
set server_path [tmpdir "server.rdb-encoding-test"]

# Copy RDB with different encodings in server path
# exec cp tests/assets/encodings.rdb $server_path
exec cp tests/assets/crdt.so $server_path
start_server [list overrides [list crdt-gid 1 loadmodule crdt.so  "dir"  $server_path "dbfilename" "encodings.rdb"]] {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    [lindex $peers 0] debug set-crdt-ovc 0
    start_server {tags {"save"} overrides {crdt-gid 2} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2
        
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
        wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
        wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
        [lindex $peers 1] debug set-crdt-ovc 0
        test "set" {
            [lindex $peers 0] set save-kv1 value
            [lindex $peers 0] hset save-hash1 key value
            assert_equal [[lindex $peers 0] get save-kv1] value
            assert_equal [[lindex $peers 0] hget save-hash1 key] value
        }
        set time [clock milliseconds]
        test "expire" {
            [lindex $peers 0] set save-kv2 10000000
            assert {[[lindex $peers 0] ttl save-kv2] < 10000000}
        }
        test "del" {
            [lindex $peers 0] crdt.set save-kv10 value 1 $time "1:100"
            [lindex $peers 0] crdt.del_reg save-kv10 2 $time "1:100;2:100"
        }
        test "delexpire" {
            [lindex $peers 0] crdt.set save-kv11 value 1 $time "1:100"
            [lindex $peers 0] crdt.expire save-kv11 3 $time "1:100;3:100" [expr $time + 1000000] 1
            [lindex $peers 0] crdt.persist save-kv11 3 $time "1:100;3:101" 1
            assert_equal [[lindex $peers 0] expiretombstonesize] 1
        }
        
        test "bgsave" {
            [lindex $peers 0] bgsave
            wait_save  [lindex $peers 0] [lindex $peer_stdouts 0]
            assert_equal [[lindex $peers 0] tombstonesize] 1
            assert_equal [[lindex $peers 0] expiretombstonesize] 1
        }
        test "reload" {
            [lindex $peers 0] debug reload
            assert_equal [[lindex $peers 0] get save-kv1] value
            assert_equal [[lindex $peers 0] hget save-hash1 key] value
            assert {[[lindex $peers 0] ttl save-kv2] < 10000000}
            assert_equal [[lindex $peers 0] tombstonesize] 1
            assert_equal [[lindex $peers 0] expiretombstonesize] 1
        }
    }
}
start_server [list overrides [list crdt-gid 1 loadmodule crdt.so  "dir"  $server_path "dbfilename" "encodings.rdb"]] {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    [lindex $peers 0] debug set-crdt-ovc 0
    test "load" {
        assert_equal [[lindex $peers 0] get save-kv1] value
        assert_equal [[lindex $peers 0] hget save-hash1 key] value
        assert {[[lindex $peers 0] ttl save-kv2] < 10000000}
        assert_equal [[lindex $peers 0] tombstonesize] 1
        assert_equal [[lindex $peers 0] expiretombstonesize] 1
    }
}