proc master-peer {type arrange} {
    start_server {tags {"master"} overrides {crdt-gid 1} module {crdt.so} } {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_log [srv 0 stdout]
        set master_gid 1
        $master config set repl-diskless-sync yes
        $master config crdt.set repl-diskless-sync-delay 1
        start_server {tags {"peer"} overrides {crdt-gid 2} module {crdt.so} } {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_log [srv 0 stdout]
            set peer_gid 2
            $peer config set repl-diskless-sync yes
            $peer config set repl-diskless-sync-delay 1
            $peer config crdt.set repl-diskless-sync-delay 1
            
            test $type {
                if {[catch [uplevel 0 $arrange ] result]} {
                    # puts $result
                }
            }
        }
    }
}

proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
test "full_sync_max_limit" {
    master-peer "kv_value_max_memory" {
        $master config set proto-max-bulk-len "30b"
        $master set k1 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$master get k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $peer peerof $master_gid $master_host $master_port
        after 5000
        assert_equal [log_file_matches $master_log "*key:{k1} ,value is too big*"] 1
        $master config set proto-max-bulk-len "100b"
        wait_for_peer_sync $peer 
        assert_equal [$peer get k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
    }
    master-peer "tombstone_max_memory" {
        $master set k1 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $master config set proto-max-bulk-len "10b"
        assert_equal [$master get k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        $master del k1
        after 5000
        assert_equal [log_file_matches $master_log "*tombstone filter value too big*"] 1
        assert_equal [log_file_matches $master_log "*key:{k1} ,value is too big*"] 1
    }
    master-peer "hash_max_memory" {
        $master hset h k1 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $master config set proto-max-bulk-len "10b"
        assert_equal [$master hget h k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $peer peerof $master_gid $master_host $master_port
        after 5000
        assert_equal [log_file_matches $master_log "*hash key {k1} value too big*"] 1
        assert_equal [log_file_matches $master_log "*key:{h} ,value is too big*"] 1
    }
    master-peer "hash_tombstone_max_memory" {
        $master hset h k1 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$master hget h k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        $master hdel h k1
        $master config set proto-max-bulk-len "10b"
        after 5000
        assert_equal [log_file_matches $master_log "*hash tombstone key {k1} value too big*"] 1
        assert_equal [log_file_matches $master_log "*key:{h} ,value is too big*"] 1
    }
    master-peer "kv_value_max_memory" {
        $master config set proto-max-bulk-len "30b"
        $master set k1 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$master get k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $peer peerof $master_gid $master_host $master_port
        after 5000
        assert_equal [log_file_matches $master_log "*key:{k1} ,value is too big*"] 1
        $master config set proto-max-bulk-len "100b"
        wait_for_peer_sync $peer 
        assert_equal [$peer get k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
    }
    master-peer "hash_filter_split" {
        $master config set proto-max-bulk-len "50b"
        $master hset h k1 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $master hset h k2 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $master hset h k3 vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$master hget h k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$master hget h k2] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$master hget h k3] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        $peer peerof $master_gid $master_host $master_port
        wait_for_peer_sync $peer
        print_log_file $master_log
        assert_equal [log_file_matches $master_log "*key:{h} 3 splitted*"] 1
        assert_equal [$peer hget h k1] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$peer hget h k2] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
        assert_equal [$peer hget h k3] vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
    }
    master-peer "hash_tombstone_filter_split" {
        $master config set proto-max-bulk-len "30b"
        $master hset h k1 a k2 b k3 c k4 d k5 e k6 f k7 g
        assert_equal [$master hget h k1] a
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        $master hdel h k1
        $master hdel h k2
        $master hdel h k3
        $master hdel h k4
        $master hdel h k5
        $master hdel h k6
        after 5000
        print_log_file $master_log
        assert_equal [log_file_matches $master_log "*key:{h} 2 splitted*"] 1
        assert_equal [$peer hget h k7] g
    }
}