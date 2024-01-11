start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config set hz 100
    
    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        $peer config set hz 100
        $peer config crdt.set repl-timeout 120
        $peer peerof 1 $master_host $master_port
        $master peerof 2 $peer_host $peer_port
        wait_for_peer_sync $peer 
        wait_for_peer_sync $master
        set peer_ovc [crdt_repl $peer ovc] 
        $master zrem z f 
        if {[$master tombstonesize] == 1} {
            #only test gc old null tombstone
            set try 10
            while  {$try > 0} {
                if {[$master tombstonesize] == 0} {
                    break;
                }
                after 500
                set try [expr {$try-1}]
            }
            assert {$try > 0}
        } else {
            assert {[crdt_repl $peer ovc] == $peer_ovc}
        }
        

        $master zadd z 10 f 
        while 1 {
            if {[$peer zscore z f] == 10} {
                break;
            }
        }
        set peer_ovc [crdt_repl $peer ovc]
        $master zrem z f1 
        if {[$master tombstonesize] == 1} {
            #only test gc old null tombstone
            set try 10
            while  {$try > 0} {
                if {[$master tombstonesize] == 0} {
                    break;
                }
                after 500
                set try [expr {$try-1}]
            }
            assert {$try > 0}
        } elseif {[$master tombstonesize] == 0} {
            assert {[crdt_repl $peer ovc] == $peer_ovc}
        }
    }
}