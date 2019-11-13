
start_server {tags {"crdt-register"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    test {"[crdt_register.tcl]SET and GET"} {
        r set x foobar
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
        r CRDT.set key val 1 [clock milliseconds] "1:100" 10000
    } {OK}

    test {"[crdt_register.tcl]Test Crdt Set-2"} {
        after 5
        r CRDT.set key val2 2 [clock milliseconds] "2:100" 10000
    } {OK}

    test {"[crdt_register.tcl]Test Concurrent-1"} {
        r CRDT.SET key val 1 [clock milliseconds] "1:100" 10000
        after 1
        r CRDT.SET key val2 1 [clock milliseconds] "1:101" 10000
        r get key
    } {val2}

    test {"[crdt_register.tcl]Test Crdt Get"} {
        r set key val
        puts [r CRDT.GET key]
    }

    test {"[crdt_register.tcl]Test Concurrent-2"} {
        r CRDT.SET key1 val 1 [clock milliseconds] "1:100" 10000
        puts [r CRDT.GET key1]
        r CRDT.SET key1 val2 2 [expr [clock milliseconds] - 2000] "1:101;2:100" 10000
        puts [r CRDT.GET key1]
        r get key1
    } {val2}

    test {"[crdt_register.tcl]Test Concurrent-3"} {
        r CRDT.SET key val 1 [clock milliseconds] "1:100" 10000
        after 1
        r CRDT.SET key val2 2 [clock milliseconds] "2:101" 10000
        r get key
    } {val2}


    test {"[crdt_register.tcl]Test DEL"} {
        r CRDT.SET key-del val 1 [clock milliseconds] "1:100" 10000
        after 1
        r DEL key-del
        r get key-del
    } {}

    # del concurrent conflict with set, set wins
    test {"[crdt_register.tcl]Test Concurrent DEL-1"} {
        r CRDT.SET key-del-2 val 1 [clock milliseconds] "1:100" 10000
        after 1
        r CRDT.DEL_REG key-del-2 2 [expr [clock milliseconds] - 2000] "2:101"
        r get key-del-2
    } {val}

}
