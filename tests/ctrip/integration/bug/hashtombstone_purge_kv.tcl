proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc wait { client index type log }  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        print_log_file $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}

#when hash merged, double free will cause the program to carsh
start_server { tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdout {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdout [srv 0 stdout]
    lappend peer_gids 1

    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 2
        lappend peer_stdout [srv 0 stdout]
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
       
        test "tombstone and data" {
            #kv -> hash tombstone  
            [lindex $peers 1] set k v
            [lindex $peers 0] hset k h v
            #hash tombstone -> kv
            set time [clock milliseconds]
            [lindex $peers 1] hset k1 h v

            [lindex $peers 1] crdt.del_hash  k1  2 [expr $time + 30] "2:3;3:1" "2:3;3:1" 
            # [lindex $peers 1] hset k1 h v
            [lindex $peers 0] set k1 v
            
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            # [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            [lindex $peers 0] del k
            [lindex $peers 1] del k1
            

            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdout 0]
            log_file_matches [lindex $peer_stdout 1] "*send crdt data num: 1*"
            log_file_matches [lindex $peer_stdout 1] "*send crdt tombstone num: 1*"
            assert_equal [[lindex $peers 0] get k] v
            assert_equal [[lindex $peers 0] get k1] v
        }
        
    }
}
