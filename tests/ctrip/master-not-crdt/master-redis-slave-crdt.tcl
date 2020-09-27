
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
proc replace_save { fun_name  format_core  format_add_core format_check_core rdbfile_core formate_rdbfile_core} {
    set str {
        $fun_name [format "$format_core" $format_add_core] [format "$format_core"  $format_check_core] $server_path [format "$rdbfile_core" $formate_rdbfile_core]
    }
    regsub -all {\$fun_name} $str $fun_name str
    regsub -all {\$format_core} $str $format_core str
    regsub -all {\$format_add_core} $str $format_add_core str
    regsub -all {\$format_check_core} $str $format_check_core str
    regsub -all {\$rdbfile_core} $str $rdbfile_core str
    regsub -all {\$formate_rdbfile_core} $str $formate_rdbfile_core str
    return $str
}
proc run_foreach {fun_name num len} {
    set foreach_core "\$fun_name"
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
    regsub -all {\$fun_name} $foreach_core [replace_save $fun_name $format_core  $format_add_core $format_check_core $rdbfile_core $formate_rdbfile_core] foreach_core
    # puts [format $foreach_core  [format ]]
    # puts $foreach_core
    run $foreach_core 2
    # puts $foreach_core
}


array set adds ""
set adds(0) {
    $redis set key value
}
set checks(0) {
    assert_equal [$redis get key] value
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
    $redis set key2 v 
    $redis expire key2 10000000
    $redis hset hash2 k v
    $redis expire hash2 10000000
}
set checks(2) {
    assert_equal [$redis hget hash2 k]  v
    assert {[$redis ttl hash2] <= 10000000}
    assert {[$redis ttl hash2] > 0}
    assert_equal [$redis get key2] v
    assert {[$redis ttl key2] <= 10000000}
    assert {[$redis ttl key2] > 0}
}
set adds(3) {
    $redis set key3 v ex 10000000
    $redis set key4 v ex 10000000
    $redis del key4
    $redis set key5 1
}
set checks(3) {
    assert_equal [$redis get key3]  v
    assert {[$redis ttl key3] <= 10000000}
    assert {[$redis ttl key3] > 0}
    assert_equal [$redis get key4]  {}
    assert_equal [$redis get key5]  1
}
set adds(4) {
    $redis sadd key6 s1 
    $redis sadd key7 s1 s2
    $redis sadd key8 s1 s2
    $redis srem key8 s1 
    $redis sadd key9 s1 s2
    $redis del key9
}
set checks(4) {
    assert_equal [$redis SISMEMBER key6 s1] 1
    assert_equal [$redis SISMEMBER key7 s1] 1
    assert_equal [$redis SISMEMBER key7 s2] 1
    assert_equal [$redis SISMEMBER key8 s1] 0
    assert_equal [$redis SISMEMBER key8 s2] 1
    assert_equal [$redis SISMEMBER key9 s1] 0
}


####### tests

#######  A redis  B crdt  C crdt
#######  t1 A full-sync B
#######  t2 B full-sync C
proc full-sync {add check server_path dbfile} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        run [replace_client $add {$master}]  1
        run [replace_client $check {$master}] 1
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_stdout
            after 1000
            run [replace_client $check {$slave}]  1
            # puts [print_log_file $slave_stdout] 
            is_not_slave $master $slave
            start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
                set crdt_slave [srv 0 client]
                set crdt_slave_host [srv 0 host]
                set crdt_slave_port [srv 0 port]
                set crdt_slave_stdout [srv 0 stdout]
                $crdt_slave slaveof $slave_host $slave_port
                wait $slave 0 info $slave_stdout
                test "full-sync" {
                    run [replace_client $check {$crdt_slave}]  1
                    # puts [print_log_file $slave_stdout] 
                    assert  {
                        [ get_info_replication_attr_value  $slave info master_replid] 
                        ==
                        [ get_info_replication_attr_value $crdt_slave info master_replid]
                    }
                    
                } 
            }
        }
    }
}


#full sync
set len [array size adds]
# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-%s" $i] {
#         run_foreach full-sync $i $len
#     }
# }
test [format "foreach"] {
    run_foreach full-sync $len $len
}

#######  A redis  B crdt  C crdt
#######  t1 A add-sync B , B add-sync C
proc add-sync {add check server_path dbfile} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_stdout
            # puts [print_log_file $slave_stdout] 
            is_not_slave $master $slave

            start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
                set crdt_slave [srv 0 client]
                set crdt_slave_host [srv 0 host]
                set crdt_slave_port [srv 0 port]
                set crdt_slave_stdout [srv 0 stdout]
                $crdt_slave slaveof $slave_host $slave_port
                wait $slave 0 info $slave_stdout
                test "add-sync" {
                    run [replace_client $add {$master}]  1
                    after 1000
                    run [replace_client $check {$slave}]  1
                    run [replace_client $check {$crdt_slave}]  1
                    # puts [print_log_file $slave_stdout] 
                    check_slave $slave $crdt_slave
                } 
            }
        }
    }
}

