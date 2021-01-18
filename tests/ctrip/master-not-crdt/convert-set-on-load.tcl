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

start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "set.rdb"]] {
   test "RDB load set: SetObject" {
    r select 0
    # assert_match "*hashtable*" [
    # assert_equal 2 [r hlen hash]
    assert_match {1 10 11 12 13 14 15 16 17 18 19 2 20 21 22 3 4 5 6 7 8 9} [lsort [r smembers k]]
  }
}


start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" "set.rdb" "set-max-intset-entries" 1]] {
   test "RDB load set: SetObject" {
    r select 0
    # assert_match "*hashtable*" [
    # assert_equal 2 [r hlen hash]
    assert_match {1 10 11 12 13 14 15 16 17 18 19 2 20 21 22 3 4 5 6 7 8 9} [lsort [r smembers k]]
  }
}

