
start_server {tags {"crdt-register"} module {crdt.so}} {
    test {SET and GET an item} {
        r set x foobar
        r get x
    } {foobar}

    test {SET and GET an empty item} {
        r set x {}
        r get x
    } {}

    test {Very big payload in GET/SET} {
        set buf [string repeat "abcd" 1000000]
        r set foo $buf
        r get foo
    } [string repeat "abcd" 1000000]

    test {Test Crdt Set} {
        r CRDT.set key val 1 [clock milliseconds]
    } {OK}

    test {Test Crdt Get} {
        r set key val
        puts [r CRDT.GET key]
    }
}
