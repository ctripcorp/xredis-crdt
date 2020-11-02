
start_server {tags {"hash tombstone"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        start_server {tags {"crdt-set"} overrides {crdt-gid 3} config {crdt.conf} module {crdt.so} } {
            set peer2 [srv 0 client]
            set peer2_gid 3
            set peer2_host [srv 0 host]
            set peer2_port [srv 0 port]
            set peer2_log [srv 0 stdout]
            $peer peerof $peer2_gid $peer2_host $peer2_port
            $peer hset h k1 v1
            $peer hset h k2 v2 
            $peer crdt.REM_HASH h 3 1000 "3:2;2:2" 2 k1 k2
            $master hset h k1 v0
            $peer peerof $master_gid $master_host $master_port
            wait_for_peer_sync $peer
            $peer crdt.hset h 3 999 {3:1} 1 k2 v3
            assert_equal [$peer hget h k2] {}
           
        }
    }
}