
start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    set master_gid 1
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set repl-diskless-sync-delay 1
    start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_log [srv 0 stdout]
        set slave_gid 1
        
        $slave config set repl-diskless-sync-delay 1
        $slave config crdt.set repl-diskless-sync-delay 1
        start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_log [srv 0 stdout]
            set peer_gid 2
            $peer config set repl-diskless-sync-delay 1
            $peer config crdt.set repl-diskless-sync-delay 1
            start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
                set peer_slave [srv 0 client]
                set peer_slave_host [srv 0 host]
                set peer_slave_port [srv 0 port]
                set peer_slave_log [srv 0 stdout]
                set peer_slave_gid 2
                $peer_slave config set repl-diskless-sync-delay 1
                $peer_slave config crdt.set repl-diskless-sync-delay 1
                proc init {master master_gid master_host  master_port peer peer_gid peer_host peer_port slave peer_slave} {
                    $slave slaveof $master_host $master_port
                    $peer_slave slaveof $peer_host $peer_port
                    $master peerof $peer_gid $peer_host $peer_port
                    $peer peerof $master_gid $master_host $master_port
                    wait_for_sync $slave 
                    wait_for_sync $peer_slave 
                    wait_for_peer_sync $master 
                    wait_for_peer_sync $peer 
                }
                init $master $master_gid $master_host $master_port $peer $peer_gid $peer_host $peer_port $slave $peer_slave
                test "change" {
                    while {1} {
                        set peer_slave_sync_partial_ok [status $peer_slave sync_partial_ok]
                        set master_peer_sync_partial_ok [crdt_stats $master sync_partial_ok]
                        $master slaveof 127.0.0.1 0 
                        $slave slaveof no one 
                        $master slaveof $slave_host $slave_port 
                        $peer slaveof 127.0.0.1 0 
                        $peer_slave slaveof no one 
                        $peer slaveof $peer_slave_host $peer_slave_port
                        wait_for_sync $peer 
                        wait_for_peer_sync $peer_slave  
                        wait_for_peer_sync $slave
                        if {[expr  $peer_slave_sync_partial_ok + 1] == [status $peer_slave sync_partial_ok]} {
                            puts $master_peer_sync_partial_ok  
                            puts [crdt_stats $master sync_partial_ok]
                            if {[expr  $master_peer_sync_partial_ok + 1] == [crdt_stats $master sync_partial_ok]} {
                                break;
                            }
                        }
                        init $master $master_gid $master_host $master_port $peer $peer_gid $peer_host $peer_port $slave $peer_slave
                    }
                    $peer_slave peerof $slave_gid $slave_host $slave_port
                    $slave peerof $peer_slave_gid $peer_slave_host $peer_slave_port
                    wait_for_peer_sync $peer_slave
                    wait_for_peer_sync $slave 
                    $peer_slave set k v  
                    after 1000
                    assert_equal [$master get k] v 
                }
            }
        }
    }
}