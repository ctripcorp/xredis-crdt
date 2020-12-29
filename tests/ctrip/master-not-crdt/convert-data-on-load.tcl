# Copy RDB with zipmap encoded hash to server path
set server_path [tmpdir "server.convert-zipmap-hash-on-load"]

set module_path [exec pwd]
append module_path "/tests/assets/"
set uname_S [exec uname -s]
if {$uname_S eq "Darwin"} {
    append module_path "mac/"
} elseif {$uname_S eq "Linux"} {
    append module_path "linux/"
}
append module_path "crdt.so"
exec cp -f $module_path $server_path
start_redis [list overrides [list "dir" $server_path "dbfilename" "zset-ziplist.rdb"]] {
    r zadd zset 1.0 f1 
    r zadd zset 2.0 f2
    assert_match "*ziplist*" [r debug object zset]
    assert_equal 2 [r zcard zset]
    r bgsave
    exec cp $server_path/zset-ziplist.rdb z.rdb
}
start_redis [list overrides [list "dir" $server_path "dbfilename" "zset-skiplist.rdb" "zset-max-ziplist-entries" 1]] {
    r zadd zset1 1.0 f1 
    r zadd zset1 2.0 f2
    # assert_match "*ziplist*" [r debug object zset]
    assert_equal 2 [r zcard zset1]
    r bgsave
    exec cp $server_path/zset-skiplist.rdb s.rdb
}

start_redis [list overrides [list "dir" $server_path "dbfilename" "zset-skiplist2.rdb" "zset-max-ziplist-value" 1]] {
    r zadd zset2 1.0 f1 
    r zadd zset2 2.0 f2
    # assert_match "*ziplist*" [r debug object zset]
    assert_equal 2 [r zcard zset2]
    r bgsave
    exec cp $server_path/zset-skiplist2.rdb s2.rdb
}