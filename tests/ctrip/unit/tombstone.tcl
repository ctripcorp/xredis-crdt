
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
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
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
            start_server {config {crdt.conf} overrides {crdt-gid 4 repl-diskless-sync-delay 1} module {crdt.so}} {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_gids 4
                [lindex $peers 3] config crdt.set repl-diskless-sync-delay 1
                [lindex $peers 3] config set repl-diskless-sync-delay 1
                test "full-sync tombstone merge some type" {
                    [lindex $peers 0] set key v1
                    [lindex $peers 0] hset hash-key f1 v1
                    [lindex $peers 0] hset hash-key f2 v2
                    [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                    [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                    wait [lindex $peers 0] 0
                    wait [lindex $peers 0] 1
                    [lindex $peers 1] del key 
                    [lindex $peers 2] del key 
                    [lindex $peers 1] hdel hash-key f1
                    [lindex $peers 2] hdel hash-key f2
                    [lindex $peers 3] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                    [lindex $peers 3] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]
                    wait [lindex $peers 1] 0
                    wait [lindex $peers 2] 0
                    after 1000
                    assert {[[lindex $peers 3] get key] eq {}}
                    assert {[[lindex $peers 3] hget hash-key f1] eq {}}
                    assert {[[lindex $peers 3] hget hash-key f2] eq {}}
                }
            }
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
            start_server {config {crdt.conf} overrides {crdt-gid 4 repl-diskless-sync-delay 1} module {crdt.so}} {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_gids 4
                [lindex $peers 3] config crdt.set repl-diskless-sync-delay 1
                [lindex $peers 3] config set repl-diskless-sync-delay 1
                start_server {config {crdt.conf} overrides {crdt-gid 5 repl-diskless-sync-delay 1} module {crdt.so}} {
                    lappend peers [srv 0 client]
                    lappend peer_hosts [srv 0 host]
                    lappend peer_ports [srv 0 port]
                    lappend peer_gids 5
                    set stdout5 [srv 0 stdout]
                    [lindex $peers 4] config crdt.set repl-diskless-sync-delay 1
                    [lindex $peers 4] config set repl-diskless-sync-delay 1
                    test "tombstone different type" {
                        [lindex $peers 0] hset key field value
                        [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                        wait [lindex $peers 0] 0
                        [lindex $peers 1] hdel key field
                        [lindex $peers 2] set key value
                        [lindex $peers 3] peerof [lindex $peer_gids 2] [lindex $peer_hosts 2] [lindex $peer_ports 2]
                        wait [lindex $peers 2] 0
                        [lindex $peers 3] del key
                        [lindex $peers 4] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                        [lindex $peers 4] peerof [lindex $peer_gids 3] [lindex $peer_hosts 3] [lindex $peer_ports 3]
                        wait [lindex $peers 1] 0
                        wait [lindex $peers 3] 0
                        wait_for_condition 50 100 {
                            [log_file_matches $stdout5 {*tombstone*}]
                        } else {
                            fail "no merge tombstone fail log"
                        }
                        for { set i 0 }  {$i < 5} {incr i} {
                            for {set pi 0} {$pi < 5} {incr pi} {
                                if {$i != $pi} {
                                    [lindex $peers $i] peerof [lindex $peer_gids $pi] [lindex $peer_hosts $pi] [lindex $peer_ports $pi]
                                    after 1000
                                }
                            }
                        }
                        for { set i 0 }  {$i < 5} {incr i} {
                            assert {[[lindex $peers $i] ping] eq {PONG}}
                        }
                        
                    }
                }
            }
        }
    }
}