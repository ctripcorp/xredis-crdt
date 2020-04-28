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
        log_file_matches $log
    }
}
set server_path [tmpdir "add-sync-stop"]
start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        set n 10000
        for {set j 0} {$j <= $n } {incr j} {
            $master set [format "key-%s" $j] [format "value-%s" $j]
        }
        $slave slaveof $master_host $master_port
        # wait $master 0 info $slave_stdout
        set killed 0
        for {set j 0} {$j <= 200} {incr j} { 
            if {[log_file_matches $slave_stdout "*Full resync from master:*"] == 1} {
                kill_slave $master
                set killed 1
                break
            } else {
                after 100
            }
        }
        assert { $killed eq {1} }
        puts [$slave dbsize] 
        set trysync 0
        for {set j 0} {$j <= 500} {incr j} {
            if {[log_file_matches $slave_stdout "*I/O error trying to sync with MASTER:*"]} {
                set trysync 1
                break
            } else {
                after 100
            }
        }
        # print_log_file $slave_stdout
        # assert { $trysync eq {1} }
        wait $master 0 info $slave_stdout 
        assert  {
            [ get_info_replication_attr_value  $master info master_replid] 
            != 
            [ get_info_replication_attr_value $slave info master_replid]
        }
        assert_equal [$master dbsize] [$slave dbsize]
        # for {set j 0} {$j <= $n } {incr j} {
        #     assert_equal [$slave get [format "key-%s" $j]] [format "value-%s" $j]
        # }
        
    }
}