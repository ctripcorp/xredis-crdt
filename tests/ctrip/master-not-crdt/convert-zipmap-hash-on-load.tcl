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
exec cp -f tests/assets/hash-zipmap.rdb $server_path
exec cp -f $module_path $server_path
# start_server [list overrides [list "dir" $server_path "dbfilename" "hash-zipmap.rdb"]] {
# start_server {tags {"ziplist"} overrides {crdt-gid 1  "dir" $server_path "dbfilename" "hash-zipmap.rdb"} config {crdt.conf} module {crdt.so} } {

start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "hash-zipmap.rdb"]] {
  test "RDB load zipmap hash: converts to ziplist" {
    r select 0

    # assert_match "*ziplist*" [r debug object hash]
    # assert_equal 2 [r hlen hash]
    assert_match {v1 v2} [r hmget hash f1 f2]
  }
}

exec cp -f tests/assets/hash-zipmap.rdb $server_path
# start_server [list overrides [list "dir" $server_path "dbfilename" "hash-zipmap.rdb" "hash-max-ziplist-entries" 1]] {
start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "hash-zipmap.rdb" "hash-max-ziplist-entries" 1]] {
   test "RDB load zipmap hash: converts to hash table when hash-max-ziplist-entries is exceeded" {
    r select 0

    # assert_match "*hashtable*" [r debug object hash]
    # assert_equal 2 [r hlen hash]
    assert_match {v1 v2} [r hmget hash f1 f2]
  }
}

exec cp -f tests/assets/hash-zipmap.rdb $server_path
# start_server [list overrides [list "dir" $server_path "dbfilename" "hash-zipmap.rdb" "hash-max-ziplist-value" 1]] {
start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "hash-zipmap.rdb" "hash-max-ziplist-value" 1]] {
  test "RDB load zipmap hash: converts to hash table when hash-max-ziplist-value is exceeded" {
    r select 0

    # assert_match "*hashtable*" [r debug object hash]
    # assert_equal 2 [r hlen hash]
    assert_match {v1 v2} [r hmget hash f1 f2]
  }
}
