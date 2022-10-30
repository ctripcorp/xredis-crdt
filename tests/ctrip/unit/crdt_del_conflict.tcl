
start_server {tags {"crdt-del"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    set peers {}
    set hosts {}
    set ports {}
    set gids {}

    lappend peers [srv 0 client]
    lappend hosts [srv 0 host]
    lappend ports [srv 0 port]
    lappend gids 1

    r config crdt.set repl-diskless-sync-delay 1
    r config set repl-diskless-sync-delay 1

    start_server {tags {"crdt-del"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend hosts [srv 0 host]
        lappend ports [srv 0 port]
        lappend gids 2

        r config crdt.set repl-diskless-sync-delay 1
        r config set repl-diskless-sync-delay 1

        [lindex $peers 0] peerof [lindex $gids 1] [lindex $hosts 1] [lindex $ports 1]
        [lindex $peers 1] peerof [lindex $gids 0] [lindex $hosts 0] [lindex $ports 0]

        test "peers are connected" {
            # Wait for all the three slaves to reach the "online"
            # state from the POV of the master.
            set retry 500
            while {$retry} {
                set info [[lindex $peers 0] crdt.info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            set retry 500
            while {$retry} {
                set info [[lindex $peers 1] crdt.info replication]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion:Peers not correctly synchronized"
            }
        }

        test "wait till peers synchronized" {
            [lindex $peers 0] set k v
            wait_for_condition 500 100 {
                [[lindex $peers 1] get k] eq {v}
            } else {
                fail "peers not synchronized yet"
            }
        }

        test "crdt tombstone conflict" {
            [lindex $peers 0] del k
            wait_for_condition 500 100 {
                [[lindex $peers 1] get k] eq {}
            } else {
                fail "del fail to replicate"
            }
            # puts [format "tombstone size: %lld" [[lindex $peers 1] tombstonesize]]
            
            [lindex $peers 0] debug set-crdt-ovc 0
            [lindex $peers 1] debug set-crdt-ovc 0
            [lindex $peers 0] hmset k f v

            [lindex $peers 0] del k

            # puts [format "tombstone size: %lld" [[lindex $peers 1] tombstonesize]]
            [lindex $peers 0] set k v
            [lindex $peers 0] del k
            # puts [format "tombstone size: %lld" [[lindex $peers 1] tombstonesize]]
            [lindex $peers 0] hmset k f v

            [lindex $peers 0] del k

            # puts [format "tombstone size: %lld" [[lindex $peers 1] tombstonesize]]

            [lindex $peers 1] debug set-crdt-ovc 1
            [lindex $peers 1] debug set-crdt-ovc 1
        }

        test "crdt del hash then k/v" {
            [lindex $peers 0] hmset key-hash-key f v f1 v1 f2 v2
            [lindex $peers 0] del key-hash-key
            [lindex $peers 0] set key-hash-key val
            [lindex $peers 0] del key-hash-key

            wait_for_condition 500 100 {
                [[lindex $peers 0] tombstonesize] eq 0
            } else {
                fail "tombstone not gced"
            }
        }
    }
}
