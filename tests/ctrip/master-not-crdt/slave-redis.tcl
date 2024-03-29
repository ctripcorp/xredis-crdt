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
start_server {tags {"master"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    $master set key value
    assert_equal [$master get key] value
    start_redis {tags {"slave"} config {redis/redis.conf} overrides {repl-diskless-sync-delay 1}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        $slave slaveof $master_host $master_port
        # wait $master 0 info $slave_stdout
        set retry 50
        while {$retry} {
            if {[log_file_matches $slave_stdout "*Slave is not crdt*"] == 1} {
                break
            } else {
                incr retry -1
                after 100
            }
        }
        # print_log_file $slave_stdout
        assert {$retry > 0}
    }
}