#add sync
set len [array size adds]
# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-add-sync-%s" $i] {
#         run_foreach add-sync $i $len
#     }
# }
test [format "foreach-add-sync"] {
    run_foreach add-sync $len $len
}
#######  A redis  B crdt  C crdt
#######  t1 A full-sync B
#######  t2 B full-sync C
#######  t3 A add-sync B , B add-sync C
proc add_all {client} {
    $client set add-key value
    $client hset add-hash k1 v1 k2 v2
    $client set add-exp v ex 10000
}
proc check_all {client} {
    assert_equal [$client get add-key] value
    assert_equal [$client hget add-hash k1] v1
    assert_equal [$client hget add-hash k2] v2
    assert_equal [$client get add-exp] v
    assert {[$client ttl add-exp] <= 10000}
    assert {[$client ttl add-exp] > 0}
}
proc full-and-add-sync {add check server_path dbfile} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        add_all $master
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_stdout
            check_all $slave
            # puts [print_log_file $slave_stdout] 
            is_not_slave $master $slave

            start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
                set crdt_slave [srv 0 client]
                set crdt_slave_host [srv 0 host]
                set crdt_slave_port [srv 0 port]
                set crdt_slave_stdout [srv 0 stdout]
                $crdt_slave slaveof $slave_host $slave_port
                wait $slave 0 info $slave_stdout
                check_all $crdt_slave
                test "full-and-add-sync" {
                    run [replace_client $add {$master}]  1
                    after 1000
                    run [replace_client $check {$slave}]  1
                    run [replace_client $check {$crdt_slave}]  1
                    # puts [print_log_file $slave_stdout] 
                    check_slave $slave $crdt_slave
                } 
            }
        }
    }
}
#full and add sync
set len [array size adds]
# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-full-and-add-sync-%s" $i] {
#         run_foreach full-and-add-sync $i $len
#     }
# }
test [format "foreach-full-and-add-sync"] {
    run_foreach full-and-add-sync $len $len
}
#######  A redis  B crdt  C crdt
#######  A add-sync B 
#######  B  full-sync C
proc before-add-after-full {add check server_path dbfile} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            $slave slaveof $master_host $master_port
            wait $master 0 info $slave_stdout
            run [replace_client $add {$master}]  1
            # puts [print_log_file $slave_stdout] 
            is_not_slave $master $slave

            start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
                set crdt_slave [srv 0 client]
                set crdt_slave_host [srv 0 host]
                set crdt_slave_port [srv 0 port]
                set crdt_slave_stdout [srv 0 stdout]
                $crdt_slave slaveof $slave_host $slave_port
                wait $slave 0 info $slave_stdout
                
                test "master-slave" {
                    after 1000
                    run [replace_client $check {$slave}]  1
                    run [replace_client $check {$crdt_slave}]  1
                    # puts [print_log_file $slave_stdout] 
                    check_slave $slave $crdt_slave
                } 
            }
        }
    }
}
#before add after full
set len [array size adds]
# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-before-add-after-full-%s" $i] {
#         run_foreach before-add-after-full $i $len
#     }
# }
test [format "foreach-before-add-after-full"] {
    run_foreach before-add-after-full $len $len
}

######  A redis  B crdt  C crdt
######  t1 C slaveof B
######  t2 B slaveof A   
proc slaves-full-sync {add check server_path dbfile} {
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        $master config set repl-diskless-sync-delay 1
        
        start_server {tags {"slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            
            run [replace_client $add {$master}]  1
            # puts [print_log_file $slave_stdout] 
            is_not_slave $master $slave

            start_server {tags {"crdt-slave"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
                set crdt_slave [srv 0 client]
                set crdt_slave_host [srv 0 host]
                set crdt_slave_port [srv 0 port]
                set crdt_slave_stdout [srv 0 stdout]
                $crdt_slave slaveof $slave_host $slave_port
                wait $slave 0 info $slave_stdout
                $slave slaveof $master_host $master_port
                wait $master 0 info $slave_stdout
                test "master-slave" {
                    run [replace_client $check {$slave}]  1
                    wait $slave 0 info $slave_stdout
                    # print_log_file $slave_stdout 
                    run [replace_client $check {$crdt_slave}]  1
                    # print_log_file $slave_stdout 
                    check_slave $slave $crdt_slave 
                } 
            }
        }
    }
}
#slaves full sync
set len [array size adds]
# for {set i 1} {$i <= $len} {incr i} {
#     test [format "foreach-slaves full sync-%s" $i] {
#         run_foreach slaves-full-sync $i $len
#     }
# }
test [format "foreach-slaves full sync" ] {
    run_foreach slaves-full-sync $len $len
}