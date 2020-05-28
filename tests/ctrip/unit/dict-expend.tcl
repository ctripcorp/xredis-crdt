proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc print_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait_full_sync_start { log}  {
    set retry 1000
    set match_str ""
    while {$retry} {
        if {[log_file_matches $log "*Diskless sync started*"]} {
            break
        } else {
            incr retry -1
            after 5
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        assert_equal [$client ping] PONG
        print_file $log
        error "assertion: Master-Slave not correctly synchronized"
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
start_server {tags {"crdt-dict"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    test {"set config dict-expand-max-idle-size"} {
        assert_equal [lindex [r config get dict-expand-max-idle-size] 1] 134217728
        r config set dict-expand-max-idle-size 32
        assert_equal [lindex [r config get dict-expand-max-idle-size] 1] 32
    }
}
start_server {tags {"crdt-dict"} overrides {crdt-gid 1 dict-expand-max-idle-size 32} config {crdt.conf} module {crdt.so} } {
    test {"file config dict-expand-max-idle-size"} {
        assert_equal [lindex [r config get dict-expand-max-idle-size] 1] 32
    }
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_gid 1
    set master_stdout [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    $master set k v
    for {set i 10000} {$i < 18192} {incr i} {
        $master set $i $i
    }
    start_server {tags {"crdt-dict"} overrides {crdt-gid 1 dict-expand-max-idle-size 32} config {crdt.conf} module {crdt.so} } {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_gid 1
        $slave slaveof $master_host $master_port
        wait_full_sync_start  $master_stdout
        for {set i 0} {$i < 10} {incr i} {
            $master set $i $i
        }
        wait $master 0 info $master_stdout 
        print_file $master_stdout
        for {set i 10} {$i < 20} {incr i} {
            $master set $i $i
        }
        after 10000
        # 8212 * 40 + 8192 * 8 * 4 = 590624
        # 8212 * 40 + 8192 * 8 * 2 = 459592
        if {![string match "*overhead.hashtable.main 459592*" [r memory stats]]} {
            puts [$master memory stats]
            error "full-sync dict add rehash error"
        }
        
    }
}
