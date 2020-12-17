
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
    
}