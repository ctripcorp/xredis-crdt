
start_server {tags {"crdt-del"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    test {"[crdt_del.tcl]basic delete"} {
        r set x foobar
        r del x
        r get x
    } {}

    test {"[crdt_del.tcl]basic crdt delete"} {
        r set x2 foobar
        r CRDT.DEL_REG x2 1 [clock milliseconds] "1:10"
        r get x2
    } {}

    test {"[crdt_del.tcl]concurrent crdt delete - 1"} {
        r set key-del-3 val
        after 1
        r CRDT.SET key-del-3 val2 3 [expr [clock milliseconds] - 10]  "1:10;2:99;3:100"
        r CRDT.DEL_REG key-del-3 2 [clock milliseconds] "1:30;2:100;3:100"
        r get key-del-3
    } {}

    test {"[crdt_del.tcl]concurrent crdt delete - 2"} {
        r set key-del-4 val
        after 1
        r CRDT.DEL_REG key-del-4 2 [clock milliseconds] "1:30;2:100;3:100"
        after 1
        r CRDT.SET key-del-4 val2 3 [expr [clock milliseconds] - 10]  "1:10;2:99;3:100"
        r get key-del-4
    } {}

    test {"[crdt_del.tcl]concurrent crdt delete - 3"} {
        r CRDT.DEL_REG key-del-5 2 [clock milliseconds] "1:30;2:100;3:100"
        r CRDT.SET key-del-5 val2 3 [expr [clock milliseconds] - 10]  "1:10;2:99;3:100"
        r get key-del-5
    } {}

    test {"[crdt_del.tcl]concurrent crdt delete - 4"} {
        r CRDT.SET key-del-6 val2 1 [expr [clock milliseconds] - 10]  "1:10"
        r CRDT.DEL_REG key-del-6 2 [clock milliseconds] "2:100"
        r get key-del-6
    } {val2}
}
