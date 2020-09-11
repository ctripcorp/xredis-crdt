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
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

proc get_dataset { client } {
    set info [$client memory stats]
    if {[regexp {dataset.bytes ([0-9]+)} $info _ value] == 1} {
        return $value
    }
    return 0
}
proc get_module_all_memory { client } {
    set info [$client crdt.memory]
    if {[regexp {module-memory: ([0-9]+)} $info _ module_memory] != 1} {
        error "get module memory error"
    }
    if {[regexp {key-memory: ([0-9]+)} $info _ key_memory] != 1} {
        error "get key memory error"
    }
    if {[regexp {moduleValue-memory: ([0-9]+)} $info _ rm_memory] != 1} {
        error "get robj and module memory error"
    }
    # puts $info
    return [expr $module_memory + $key_memory + $rm_memory]
}
proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait_flushall { client } {
    set retry 50
    while {$retry} {
        if {
            [$client dbsize] == 0 && 
            [$client expiresize] == 0 && 
            [$client tombstonesize] == 0 
        } {
            break
        } else {
            assert_equal [$client ping] PONG
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        puts [$client dbsize] 
        puts [$client expiresize]
        puts [$client tombstonesize]
        error "wait free all module momory fail"
    }
}
set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    test "kv" {
        set m [get_module_all_memory [lindex $peers 0]]
        set before_dataset [get_dataset [lindex $peers 0]]
        [lindex $peers 0] set k v
        set m1 [get_module_all_memory [lindex $peers 0]]
        assert {$m1 > 0}
        puts  [[lindex $peers 0] crdt.memory]
        puts  [expr [get_dataset [lindex $peers 0]] - $before_dataset]
        [lindex $peers 0] crdt.set k v1 2 [clock milliseconds] 2:1 
        set m2 [get_module_all_memory [lindex $peers 0]]
        assert {$m2 >= $m1}
        [lindex $peers 0] set k vvvvvvvvvvvvvvvvvvvvvvv
        set m3 [get_module_all_memory [lindex $peers 0]]
        assert {$m3 >= $m2}
        [lindex $peers 0] del k
        [lindex $peers 0] set k1 v1
        set time [clock milliseconds]
        [lindex $peers 0] crdt.del_reg k1 1 [incr time 100] 1:10
        wait_flushall [lindex $peers 0]
        assert_equal [get_module_all_memory [lindex $peers 0]] $m
    }
    test "hash" {
        set m [get_module_all_memory [lindex $peers 0]]
        [lindex $peers 0] hset h k v
        set m1 [get_module_all_memory [lindex $peers 0]]
        assert {$m1 > 0}
        [lindex $peers 0] crdt.hset h 2 [clock milliseconds] 2:1 2 k v1
        set m2 [get_module_all_memory [lindex $peers 0]]
        assert {$m2 >= $m1}
        [lindex $peers 0] del h
        [lindex $peers 0] hset h1 k v
        [lindex $peers 0] hdel h1 k 
        [lindex $peers 0] hset h2 k v
        [lindex $peers 0] CRDT.REM_HASH h2 1 [clock milliseconds] "1:20;2:1" k
        [lindex $peers 0] hset h3 k v
        [lindex $peers 0] CRDT.DEL_HASH h3 1 [clock milliseconds] "1:30;2:1" "1:30;2:1"
        wait_flushall [lindex $peers 0]
        assert_equal [get_module_all_memory [lindex $peers 0]] $m
    }
    test "expire" {
        set m [get_module_all_memory [lindex $peers 0]]
        [lindex $peers 0] setex k 5 v
        set time [clock milliseconds]
        [lindex $peers 0] hset h k v 
        [lindex $peers 0] crdt.expire h 2 [incr time 1] [incr time 1] 1
        after 5000
        wait_flushall [lindex $peers 0]
        # puts [get_module_all_memory [lindex $peers 0]]
        assert_equal [get_module_all_memory [lindex $peers 0]] $m
    }
    test "flushall" {
        [lindex $peers 0] set k v 
        assert {[get_module_all_memory [lindex $peers 0]] > 0}
        [lindex $peers 0] flushall
        assert {[get_module_all_memory [lindex $peers 0]] == 0}
    }
    test "flushdb" {
        [lindex $peers 0] set k v 
        assert {[get_module_all_memory [lindex $peers 0]] > 0}
        [lindex $peers 0] flushdb
        assert {[get_module_all_memory [lindex $peers 0]] == 0}
    }
    test "add kv memory" {
        [lindex $peers 0] set k v
        set before_mm [get_module_all_memory [lindex $peers 0]]
        set before_dataset [get_dataset [lindex $peers 0]]
        [lindex $peers 0] set k1 v1
        [lindex $peers 0] set k2 v3
        set after_mm [get_module_all_memory [lindex $peers 0]]
        set after_dataset  [get_dataset [lindex $peers 0]]
        assert {[expr $after_mm - $before_mm] <= [expr $after_dataset - $before_dataset]}
    }
    test "add hash memory" {
        [lindex $peers 0] hset h k v
        set before_mm [get_module_all_memory [lindex $peers 0]]
        set before_dataset [get_dataset [lindex $peers 0]]
        [lindex $peers 0] hset h k1 k1
        [lindex $peers 0] hset h k2 k3
        set after_mm [get_module_all_memory [lindex $peers 0]]
        set after_dataset  [get_dataset [lindex $peers 0]]
        assert {[expr $after_mm - $before_mm] <= [expr $after_dataset - $before_dataset]}
    }
    start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_hosts [srv 0 host]
            set slave_ports [srv 0 port]
            set slave_stdouts [srv 0 stdout]
            set slave_gids 1
            $slave config crdt.set repl-diskless-sync-delay 1
            $slave config set repl-diskless-sync-delay 1
            test "peer and slave" {
                set m [get_module_all_memory [lindex $peers 0]]
                [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                $slave slaveof  [lindex $peer_hosts 0] [lindex $peer_ports 0]
                wait [lindex $peers 0] 0 info [lindex $peer_stdouts 0]
                wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
                set info [[lindex $peers 0] crdt.datainfo k]
                assert_equal $info [[lindex $peers 1] crdt.datainfo k]
                assert_equal $info [$slave crdt.datainfo k]
                
                set info [[lindex $peers 0] crdt.datainfo h]
                assert_equal $info [[lindex $peers 1] crdt.datainfo h]
                assert_equal $info [$slave crdt.datainfo h]
                assert_equal $m [get_module_all_memory [lindex $peers 0]]
                assert_equal $m [get_module_all_memory [lindex $peers 1]]
                assert_equal $m [get_module_all_memory $slave]
                [lindex $peers 0] set k v123
                set m1 [get_module_all_memory [lindex $peers 0]]
                assert_equal $m1 [get_module_all_memory [lindex $peers 1]]
                assert_equal $m1 [get_module_all_memory $slave]
                [lindex $peers 0] hset h k v123
                set m2 [get_module_all_memory [lindex $peers 0]]
                assert_equal $m2 [get_module_all_memory [lindex $peers 1]]
                assert_equal $m2 [get_module_all_memory $slave]
            }
             

        }
    }
}


