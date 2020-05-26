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
            [lindex $peers 0] slaveof $master_host $master_port  
            wait $master 0 info $master_stdout
            
            # print_log_file [lindex $peer_stdouts 0]
            test "test" {
                [lindex $peers 0] set key value ex 5
                [lindex $peers 0] set tombstone value ex 5
                [lindex $peers 0] hset hash key value 
                [lindex $peers 0] expire hash 5
                [lindex $peers 1] set key value1
                [lindex $peers 1] set tombstone value1
                [lindex $peers 1] hset hash key value1
                after 5000
                assert_equal [[lindex $peers 0] dbsize] 3
                [lindex $peers 1] crdt.del_reg tombstone 2 [clock milliseconds] "2:2;3:1" 
                [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                # [lindex $peers 1] del tombstone
                wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 0]
                print_log_file [lindex $peer_stdouts 0]
                assert_equal [[lindex $peers 0] get key] ""
                assert_equal [[lindex $peers 0] hget hash key] ""
                assert_equal [[lindex $peers 0] dbsize] 2

            }
        }
    }
}