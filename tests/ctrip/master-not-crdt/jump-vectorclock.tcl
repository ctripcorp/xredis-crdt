proc print_file {log} {
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
        print_file $log
        error "assertion: Master-Slave not correctly synchronized"
        
    }
}
proc read_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
    # puts $content
}
set server_path [tmpdir "jump-vectorclock"]
exec cp tests/assets/redis/dump.rdb $server_path
exec cp tests/assets/crdt.so $server_path
start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path ]]  {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    test "check value1" {
        assert_equal [get_info_replication_attr_value $master crdt.info ovc] "1:10004"
    }
    start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        $slave slaveof $master_host $master_port
        wait $master 0 info $slave_stdout
        $slave slaveof no one 
        assert_equal [get_info_replication_attr_value $slave crdt.info ovc] "1:20004"
        after 5000
        read_file_matches [srv 0 config_file] "*crdt-clockunit 20004*"
    }
}


