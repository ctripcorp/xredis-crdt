

proc log_file_matches {log} {
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
        log_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
        
    }
}
proc check_slave {master slave} {
    assert  {
        [ get_info_replication_attr_value  $master info master_replid] 
        ==
        [ get_info_replication_attr_value $slave info master_replid]
    }
    assert  {
        [ get_info_replication_attr_value  $master info master_repl_offset] 
        ==
        [ get_info_replication_attr_value $slave info master_repl_offset]
    }
}
proc is_not_slave {master slave} {
    assert  {
        [ get_info_replication_attr_value  $master info master_replid] 
        !=
        [ get_info_replication_attr_value $slave info master_replid]
    }
}



set server_path [tmpdir "master-redis-slave-crdt"]
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
proc load_redis_rdb {add check server_path dbfile} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        run [replace_client $add {$master}]  1
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_gid 1
            $slave config crdt.set repl-diskless-sync-delay 1 
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_stdout
            run [replace_client $check {$slave}]  1
            # puts [log_file_matches $slave_stdout] 
            is_not_slave $master $slave

            start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so}} {
                set crdt_slave [srv 0 client]
                set crdt_slave_host [srv 0 host]
                set crdt_slave_port [srv 0 port]
                set crdt_slave_stdout [srv 0 stdout]
                set crdt_slave_gid 2
                $slave debug set-crdt-ovc 0
                $crdt_slave debug set-crdt-ovc 0
                $crdt_slave peerof $slave_gid $slave_host $slave_port
                $slave peerof $crdt_slave_gid $crdt_slave_host $crdt_slave_port
                wait $slave 0 crdt.info $slave_stdout
                test "master-slave" {
                    run [replace_client $check {$crdt_slave}]  1
                    # puts [log_file_matches $slave_stdout] 
                    check_peer_info $slave $crdt_slave 0
                } 
            }
        }
    }
}


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
        load_redis_rdb [format "$format_core" $format_add_core] [format "$format_core"  $format_check_core] $server_path [format "$rdbfile_core" $formate_rdbfile_core]
    }
    regsub -all {\$format_core} $str $format_core str
    regsub -all {\$format_add_core} $str $format_add_core str
    regsub -all {\$format_check_core} $str $format_check_core str
    regsub -all {\$rdbfile_core} $str $rdbfile_core str
    regsub -all {\$formate_rdbfile_core} $str $formate_rdbfile_core str
    return $str
}
proc run_foreach {num len} {
    set foreach_core "\$load_redis_rdb"
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
    regsub -all {\$load_redis_rdb} $foreach_core [replace_save $format_core  $format_add_core $format_check_core $rdbfile_core $formate_rdbfile_core] foreach_core
    # puts [format $foreach_core  [format ]]
    # puts $foreach_core
    run $foreach_core 2
    # puts $foreach_core
}


array set adds ""
set set_argvs {}
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
    assert_equal [$redis get rc4] 2.30000000000000000
    for {set i 0} {$i < 256} {incr i} {
        set a [i2b $i] 
        assert_equal [$redis get $a] $a 
        assert_equal [$redis hget hash_binary $a] $a
    }
    for {set i 0} {$i < 256} {incr i} {
        set argv  [lindex set_argvs $i]
        assert_equal [$redis get [lindex $argv 0]] [lindex $argv 1]
        assert_equal [$redis hget hash_random [lindex $argv 0]] [lindex $argv 1]
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
    $redis set key2 v ex 10000000
}
set checks(2) {
    assert {[$redis ttl key2] < 10000000}
}
set adds(3) {
    $redis set key3 v
    $redis del key3 
}
set checks(3) {
    assert_equal [$redis get key3] {}
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
#full sync
# set len [array size adds]
# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-%s" $i] {
#         run_foreach $i $len
#     }
# }
set len [array size adds]
test [format "master redis and peer slave"] {
    run_foreach $len $len
}