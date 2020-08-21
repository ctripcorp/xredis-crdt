proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
start_server {tags {"crdt-basic"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_stdouts {}
        set peer_gids {}
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 1
        
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1   
        
        start_server {tags {"crdt-basic"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_gids 2
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1 
            [lindex $peers 0] slaveof [lindex $peer_hosts 1] [lindex $peer_ports 1]  
            [lindex $peers 0] config set slave-read-only no
            start_server {tags {"crdt-basic"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_stdouts [srv 0 stdout]
                lappend peer_gids 2
                [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
                [lindex $peers 2] config set repl-diskless-sync-delay 1 
                [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0] 
                wait_for_sync [lindex $peers 0]
                wait_for_peer_sync [lindex $peers 2]
                # print_log_file [lindex $peer_stdouts 0]
                test "test" {
                    
                    [lindex $peers 1] set k v1
                    [lindex $peers 0] set k v2
                    [lindex $peers 1] setex k1 600 v1
                    [lindex $peers 0] setex k1 1200 v2
                    [lindex $peers 1] hset h k v1
                    [lindex $peers 0] hset h k v2
                    [lindex $peers 1] expire k 600 
                    [lindex $peers 0] expire k 1200
                    
                    [lindex $peers 1] set k3 v1
                    [lindex $peers 0] set k3 v2
                    [lindex $peers 0] del k3 
                    [lindex $peers 1] hset h1 k v1
                    [lindex $peers 0] hset h1 k v2
                    [lindex $peers 0] hdel h1 k

                    [lindex $peers 1] select 0 
                    [lindex $peers 1] set k v 

                    [lindex $peers 0] slaveof no one
                    
                    wait_for_peer_sync [lindex $peers 2] 
                    
                    assert_equal [[lindex $peers 2] get k] v1
                    assert_equal [[lindex $peers 2] get k1] v1
                    assert {[[lindex $peers 2] ttl k1] <= 600}
                    assert_equal [[lindex $peers 2] hget h k] v1
                    assert {[[lindex $peers 2] ttl k] <= 600}
                    assert_equal [[lindex $peers 2] get k3] v1
                    assert_equal [[lindex $peers 2] hget h1 k] v1
                    [lindex $peers 2] select 0 
                    assert_equal [[lindex $peers 2] get k ] v
                }
            }
        }
    }