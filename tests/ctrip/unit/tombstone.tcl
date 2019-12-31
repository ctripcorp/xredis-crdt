
proc wait { client index}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client crdt.info replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        error "assertion: Master-Slave not correctly synchronized"
    }
}


test "tombstone kv" {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 1
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        test "tombstone hash" {
            [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 0] config set repl-diskless-sync-delay 1
            set time [clock milliseconds]
            [lindex $peers 0] crdt.rem_hash  hash-key  2 $time "2:2;3:1" field
            [lindex $peers 0] crdt.hset hash-key 3 [expr $time - 10] "2:1;3:1" 2 field val
            assert {[[lindex $peers 0] hget hash-key field ] eq {}}
            [lindex $peers 0] crdt.hset hash-key 3 [expr $time + 10] "2:2;3:2" 2 field val1 
            assert {[[lindex $peers 0] hget hash-key field] eq {val1}}
            [lindex $peers 0] crdt.del_reg  hash-key  2 [expr $time + 30] "2:3;3:3" field
            assert {[[lindex $peers 0] hget hash-key field] eq {}}
            [lindex $peers 0] crdt.hset hash-key 3 [expr $time + 20] "2:2;3:3" 2 field1 val1
            assert {[[lindex $peers 0] hget hash-key field1] eq {}}
        }
        
        test "tomstone kv" {
            set time [clock milliseconds]
            [lindex $peers 0] crdt.del_reg  key  2 $time "2:4;3:4" field 
            [lindex $peers 0] crdt.set key val 3 [expr $time - 10] "2:3;3:4" 10000
            
            assert {[[lindex $peers 0] hget key field ] eq {}}

            [lindex $peers 0] crdt.set key val1 3 [expr $time + 10] "2:4;3:5" 10000 
            assert {[[lindex $peers 0] get key] eq {val1}}
        }
    }
}


start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        start_server {config {crdt.conf} overrides {crdt-gid 3 repl-diskless-sync-delay 1} module {crdt.so}} {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 3
            [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 2] config set repl-diskless-sync-delay 1
            test "full sync tombstone" {
                [lindex $peers 0] set key v0
                [lindex $peers 0] hset key1 f v1
                [lindex $peers 0] hset key2 f v2
                [lindex $peers 0] hset key2 f1 v1
                [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                set retry 50
                wait [lindex $peers 0] 0 
                [lindex $peers 1] del key
                [lindex $peers 1] hset key1 f1 f1 
                [lindex $peers 1] hdel key1 f
                [lindex $peers 1] del key2 
                [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                [lindex $peers 2] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                wait [lindex $peers 0] 1
                wait [lindex $peers 1] 0
                after 1000
                assert {[[lindex $peers 1] get key] eq {}}
                assert {[[lindex $peers 2] get key] eq {}}
                assert {[[lindex $peers 1] hget key1 f] eq {}}
                assert {[[lindex $peers 2] hget key1 f] eq {}}
                assert {[[lindex $peers 1] hget key2 f] eq {}}
                assert {[[lindex $peers 2] hget key2 f] eq {}}
                assert {[[lindex $peers 1] hget key2 f1] eq {}}
                assert {[[lindex $peers 2] hget key2 f1] eq {}}
                [lindex $peers 2] set key v10
                [lindex $peers 2] hset key1 f v11
                [lindex $peers 2] hset key2 f v12
                [lindex $peers 2] hset key2 f1 v13
                assert {[[lindex $peers 2] get key] eq {v10}}
                assert {[[lindex $peers 2] hget key1 f] eq {v11}}
                assert {[[lindex $peers 2] hget key2 f] eq {v12}}
                assert {[[lindex $peers 2] hget key2 f1] eq {v13}}

            }
        }
    }
}

