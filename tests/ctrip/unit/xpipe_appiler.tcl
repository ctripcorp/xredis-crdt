
start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    set gid 1
    test {test incr command} {
        # set repl [attach_to_replication_stream]
        set repl [attach_to_crdt_replication_stream  $gid [srv 0 host] [srv 0 port]]
        r incr foo 
        r incrby foo 2
        r incrbyfloat foo 1.5
        r incrbyfloat foo 2.5
        r incrbyfloat foo 3.1415926
        assert_replication_stream $repl {
            {crdt.select 1 9}
            {crdt.counter foo 1 * * * * 1}
            {crdt.counter foo 1 * * * * 3}
            {crdt.counter foo 1 * * * * 4.5}
            {crdt.counter foo 1 * * * * 7}
            {crdt.counter foo 1 * * * * 10.1415926}
        }
        close_replication_stream $repl
    }

    test {test zincr command} {
        # set repl [attach_to_replication_stream]
        set repl [attach_to_crdt_replication_stream  $gid [srv 0 host] [srv 0 port]]
        r zadd zset INCR  1 foo
        r zincrby zset 2 foo
        r zincrby zset 1.5 foo
        r zadd zset INCR  2.5 foo
        r zincrby zset 3.1415926 foo
        assert_replication_stream $repl {
            {crdt.select 1 9}
            {crdt.zincrby zset 1 * * foo * 1}
            {crdt.zincrby zset 1 * * foo * 3}
            {crdt.zincrby zset 1 * * foo * 4.5}
            {crdt.zincrby zset 1 * * foo * 7}
            {crdt.zincrby zset 1 * * foo * 10.141592599999999}
        }
        close_replication_stream $repl
    }
}