
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
    puts [ get_info_replication_attr_value  $peerMaster crdt.info master_repl_offset] 
    puts [ get_info_replication_attr_value $peerSlave crdt.info $attr]
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
# set server_path1 [tmpdir "master-redis-peer1"]
# set server_path2 [tmpdir "master-redis-peer1"]


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
    [lindex $master 0] config set repl-diskless-sync-delay 1
    start_redis [list overrides [list repl-diskless-sync-delay 1  ]] {
        lappend master [srv 0 client]
        lappend master_hosts [srv 0 host]
        lappend master_ports [srv 0 port]
        lappend master_stdouts [srv 0 stdout]
        [lindex $master 1] config set repl-diskless-sync-delay 1
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            lappend slave [srv 0 client]
            lappend slave_hosts [srv 0 host]
            lappend slave_ports [srv 0 port]
            lappend slave_stdouts [srv 0 stdout]
            lappend slave_gid 1
            [lindex $slave 0] config set repl-diskless-sync-delay 1
            [lindex $slave 0] config crdt.set repl-diskless-sync-delay 1
            start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
                lappend slave [srv 0 client]
                lappend slave_hosts [srv 0 host]
                lappend slave_ports [srv 0 port]
                lappend slave_stdouts [srv 0 stdout]
                lappend slave_gid 2
                [lindex $slave 1] config set repl-diskless-sync-delay 1
                [lindex $slave 1] config crdt.set repl-diskless-sync-delay 1
                test "value1" {
                    [lindex $slave 0] slaveof [lindex $master_hosts 0] [ lindex $master_ports 0]
                    [lindex $slave 1] slaveof [lindex $master_hosts 1] [ lindex $master_ports 1]
                    wait [lindex $master 0] 0 info [lindex $master_stdouts 1]
                    wait [lindex $master 1] 0 info [lindex $master_stdouts 0]
                    # [lindex $slave 0] config set Slave-read-only no
                    # [lindex $slave 1] config set Slave-read-only no
                    [lindex $slave 0] peerof [lindex $slave_gid 1] [lindex $slave_hosts 1] [lindex $slave_ports 1]
                    [lindex $slave 1] peerof [lindex $slave_gid 0] [lindex $slave_hosts 0] [lindex $slave_ports 0]
                    wait [lindex $slave 0] 0 crdt.info [lindex $slave_stdouts 1]
                    wait [lindex $slave 1] 0 crdt.info [lindex $slave_stdouts 0]
                    
                    [lindex $master 0] set key value
                    [lindex $master 1] hset hash k v
                    after 500
                    # print_log_file [lindex $slave_stdouts 0]
                    assert_equal [[lindex $slave 0] get key] value
                    # print_log_file [lindex $slave_stdouts 1]
                    assert_equal [[lindex $slave 1] hget hash k] v 
                    after 500
                    assert_equal [[lindex $slave 1] get key] value
                    assert_equal [[lindex $slave 0] hget hash k] v 
                    check_peer [lindex $slave 0] [lindex $slave 1] 0
                    check_peer [lindex $slave 1] [lindex $slave 0] 0

                }
                
            }
        }
    }
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
    start_redis [list overrides [list repl-diskless-sync-delay 1  ]] {
        lappend master [srv 0 client]
        lappend master_hosts [srv 0 host]
        lappend master_ports [srv 0 port]
        lappend master_stdouts [srv 0 stdout]
        [lindex $master 1] set k2 v2
        [lindex $master 1] config set repl-diskless-sync-delay 1
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            lappend slave [srv 0 client]
            lappend slave_hosts [srv 0 host]
            lappend slave_ports [srv 0 port]
            lappend slave_stdouts [srv 0 stdout]
            lappend slave_gid 1
            [lindex $slave 0] config set repl-diskless-sync-delay 1
            [lindex $slave 0] config crdt.set repl-diskless-sync-delay 1
            start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
                lappend slave [srv 0 client]
                lappend slave_hosts [srv 0 host]
                lappend slave_ports [srv 0 port]
                lappend slave_stdouts [srv 0 stdout]
                lappend slave_gid 2
                [lindex $slave 1] config set repl-diskless-sync-delay 1
                [lindex $slave 1] config crdt.set repl-diskless-sync-delay 1
                test "value" {
                    [lindex $slave 0] slaveof [lindex $master_hosts 0] [ lindex $master_ports 0]
                    [lindex $slave 1] slaveof [lindex $master_hosts 1] [ lindex $master_ports 1]
                    wait [lindex $master 0] 0 info [lindex $master_stdouts 1]
                    wait [lindex $master 1] 0 info [lindex $master_stdouts 0]
                    # [lindex $slave 0] config set Slave-read-only no
                    # [lindex $slave 1] config set Slave-read-only no
                    [lindex $slave 0] peerof [lindex $slave_gid 1] [lindex $slave_hosts 1] [lindex $slave_ports 1]
                    [lindex $slave 1] peerof [lindex $slave_gid 0] [lindex $slave_hosts 0] [lindex $slave_ports 0]
                    wait [lindex $slave 0] 0 crdt.info [lindex $slave_stdouts 1]
                    wait [lindex $slave 1] 0 crdt.info [lindex $slave_stdouts 0]
                    assert_equal [[lindex $slave 0] get k1] v1
                    assert_equal [[lindex $slave 0] get k2] v2
                    assert_equal [[lindex $slave 1] get k1] v1
                    assert_equal [[lindex $slave 1] get k2] v2
                    [lindex $master 0] set key value
                    [lindex $master 1] hset hash k v
                    after 500
                    assert_equal [[lindex $slave 0] get key] value
                    assert_equal [[lindex $slave 1] hget hash k] v 
                    after 500
                    assert_equal [[lindex $slave 1] get key] value
                    assert_equal [[lindex $slave 0] hget hash k] v 
                    print_log_file [lindex $slave_stdouts 1]
                    check_peer [lindex $slave 0] [lindex $slave 1] 0
                    check_peer [lindex $slave 1] [lindex $slave 0] 0

                }
                
            }
        }
    }
}


