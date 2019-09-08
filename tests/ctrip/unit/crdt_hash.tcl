

proc start_bg_hash_data {host port db ops} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/bg_hash_data.tcl $host $port $db $ops &
}

proc stop_bg_hash_data {handle} {
    catch {exec /bin/kill -9 $handle}
}

start_server {tags {"crdt-hash"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {

    set redis_host [srv 0 host]
    set redis_port [srv 0 port]

    test {"[crdt_hash.tcl]basic hset and hget"} {
        r hset k-hash f1 v1
        r hget k-hash f1
    } {v1}

    test {"[crdt_hash.tcl]hset and hget an empty item"} {
        r hset k-hash-1 k1 {}
        r hget k-hash-1 k1
    } {}

    test {"[crdt_hash.tcl]Very big payload in HGET/HMSET"} {
        set buf [string repeat "abcd" 1000000]
        r hmset k-hash-2 field $buf
        r hget k-hash-2 field
    } [string repeat "abcd" 1000000]

    test {"[crdt_hash.tcl]big hash map"} {
        set load_handle0 [start_bg_hash_data $redis_host $redis_port 9 100000]
        after 1000
        stop_bg_hash_data $load_handle0
    }
}
