proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait { client index type log}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            assert_equal [$client ping] PONG
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        assert_equal [$client ping] PONG
        print_log_file $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
proc get_dataset { client } {
    set info [$client memory stats]
    if {[regexp {dataset.bytes ([0-9]+)} $info _ value] == 1} {
        return $value
    }
    return 0
}
set server_path [tmpdir "slave-merge-expired-object-bug"]
start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_gids 1
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
        
        start_server {tags {"crdt-basic"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_gids 2
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            $master config set repl-backlog-size 1mb
            set size1 [get_dataset [lindex $peers 0]]
            set size2 [get_dataset [lindex $peers 1]]
             for {set i 0} {$i < 20} {incr i} {
                $master set $i v ex 10
                [lindex $peers 1] set $i v ex 10
            }
            
            [lindex $peers 0] slaveof $master_host $master_port  
            [lindex $peers 0] config set slave-read-only no
            # wait $master 0 info $master_stdout
            wait_for_sync [lindex $peers 0]
            
            
            # print_log_file [lindex $peer_stdouts 0]
            [lindex $peers 0] slaveof no one
            after 10000
            
            
            set retry 100
            while {$retry} {
                if {
                    [[lindex $peers 0] dbsize] == 0 && 
                    [[lindex $peers 0] expiresize] == 0 && 
                    [[lindex $peers 0] tombstonesize] == 0 &&
                    [[lindex $peers 1] dbsize] == 0 &&
                    [[lindex $peers 1] expiresize] == 0 &&
                    [[lindex $peers 1] tombstonesize] == 0
                } {
                    break
                } else {
                    assert_equal [[lindex $peers 0] ping] PONG
                    assert_equal [[lindex $peers 1] ping] PONG
                    # puts [[lindex $peers 0] dbsize] 
                    # puts [[lindex $peers 0] expiresize] 
                    # puts [[lindex $peers 0] tombstonesize] 
                    # puts [[lindex $peers 1] dbsize] 
                    # puts [[lindex $peers 1] expiresize] 
                    # puts [[lindex $peers 1] tombstonesize] 
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "wait expire free all momory fail"
            }
            # set size2 [get_dataset [lindex $peers 0]]
            # assert_equal [expr [expr  [get_dataset [lindex $peers 0]] -$size1] - [expr [get_dataset [lindex $peers 1]] -$size2]] 32
            
        }
    }
}