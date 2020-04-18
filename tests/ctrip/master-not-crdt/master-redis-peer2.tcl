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
proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}
proc check_peer {peerMaster  peerSlave masteindex} {
    set attr [format "peer%d_repl_offset" $masteindex]
    assert  {
        [ get_info_replication_attr_value  $peerMaster crdt.info master_repl_offset] 
        ==
        [ get_info_replication_attr_value $peerSlave crdt.info $attr]
    }
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
        print_log_file $log
        error "assertion: Master-Slave not correctly synchronized"
        
    }
}
set server_path [tmpdir "inited-not-full-sync1"]
start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    $master set k1 v1
    start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        set slave_gid 1
        $slave config crdt.set repl-diskless-sync-delay 1 
        # $slave debug set-crdt-ovc 0
        # run [replace_client $check {$slave}]  1
        
        # puts [log_file_matches $slave_stdout] 
        assert  {
            [ get_info_replication_attr_value  $master info master_replid] 
            != 
            [ get_info_replication_attr_value $slave info master_replid]
        }

        start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
            set crdt_slave [srv 0 client]
            set crdt_slave_host [srv 0 host]
            set crdt_slave_port [srv 0 port]
            set crdt_slave_stdout [srv 0 stdout]
            
            
            test "master-slave" {
                $crdt_slave peerof $slave_gid $slave_host $slave_port
                wait $slave 0 crdt.info $slave_stdout
                $slave slaveof $master_host $master_port
                wait $master 0 info $master_stdout
                assert_equal [$slave get k1] v1
                wait $slave 0 crdt.info $slave_stdout
                # print_log_file $slave_stdout
                assert_equal [$crdt_slave get k1] v1
                $master set k2 v2
                after 1000
                assert_equal [$crdt_slave get k2] v2
                check_peer $slave $crdt_slave 0
                $master del k2
                after 1000
                assert_equal [$crdt_slave get k2] {}
                check_peer $slave $crdt_slave 0
            } 
        }
    }
}