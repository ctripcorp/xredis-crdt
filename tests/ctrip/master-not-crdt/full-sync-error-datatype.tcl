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
proc run {script level} {
    catch [uplevel $level $script ] result opts
}
proc replace_client { str client } {
    regsub -all {\$redis} $str $client str
    return $str
}
proc replace { str argv } {
    set len [llength $argv]
    for {set i 0} {$i < $len} {incr i} {
        set regstr [format {\$%s} $i]
        # puts [lindex $argv $i]
        regsub -all $regstr $str [lindex $argv $i] str
    }
    return $str
}

proc full-sync-error-data {add server_path} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        # $master lpush runoob redis
        run [replace_client $add {$master}]  1
        start_server {config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            $slave slaveof $master_host $master_port
            # wait $master 0 info $slave_stdout
            set retry 50
            set match_str ""
            append match_str "*slave" 0 ":*state=online*"
            while {$retry} {
                set info [ $master info replication ]
                if {[string match $match_str $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            assert_equal [$slave dbsize] 0
            assert_equal [log_file_matches $slave_stdout "*crdt load not crdt rdb datatype error*"] 1
        }
    }
}

test "lpush" {
    set server_path [tmpdir "full-sync-error-datatype-lpush"]
    full-sync-error-data {
        $redis lpush runoob redis
    } $server_path
}

test "sadd" {
    set server_path [tmpdir "full-sync-error-datatype-sadd"]
    full-sync-error-data {
        $redis sadd runoob redis
    } $server_path
}


# test "kv int" {
#     set server_path [tmpdir "kv-int"]
#     full-sync-error-data {
#         $redis set k 1
#     } $server_path
# }
