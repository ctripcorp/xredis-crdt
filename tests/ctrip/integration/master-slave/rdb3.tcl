
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
set server_path [tmpdir "server.rdb3"]

# Copy RDB with different encodings in server path
# exec cp tests/assets/encodings.rdb $server_path
cp_crdt_so $server_path
exec cp tests/assets/crdt_1.0.0.rdb $server_path
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
proc load {check server_path dbfile} {
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
        # log_file_matches [lindex $peer_stdouts 0]
        test  "check" {
            run [replace_client $check {[lindex $peers 0]}]  2
        };

    }
}
array set checks ""
set checks(0) {
    assert_equal [$redis
    get
    key] value
}
set checks(1) {
    assert_equal [$redis
    hget
    h
    k] v
}
set checks(2) {
    assert_equal [$redis tombstonesize] 1
}
set len [array size checks]
set check $checks(0)
for {set x 1} {$x<$len} {incr x} {
    append check $checks($x)
}
#old_version rdb
load $check $server_path "crdt_1.0.0.rdb"
