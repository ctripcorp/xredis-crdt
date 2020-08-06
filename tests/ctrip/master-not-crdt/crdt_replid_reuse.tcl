
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
# set server_path1 [tmpdir "master-redis-peer1"]
# set server_path2 [tmpdir "master-redis-peer1"]
proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}
start_redis [list overrides [list repl-diskless-sync-delay 1  ]] {
    set master {}
    set master_hosts {}
    set master_ports {}
    set master_stdouts {}

    set slave {}
    set slave_hosts {}
    set slave_ports {}
    set slave_stdouts {}
    set slave_gid {}

    lappend master [srv 0 client]
    lappend master_hosts [srv 0 host]
    lappend master_ports [srv 0 port]
    lappend master_stdouts [srv 0 stdout]
    [lindex $master 0] set k1 v1 
    [lindex $master 0] config set repl-diskless-sync-delay 1
    
    start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
        lappend slave [srv 0 client]
        lappend slave_hosts [srv 0 host]
        lappend slave_ports [srv 0 port]
        lappend slave_stdouts [srv 0 stdout]
        lappend slave_gid 1
        [lindex $slave 0] config set slave-read-only no
        [lindex $slave 0] config set repl-diskless-sync-delay 1
        [lindex $slave 0] config crdt.set repl-diskless-sync-delay 1
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            lappend slave [srv 0 client]
            lappend slave_hosts [srv 0 host]
            lappend slave_ports [srv 0 port]
            lappend slave_stdouts [srv 0 stdout]
            lappend slave_gid 1
            [lindex $slave 1] config set repl-diskless-sync-delay 1
            [lindex $slave 1] config crdt.set repl-diskless-sync-delay 1
            test "test" {
                [lindex $slave 0] slaveof   [lindex $master_hosts 0] [lindex $master_ports 0]
                wait [lindex $master 0] 0 info [lindex $slave_stdouts 0]
                [lindex $slave 1] slaveof [lindex $slave_hosts 0] [lindex $slave_ports 0]
                wait [lindex $slave 0] 0 info [lindex $slave_stdouts 1]
                [lindex $slave 0] slaveof no one 
                after 2000
                assert_equal [get_info_replication_attr_value [lindex $slave 0] crdt.info master_replid] [get_info_replication_attr_value [lindex $slave 1] crdt.info master_replid]
                assert_equal [get_info_replication_attr_value [lindex $slave 0] crdt.info master_replid2] [get_info_replication_attr_value [lindex $slave 1] crdt.info master_replid2]
                #print_log_file [lindex $slave_stdouts 1] 
            }
            
        }
    }
}


