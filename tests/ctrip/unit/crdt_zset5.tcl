
start_server {tags {"debug"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    test "add contemporary" {
        r zadd myzset1 1.0 a 2.0 a
        assert_equal [r zscore myzset1 a] 2
    }
    test "other tag is null" {
        r crdt.debug_gc zset 0
        r zadd myzset2 1.99999 a
        r del myzset2 
        r crdt.zadd myzset2 2 10000 2:207 a 2:1.1
        r CRDT.DEL_SS myzset2 2 1608010265117 2:208 
        assert_equal [r zscore myzset2 a] {}
    }
    test "zset from sst" {
        r  CRDT.Zrem myzset3 2 10000 {1:1;2:1} {3:6:mfield,1:15494:2:-174735312.23345113,2:15838:2:-516884416.18146986}
        r  CRDT.Zincrby myzset3 3 10000 {1:1;3:1} mfield {2:-223717193.02946794}
        r CRDT.Zrem myzset3 3 10000 {1:1;3:2} {3:6:mfield,1:15494:2:-174735312.23345113,3:15936:2:-223717193.02946794}
        r zadd myzset3 244089021.83550954 mfield
        assert_equal [r zscore myzset3 mfield] 244089021.83550954
        assert_match "*1:4;2:1;3:2*" [r crdt.datainfo myzset3] 
    }
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    start_server {tags {"debug"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        $master crdt.debug_gc zset 0
        $peer crdt.debug_gc zset 0
        test "before" {
            $master crdt.datainfo []
        }
        $peer crdt.set set_vcu vcu 2 1000 2:100000
        $master peerof $peer_gid $peer_host $peer_port
        $peer peerof $master_gid $master_host $master_port
        wait_for_peer_sync $master 
        wait_for_peer_sync $peer
        test "crdt.zadd and zadd diff" {
            
            $master CRDT.DEL_SS myzset2 3 1608708360416 3:14
            $peer CRDT.DEL_SS myzset2 3 1608708360416 3:14
            $master zadd myzset2  1.0 a 
            # after 1000
            # puts [$master crdt.datainfo myzset2]
            # puts [$peer crdt.datainfo myzset2]
        }
    }
    # set master [srv 0 client]
    # set master_gid 1
    # set master_host [srv 0 host]
    # set master_port [srv 0 port]
    # set master_log [srv 0 stdout]
    # start_server {tags {"debug"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
    #     set peer [srv 0 client]
    #     set peer_gid 2
    #     set peer_host [srv 0 host]
    #     set peer_port [srv 0 port]
    #     set peer_log [srv 0 stdout]
    #     start_server {tags {"debug"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    #         set slave [srv 0 client]
    #         set slave_gid 1
    #         set slave_host [srv 0 host]
    #         set slave_port [srv 0 port]
    #         set slave_log [srv 0 stdout]
    #         $master crdt.debug_gc zset 0
    #         # $slave crdt.debug_gc zset 0
    #         $master peerof $peer_gid $peer_host $peer_port
    #         $peer peerof $master_gid $master_host $master_port
    #         $slave crdt.debug_gc zset 0
    #         $slave slaveof $master_host $master_port
            
    #         wait_for_sync $slave 
    #         wait_for_peer_sync $master 
    #         wait_for_peer_sync $peer
    #         test "before" {
    #             # $master zadd zset1 3.0 a 4.0 b 
    #             # # $master crdt.del_ss zset1 2 1000 2:1 
    #             # $master crdt.zrem zset1 2 1000 {2:1;1:2} 3:1:a 3:1:b
    #             # $master CRDT.ZADD myzset2 2 1608573287104 2:16 250154318404 2:7684606 -433 2:3797239
    #             # $master CRDT.DEL_SS myzset2 2 1608573287104 2:22
    #             # $master CRDT.ZADD myzset2 3 1608573287107 {2:22;3:28} -456831028897 2:1834112 2651796764 2:6388045
    #             # $master CRDT.DEL_SS myzset2 3 1608573287107 {2:22;3:34}

    #             $master zadd myzset3 2 a 
    #             $peer zadd myzset3 3 a 
    #             $master del myzset3 
    #             $peer del myzset3
    #             puts [$master crdt.datainfo myzset3]
    #         }
           
    #         $master slaveof $slave_host $slave_port
    #         $slave slaveof no one 
            
    #         test "after" {
                
    #             $slave zadd myzset3 2 a 
    #             after 1000
    #             wait_for_sync $master
    #             # print_log_file $slave_log
    #             print_log_file $master_log
    #             # puts [$master crdt.info replication]
    #             puts [$slave crdt.info replication]
    #             puts [$slave crdt.datainfo myzset3]
    #             puts [$master crdt.datainfo myzset3]
    #         }
    #     }
    # }
}