
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc print_log_content {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc crdt_status { client property } {
    set info [ $client crdt.info stats]
    if {[regexp "\r\n$property:(.*?)\r\n" $info _ value]} {
        set _ $value
    }
}
proc write_batch_data {host port time} {
    # Start to write random val(set k v). for 1 sec
    # the data will be used in full-sync
    set load_handle0 [start_write_load $host $port 3]
    set load_handle1 [start_write_load $host $port 5]
    set load_handle2 [start_write_load $host $port 20]
    set load_handle3 [start_write_load $host $port 8]
    set load_handle4 [start_write_load $host $port 4]

    after $time
    # Stop the write load
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    stop_write_load $load_handle2
    stop_write_load $load_handle3
    stop_write_load $load_handle4
}
proc wait { client index type log}  {
    set retry 500
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
        print_log_content $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_gid  1
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set  repl-backlog-size 104857600
    start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        set slave_gid  1
        $slave config crdt.set repl-diskless-sync-delay 1
        $slave config set repl-diskless-sync-delay 1
        $slave config crdt.set repl-backlog-size 104857600
        $slave config crdt.set repl-backlog-ttl 10
        $slave slaveof $master_host $master_port
        wait $master 0 info $master_stdout
        start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_stdout [srv 0 stdout]
            set peer_gid  2
            $master set key value
            test "free-replication-block" {
                $master peerof $peer_gid $peer_host $peer_port
                $peer peerof $master_gid $master_host $master_port
                write_batch_data $master_host $master_port 10000
                $peer peerof $slave_gid 127.0.0.1 0

                # puts [$slave crdt.info replication]
                $slave slaveof no one
                after 1000
                $peer peerof $slave_gid $slave_host $slave_port
                
                wait $slave 0 crdt.info $slave_stdout
                # puts [$slave crdt.info stats]
                set sync_partial_ok [ crdt_status $slave "sync_partial_ok" ]
                if {$sync_partial_ok==0} {
                    print_log_content $slave_stdout
                    # print_log_content $master_stdout
                    fail "crdt sync_partial_error"
                }
            }
        }
    }
}