proc get_kill_client_addr { clients_info } {
    set lines [split $clients_info "\r\n"]
    set len [llength $lines]
    for {set j 0} {$j < $len} {incr j} { 
        set line [lindex $lines $j] 
        if { [regexp {(.*?)(cmd=client)$} $line match] != 1} {
            if {[regexp {addr=(.*?) fd=(.*?)} $line match addr ]} {
                return $addr
            }  
        }   
    }
}
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc kill_slave {client} {
    set kill_addr [get_kill_client_addr [$client CLIENT LIST] ]
    if {$kill_addr != {}} {
        $client client kill  $kill_addr
        set killed 1
    }
}
proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
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
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        print_log_file $log
    }
}
set server_path [tmpdir "add-sync-stop"]
start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    $master set key value
    start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        $slave slaveof $master_host $master_port
        wait $master 0 info $slave_stdout
        assert_equal [$slave get key] value
        
        assert  {
            [ get_info_replication_attr_value  $master info master_replid] 
            != 
            [ get_info_replication_attr_value $slave info master_replid]
        }

        start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set crdt_slave [srv 0 client]
            set crdt_slave_host [srv 0 host]
            set crdt_slave_port [srv 0 port]
            set crdt_slave_stdout [srv 0 stdout]
            $crdt_slave slaveof $slave_host $slave_port
            wait $slave 0 info $slave_stdout
            test "master-slave" {
                assert_equal [$crdt_slave get key] value
                assert_equal [log_file_matches $slave_stdout "*MASTER <-> SLAVE sync: Master accepted a Partial Resynchronization.*"] 0
                set psync_count [status $master sync_partial_ok]
                kill_slave $master

                $master hset hash k v
                wait $master 0 info $slave_stdout
                assert_equal [status $master sync_partial_ok] [incr $psync_count 1]
                assert_equal [log_file_matches $slave_stdout "*MASTER <-> SLAVE sync: Master accepted a Partial Resynchronization.*"] 1
                assert_equal [$slave hget hash k] v
                
            } 
        }
    }
}