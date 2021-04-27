proc log_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc read_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    # string match $pattern $content
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
        log_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
        
    }
}
set server_path [tmpdir "load-redis-rdb"]
exec cp tests/assets/non-crdt.rdb $server_path/dump.rdb
cp_crdt_so $server_path
start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path]]  {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master select 0
    assert_equal [$master dbsize]  1
    catch { $master shutdown } error
}
set server_path1 [tmpdir "load-redis-rdb1"]
exec cp tests/assets/non-crdt.rdb $server_path1/dump.rdb
cp_crdt_so $server_path1
start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path1 local-clock 100]]  {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master select 0
    assert_equal [$master dbsize] 0
}


