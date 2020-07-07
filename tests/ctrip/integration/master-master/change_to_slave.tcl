
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

proc write_batch_data {host port} {
    # Start to write random val(set k v). for 1 sec
    # the data will be used in full-sync
    set load_handle0 [start_write_load $host $port 3]
    set load_handle1 [start_write_load $host $port 5]
    set load_handle2 [start_write_load $host $port 20]
    set load_handle3 [start_write_load $host $port 8]
    set load_handle4 [start_write_load $host $port 4]

    after 1000
    # Stop the write load
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    stop_write_load $load_handle2
    stop_write_load $load_handle3
    stop_write_load $load_handle4
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
        log_file_matches $log
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
    start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        set slave_gid  1
        $slave config crdt.set repl-diskless-sync-delay 1
        $slave config set repl-diskless-sync-delay 1
        start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_stdout [srv 0 stdout]
            set peer_gid  2
            test "change_to_slave" {
                $peer config crdt.set repl-diskless-sync-delay 1
                $peer config set repl-diskless-sync-delay 1
                write_batch_data $master_host $master_port
                $slave slaveof $master_host $master_port
                $peer peerof $master_gid $master_host $master_port
                wait $master 0 info $master_stdout
                wait $master 0 crdt.info $master_stdout
                after 5000
                $slave slaveof no one 
                $master slaveof $slave_host $slave_port
                write_batch_data $slave_host $slave_port
                wait $slave 0 info $slave_stdout
                after 5000
                assert_equal [$slave dbsize] [$master dbsize]
                assert_equal [log_file_matches $peer_stdout "*lost.*"] 1
            }
        }
    }
}