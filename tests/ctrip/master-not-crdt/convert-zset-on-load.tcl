# Copy RDB with zipmap encoded hash to server path
set server_path [tmpdir "server.convert-set-on-load"]

set module_path [exec pwd]
append module_path "/tests/assets/"
set uname_S [exec uname -s]
if {$uname_S eq "Darwin"} {
    append module_path "mac/"
} elseif {$uname_S eq "Linux"} {
    append module_path "linux/"
}
append module_path "crdt.so"
exec cp -f tests/assets/set.rdb $server_path
exec cp -f tests/assets/zset.rdb $server_path
exec cp -f $module_path $server_path
# start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "set.rdb"]] {
#   test "RDB load set : IntsetObject" {
#     r select 0
#     # assert_match "*ziplist*" [r debug object hash]
#     # assert_equal 2 [r hlen hash]
#     after 1000
#     assert_match {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22} [lsort [r smembers k]]
#   }
# }


# start_server [list overrides [list "dir" $server_path "dbfilename" "hash-zipmap.rdb" "hash-max-ziplist-entries" 1]] {
# start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "sadd.rdb" "set-max-intset-entries" 1]] {
#    test "RDB load set: SetObject" {
#     r select 0
#     # assert_match "*hashtable*" [r debug object hash]
#     # assert_equal 2 [r hlen hash]
#     assert_match {1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22} [lsort [r smembers myset]]
#   }
# }

start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "zset.rdb"]] {
  test "RDB load set : IntsetObject" {
    r select 0
    # assert_match "*ziplist*" [r debug object hash]
    # assert_equal 2 [r hlen hash]
    after 1000
    puts [r dbsize]
    assert_equal [r zscore k a] 1
    assert_equal [r zscore k b] 2
    assert_equal [r zscore k c] 3
    assert_equal [r zscore k d] 4
    assert_equal [r zscore k e] 5
    assert_equal [r zscore k f] 6
    assert_equal [r zscore k g] 7
    assert_equal [r zscore k h] 8
    assert_equal [r zscore k i] 9
    assert_equal [r zscore k j] 10
    assert_equal [r zscore k k] 11
    assert_equal [r zscore k l] 12
    assert_equal [r zscore k m] 13
    assert_equal [r zscore k n] 14
    assert_equal [r zscore k o] 15
    assert_equal [r zscore k p] 16
    assert_equal [r zscore k q] 17
    assert_equal [r zscore k r] 18
    assert_equal [r zscore k s] 19
    assert_equal [r zscore k t] 20
    assert_equal [r zscore k u] 21
    
  }
}


start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "zset.rdb" "zset-max-ziplist-entries" 1]] {
  test "RDB load set : zset-max-ziplist-entries" {
    r select 0
    # assert_match "*ziplist*" [r debug object hash]
    # assert_equal 2 [r hlen hash]
    after 1000
    puts [r dbsize]
    assert_equal [r zscore k a] 1
    assert_equal [r zscore k b] 2
    assert_equal [r zscore k c] 3
    assert_equal [r zscore k d] 4
    assert_equal [r zscore k e] 5
    assert_equal [r zscore k f] 6
    assert_equal [r zscore k g] 7
    assert_equal [r zscore k h] 8
    assert_equal [r zscore k i] 9
    assert_equal [r zscore k j] 10
    assert_equal [r zscore k k] 11
    assert_equal [r zscore k l] 12
    assert_equal [r zscore k m] 13
    assert_equal [r zscore k n] 14
    assert_equal [r zscore k o] 15
    assert_equal [r zscore k p] 16
    assert_equal [r zscore k q] 17
    assert_equal [r zscore k r] 18
    assert_equal [r zscore k s] 19
    assert_equal [r zscore k t] 20
    assert_equal [r zscore k u] 21
    
  }
}

start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "zset.rdb" "zset-max-ziplist-value" 1]] {
  test "RDB load set : zset-max-ziplist-entries" {
    r select 0
    # assert_match "*ziplist*" [r debug object hash]
    # assert_equal 2 [r hlen hash]
    after 1000
    puts [r dbsize]
    assert_equal [r zscore k a] 1
    assert_equal [r zscore k b] 2
    assert_equal [r zscore k c] 3
    assert_equal [r zscore k d] 4
    assert_equal [r zscore k e] 5
    assert_equal [r zscore k f] 6
    assert_equal [r zscore k g] 7
    assert_equal [r zscore k h] 8
    assert_equal [r zscore k i] 9
    assert_equal [r zscore k j] 10
    assert_equal [r zscore k k] 11
    assert_equal [r zscore k l] 12
    assert_equal [r zscore k m] 13
    assert_equal [r zscore k n] 14
    assert_equal [r zscore k o] 15
    assert_equal [r zscore k p] 16
    assert_equal [r zscore k q] 17
    assert_equal [r zscore k r] 18
    assert_equal [r zscore k s] 19
    assert_equal [r zscore k t] 20
    assert_equal [r zscore k u] 21
    
  }
}