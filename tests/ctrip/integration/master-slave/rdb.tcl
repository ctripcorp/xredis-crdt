
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
set server_path [tmpdir "server.rdb1"]

# Copy RDB with different encodings in server path
# exec cp tests/assets/encodings.rdb $server_path
cp_crdt_so $server_path

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
proc save {add check server_path dbfile} {
    start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" $dbfile]] {
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
            test [format "bgsave %s" $dbfile] {
                [lindex $peers 0] peerof [lindex $peer_gids 1] no one 
                run [replace_client $add {[lindex $peers 0]}]  1
                [lindex $peers 0] bgsave
            }
        }
    }
    #load rdb
    start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" $dbfile]] {
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
        
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        run [replace_client $check {[lindex $peers 0]}]  1
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
        $redis set $a $a 
        $redis hset hash_binary $a $a
    }
    for {set i 0} {$i < 256} {incr i} {
        set argv {}
        lappend argv [randomKey] 
        lappend argv [randomValue] 
        lappend set_argvs $argv
        $redis set [lindex $argv 0] [lindex $argv 1]
        $redis hset hash_random [lindex $argv 0] [lindex $argv 1]
    }
}
set checks(0) {
    assert_equal [$redis get key] value
    assert_equal [$redis get rc1] 10
    assert_equal [$redis get rc2] 1
    assert_equal [$redis get rc3] 6
    # assert_equal [$redis get rc4] 2.3
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
    # assert_equal [$redis tombstonesize] 3
}
set adds(3) {
    $redis set key2 v2 ex 10000000
}
set checks(3) {
    assert {[$redis ttl key2] <= 10000000}
    assert {[$redis ttl key2] > -1}
}
set adds(4) {
    $redis sadd key4 s1 
    $redis sadd key5 s1 s2
    $redis sadd key6 s1 s2
    $redis srem key6 s1 
    $redis sadd key7 s1 s2
    $redis del key7 
}
set checks(4) {
    assert_equal [$redis SISMEMBER key4 s1] 1
    assert_equal [$redis SISMEMBER key5 s1] 1
    assert_equal [$redis SISMEMBER key5 s2] 1
    assert_equal [$redis SISMEMBER key6 s1] 0
    assert_equal [$redis SISMEMBER key6 s2] 1
    assert_equal [$redis SISMEMBER key7 s1] 0
}
set adds(5) {
    $redis zadd myzset1 1 a 
    $redis zadd myzset2 1 a 2 b
    $redis zadd myzset3 1 a 2 b
    $redis zrem myzset3 a 
    $redis zadd myzset4 1 a 2 b
    $redis del myzset4
    $redis zadd myzset5 1 a 2 b
    $redis zrem myzset5 a 
    $redis zadd myzset5 3 a 
    $redis zadd myzset6 1 a 2 b
    $redis del myzset6 a 
    $redis zadd myzset6 3 a 
}
set checks(5) {
    assert_equal [$redis zscore myzset1 a] 1
    assert_equal [$redis zscore myzset2 a] 1
    assert_equal [$redis zscore myzset2 b] 2
    assert_equal [$redis zscore myzset3 a] {}
    assert_equal [$redis zscore myzset3 b] 2
    assert_equal [$redis zscore myzset4 a] {}
    assert_equal [$redis zscore myzset4 b] {}
    assert_equal [$redis zscore myzset5 a] 3
    assert_equal [$redis zscore myzset6 a] 3
}
set len [array size adds]
proc replace_foreach {  index  len core} {
    set str {
        for {set i$index [expr $i$prev + 1]} {$i$index< $len } {incr i$index} {
            $core
        }
    }
    regsub -all {\$index} $str $index str
    regsub -all {\$prev} $str [expr $index -1] str
    regsub -all {\$core} $str $core str
    regsub -all {\$len} $str $len str
    return $str
}
proc replace_save {  format_core  format_add_core format_check_core rdbfile_core formate_rdbfile_core} {
    set str {
        save [format "$format_core" $format_add_core] [format "$format_core"  $format_check_core] $server_path [format "$rdbfile_core" $formate_rdbfile_core]
    }
    regsub -all {\$format_core} $str $format_core str
    regsub -all {\$format_add_core} $str $format_add_core str
    regsub -all {\$format_check_core} $str $format_check_core str
    regsub -all {\$rdbfile_core} $str $rdbfile_core str
    regsub -all {\$formate_rdbfile_core} $str $formate_rdbfile_core str
    return $str
}
proc run_foreach {num len} {
    set foreach_core "\$save"
    set format_core "%s"
    set format_add_core  ""
    set format_check_core ""
    set rdbfile_core "test.%s"
    set formate_rdbfile_core ""
    for {set i $num} {$i > 1} {incr i -1} {
        append format_core ";%s"
        append format_add_core   [format " \$adds(\$i%s)" $i]
        append format_check_core [format " \$checks(\$i%s)" $i]
        append rdbfile_core ".%s"
        append formate_rdbfile_core [format " \$i%s" $i]
        set foreach_core [replace_foreach $i $len $foreach_core]
    }
    append format_add_core  " \$adds(\$i1)"
    append format_check_core " \$checks(\$i1)" 
    append formate_rdbfile_core " \$i1" 
    set foreach_core [format {
        for {set i1 0} {$i1<%s} {incr i1} {
            %s
        }
    } $len $foreach_core]
    regsub -all {\$save} $foreach_core [replace_save $format_core  $format_add_core $format_check_core $rdbfile_core $formate_rdbfile_core] foreach_core
    # puts [format $foreach_core  [format ]]
    run $foreach_core 2
    # puts $foreach_core
}

# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-%s" $i] {
#         run_foreach $i $len
#     }
# }
test [format "foreach-%s" $len] {
    run_foreach $len $len
}
