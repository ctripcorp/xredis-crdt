

start_server { config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    test {Second server should have role master at first} {
        s role
    } {master}

    test {PEEROF should start with link status "down"} {
        r peerof 2 127.0.0.1 6479
        crdt_status r peer_0_link_status
    } {down}

    wait_for_peer_sync r
    after 5000
    puts [r get hello]
    test {Sync should have transferred keys from master} {
        r get hello
    } {}


}
