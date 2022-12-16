proc encode_binary_str {str size} {
    append type "H" $size
    binary format $type $str
}
proc decode_binary_str {binary_str size} {
    append type "H" $size
    binary scan $binary_str $type result
    return $result
}

start_server {tags {"crdt-register"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    test {"[crdt_register.tcl]SET and GET"} {
        r set x foobar
        set info [r crdt.datainfo x]
        # puts $info
        assert_equal [string match  "type: lww_register, gid: 1, timestamp: *, vector-clock: 1:1, val: foobar" [lindex $info 0]] 1
        r get x
    } {foobar}

    test {"[crdt_register.tcl]SET and GET an empty item"} {
        r set x {}
        r get x
    } {}

    test {"[crdt_register.tcl]Very big payload in GET/SET"} {
        set buf [string repeat "abcd" 1000000]
        r set foo $buf
        r get foo
    } [string repeat "abcd" 1000000]

    test {"[crdt_register.tcl]Test Crdt Set"} {
        r CRDT.set key val 1 [clock milliseconds] "1:100" 
    } {OK}

    test {"[crdt_register.tcl]Test Crdt Set-2"} {
        after 5
        r CRDT.set key val2 2 [clock milliseconds] "2:100" 
    } {OK}

    test {"[crdt_register.tcl]Test Concurrent-1"} {
        r CRDT.SET key val 1 [clock milliseconds] "1:100" 
        after 1
        r CRDT.SET key val2 1 [clock milliseconds] "1:101" 
        set info [r crdt.dataInfo key]
        assert_equal [string match  "type: lww_register, gid: 1, timestamp: *, vector-clock: 1:101;2:100, val: val2" [lindex $info 0]] 1
        r get key
    } {val2}

    test {"[crdt_register.tcl]Test Crdt Get"} {
        r set key val
        # puts [r CRDT.GET key]
    }

    test {"[crdt_register.tcl]Test Concurrent-2"} {
        r CRDT.SET key1 val 1 [clock milliseconds] "1:100" 
        # puts [r CRDT.GET key1]
        r CRDT.SET key1 val2 2 [expr [clock milliseconds] - 2000] "1:101;2:100" 
        # puts [r CRDT.GET key1]
        r get key1
    } {val2}

    test {"[crdt_register.tcl]Test Concurrent-3"} {
        r CRDT.SET key val 1 [clock milliseconds] "1:100" 
        after 1
        r CRDT.SET key val2 2 [clock milliseconds] "2:101" 
        r get key
    } {val2}


    test {"[crdt_register.tcl]Test DEL"} {
        r CRDT.SET key-del val 1 [clock milliseconds] "1:100" 
        after 1
        r DEL key-del
        r get key-del
    } {}

    # del concurrent conflict with set, set wins
    test {"[crdt_register.tcl]Test Concurrent DEL-1"} {
        r CRDT.SET key-del-2 val 1 [clock milliseconds] "1:100" 
        after 1
        r CRDT.DEL_REG key-del-2 2 [expr [clock milliseconds] - 2000] "2:101"
        r get key-del-2
    } {val}
    test {"[crdt_register.tcl]Test Concurrent set-binary"} {
        r set key-binary [encode_binary_str abcdef 6]
        decode_binary_str [ r get key-binary ] 6
        
    } {abcdef}
    test {"[crdt_register.tcl]mset"} {
        r mset k1 v1 k2 v2
        assert_equal [r get k1] v1
        assert_equal [r get k2] v2
    } {}
    test {"[crdt_register.tcl]mset1"} {
        r set k1 v1
        r mset k1 v2 k1 v3
        assert_equal [r get k1] v3
    } {}
    test {"[crdt_register.tcl]mget"} {
        r mset k11 v11 k12 v12
        assert_equal [r mget k11 k13 k12] {v11 {} v12}
        r hset h11 k v 
        assert_equal [r mget h11] {{}}  
    } {}

    test {"info tombstone"} {
        r "CRDT.DEL_REG" k13 "2" [clock milliseconds] "2:101;3:100" "2:101;3:100"
        set info [r crdt.dataInfo k13]
        assert_equal [string match  "type: lww_reigster_tombstone, gid: 2, timestamp: *, vector-clock: 2:101;3:100" [lindex $info 0]] 1 
    }
}
