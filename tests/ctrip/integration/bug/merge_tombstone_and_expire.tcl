proc test_merge_tombstone_and_expire {type} {
    start_server {tags {"crdt-basic"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_gid 1
        start_server {tags {"crdt-basic"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_stdout [srv 0 stdout]
            set peer_gid 2

            set load_handle0 [start_write_expire_load $peer_host $peer_port 20 $type] 
            set load_handle1 [start_write_expire_load $master_host $master_port 20 $type] 
            after 3000
            $peer peerof $master_gid $master_host $master_port
            $master peerof $peer_gid $peer_host $peer_port
            wait_for_peer_sync $peer 
            wait_for_peer_sync $master 
            after 17000
            stop_write_load $load_handle0
            stop_write_load $load_handle1
            assert_equal [$peer dbsize]  [$master dbsize]
        }
    }
}

test "zset merge tombstone and expire" {
    test_merge_tombstone_and_expire zset 
}

test "set merge tombstone and expire" {
    test_merge_tombstone_and_expire set 
}

test "hash merge tombstone and expire" {
    test_merge_tombstone_and_expire hash 
}


test "string merge tombstone and expire" {
    test_merge_tombstone_and_expire string 
}

test "all merge tombstone and expire" {
    test_merge_tombstone_and_expire all 
}

