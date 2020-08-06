proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        test "peerof myself" {
            if { [catch {
            [lindex $peers 0] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0] 
            } e]} {
                assert_equal $e "ERR invalid gid"
            } else {
                fail "code error"
            }
        }
        test "peerof no one test" {
            [lindex $peers 1] set key v1
            [lindex $peers 0] set key v0
            [lindex $peers 1] hset "hash" "field" "v1"
            [lindex $peers 0] hset "hash" "field" "v0"
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            set retry 50
            while {$retry} {
                set info [[lindex $peers 0] crdt.info replication]
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
            
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
        }
        test "peerof sendcode" {
            [lindex $peers 1] mset k v k1 v1
            [lindex $peers 0] mset k2 v2 k3 v3
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            set retry 50
            while {$retry} {
                set info [[lindex $peers 0] crdt.info replication]
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
            assert_equal [[lindex $peers 1] get k] v
            assert_equal [[lindex $peers 1] get k1] v1
            assert_equal [[lindex $peers 1] get k2] v2 
            assert_equal [[lindex $peers 1] get k3] v3
            assert_equal [[lindex $peers 1] hget "hash" "field"] v0
            assert_equal [[lindex $peers 1] get key] v0
            [lindex $peers 1] peerof [lindex $peer_gids 0] no one
        }
    }
}