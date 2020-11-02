
proc log_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
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
proc wait_save { client log}  {
    set retry 50
    append match_str1 "*rdb_bgsave_in_progress:0*"
    append match_str2 "*rdb_last_bgsave_status:ok*"
    while {$retry} {
        set info [ $client info persistence ]
        if {[string match $match_str1 $info]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        puts [ $client info persistence ]
        error "assertion: Master-Slave not correctly synchronized"
    }
    set info [ $client info persistence ]
    if {![string match $match_str2 $info]} {
        log_file_matches $log
        error "save fail"
    } 
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
proc save {add check server_path dl} {
    cp_crdt_so $server_path
    start_server {tags {"master"} overrides {crdt-gid 1} module {./crdt.so} } {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_gids {}
        set peer_stdouts {}
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 1
        [lindex $peers 0] config set repl-diskless-sync $dl
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        [lindex $peers 0] debug set-crdt-ovc 0
        start_server {tags {"save"} overrides {crdt-gid 2} module {./crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_gids 2
            
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            
            wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 0]
            wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 1]
            [lindex $peers 1] debug set-crdt-ovc 0
            run [replace_client $add {[lindex $peers 0]}]  1
            start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so dir $server_path]] {
                set slave [srv 0 client]
                set slave_hosts [srv 0 host]
                set slave_ports [srv 0 port]
                set slave_stdouts [srv 0 stdout]
                set slave_gids 1
                $slave slaveof  [lindex $peer_hosts 0] [lindex $peer_ports 0]
                # log_file_matches $slave_stdouts
                wait [lindex $peers 0] 0 info [lindex $peer_stdouts 1]
                # log_file_matches $slave_stdouts
                # log_file_matches [lindex $peer_stdouts 0]
                run [replace_client $check {$slave}]  1
            }
        }
    }
}
array set adds ""

set adds(0) {
    $redis set key value
    $redis set rc1 10
    $redis incrby rc2 1
    $redis set rc3 5
    $redis incrby rc3 1
    $redis set rc4 1.1
    $redis incrbyfloat rc4 1.2
    for {set i 0} {$i < 256} {incr i} {
        set a [i2b $i] 
        $redis set a a 
        $redis hset hashb a a
    }
}
set checks(0) {
    assert_equal [$redis get key] value
    assert_equal [$redis get rc1] 10
    assert_equal [$redis get rc2] 1
    assert_equal [$redis get rc3] 6
    assert_equal [$redis get rc4] 2.30000000000000000
    for {set i 0} {$i < 256} {incr i} {
        set a [i2b $i] 
        assert_equal [$redis get a] a 
        assert_equal [$redis hget hashb a] a
    }
}
set adds(1) {
    $redis hset hash k1 v1 k2 v2
    $redis hset hash1 k0 v0 k1 v1 k2 v2 k3 v3 k4 v4 k5 v5 k6 v6 k7 v7 k8 v8 k9 v9 
}
set checks(1) {
    assert_equal [$redis hget hash k1] v1
    assert_equal [$redis hget hash k2] v2
    assert_equal [$redis hget hash1 k0] v0
    assert_equal [$redis hget hash1 k1] v1
    assert_equal [$redis hget hash1 k2] v2
    assert_equal [$redis hget hash1 k3] v3
    assert_equal [$redis hget hash1 k4] v4
    assert_equal [$redis hget hash1 k5] v5
    assert_equal [$redis hget hash1 k6] v6
    assert_equal [$redis hget hash1 k7] v7
    assert_equal [$redis hget hash1 k8] v8
    assert_equal [$redis hget hash1 k9] v9
}
set adds(2) {
    $redis crdt.set kv value 1 1000000 "1:100"
    $redis crdt.del_reg kv 2 1000000 "1:100;2:100;3:100"
}
set checks(2) {
    assert_equal [$redis tombstonesize] 1
}
set adds(3) {
    $redis set key2 v ex 10000000
}
set checks(3) {
    assert {[$redis ttl key2] < 10000000}
    assert {[$redis ttl key2] > -1}
}

set len [array size adds]
test "one" {
    for {set x 0} {$x<$len} {incr x} {
        save $adds($x) $checks($x) [tmpdir [format "rdb2.1.1.%s" $x]] yes
        save $adds($x) $checks($x) [tmpdir [format "rdb2.1.2.%s" $x]] no
    }
}

test "two" {
    for {set x 0} {$x<$len} {incr x} {
        for {set y $x} {$y<$len} {incr y} {
            if { $x == $y} {
                continue
            }
            save [format "%s;%s" $adds($x) $adds($y)] [format "%s;%s" $checks($x) $checks($y)] [tmpdir [format "rdb2.2.1.%s" $x]] yes
            save [format "%s;%s" $adds($x) $adds($y)] [format "%s;%s" $checks($x) $checks($y)] [tmpdir [format "rdb2.2.2.%s" $x]] no
        }
    }
}
