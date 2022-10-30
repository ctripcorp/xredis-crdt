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
proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}
proc run {script level} {
    catch [uplevel $level $script ] result opts
}
proc log_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait { client index type log}  {
    set retry 100
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

proc basic_test { type create check delete} {
    set createHash {
        $redis crdt.hset $0 $3 $4 $5 2 $1 $2
    }
    set checkHash {
        set r [$redis crdt.hget $0 $1 ]
        if { {$2} == {} } {
            assert {$r == {}}
        } else {
            assert { [lindex $r 0] == {$2} }
            assert { [lindex $r 1] == {$3} }
            assert { [lindex $r 2] == {$4} }
            assert { [lindex $r 3] == [format "%s" $5] }
        }
        unset r
    } 
    set deleteHash {
        $redis crdt.rem_hash $0 $3 $4 $5 $1
    }
    start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_gid 1
        $master config crdt.set repl-diskless-sync-delay 1
        $master config set repl-diskless-sync-delay 1
        start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set peers {}
            set peer_hosts {}
            set peer_ports {}
            set peer_gids {}
            set peer_stdouts {}

            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 1
            lappend peer_stdouts [srv 0 stdout]
            [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 0] config set repl-diskless-sync-delay 1
            [lindex $peers 0] slaveof $master_host $master_port
             wait $master 0 info $master_stdout
             test [format "%s-readonly" $type] {
                set argv {key field value 1 100000 "1:1" }
                if { [catch {
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
                } e]} {
                    assert_equal $e "READONLY You can't write against a read only slave."
                } else {
                    fail "code error"
                }
                [lindex $peers 0] CONFIG SET slave-read-only no 
            }
            test [format "%s-create" $type] {
                set argv {key field value 1 100000 "1:1" }
                run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $argv] 1
            }
            
            test [format "%s-del2" $type] {
                set argv1 {key-del field value 1 100000 "1:2"}
                run [replace [replace_client $create {[lindex $peers 0]}] $argv1] 1
                set argv2 {key-del field1 value 1 100000 "1:3"}
                run [replace [replace_client $delete {[lindex $peers 0]}] $argv2] 1
                set result {key-del field1 {} 1 100000 "1:3" }
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            }

            start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_gids 2
                lappend peer_stdouts [srv 0 stdout]
                [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
                [lindex $peers 1] config set repl-diskless-sync-delay 1
                [lindex $peers 1] peerof  [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                # [lindex $peers 0] peerof  [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                wait [lindex $peers 0] 0 crdt.info [lindex $peer_stdouts 1]
                # wait [lindex $peers 1] 0 crdt.info [lindex $peer_stdouts 0]
                
                test [format "%s-peerof-create" $type] {
                    set argv2 {key field value 1 100000 "1:2"}
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv2] 1
                    after 2000
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv2] 1
                }
                test [format "%s-peerof-del" $type] {
                    set argv2 {key field value 1 100000 "1:3"}
                    run [replace [replace_client $delete {[lindex $peers 0]}] $argv2] 1
                    after 100
                    set result {key field {} 1 100000 "1:3" }
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                }
                test [format "%s-time-order" $type] {
                    set argv1 {key field value 1 100000 {"1:4;2:1"}}
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv1] 1
                    set argv2 {key field old 2 100000 {"1:3;2:1"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv2] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv1] 1
                }
                
                test [format "%s-tombstone-vc" $type] {
                    set argv1 {tombstone field value 2 100000 {"1:10;2:10"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv1] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv1] 1
                    after 100
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv1] 1
                    set del {tombstone field value 2 100000 {"1:10;2:11"} }
                    set result {tombstone field {} 2 100000 {"1:10;2:11"} }
                    run [replace [replace_client $delete {[lindex $peers 0]}] $del] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                    after 100
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

                    run [replace [replace_client $create {[lindex $peers 0]}] $argv1] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

                }
                test [format "%s-tombstone-time" $type] {
                    set result {tombstone field {} 2 100000 {"1:10;2:11"} }
                    set argv2 {tombstone field value2 1 99999 {"1:11;2:10"}}
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv2] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                    # puts [[lindex $peers 0] crdt.datainfo tombstone]
                    set argv3 {tombstone field value3 1 100001 {"1:12;2:11"}}
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv3] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv3] 1
                }
                test [format "%s-tombstone-gid1" $type] {
                    set del2 {tombstone field value3 1 100001 {"1:13;2:11"}}
                    set result {tombstone field {} 1 100000 {"1:13;2:11"} }
                    run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                    

                    set argv4 {tombstone field value4 2 100001 {"1:11;2:13"}}
                    run [replace [replace_client $create {[lindex $peers 1]}] $argv4] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                    


                }
                test [format "%s-tombstone-gid2" $type] {            
                    set argv5 {tombstone field value5 1 100001 {"1:14;2:13"}}
                    set result {tombstone field {} 1 100000 {"1:14;2:14"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv5] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv5] 1
                    

                    set del3 {tombstone field value5 2 100001 {"1:14;2:14"}}
                    run [replace [replace_client $delete {[lindex $peers 0]}] $del3] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                    

                    set argv6 {tombstone field value6 1 100001 {"1:15;2:14"}}
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv6] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $argv6] 1
                    
                }
            }


        }
    }
}

# key field value gid timestamp vc
#  0   1     2    3    4        5
basic_test "kv" {
    catch [$redis crdt.set $0 $2 $3 $4 $5] error
} {
    set r [ $redis crdt.get $0 ]
    if { {$2} == {} } {
        assert {$r == {}}
    } else {
        assert { [lindex $r 0] == {$2} }
        assert { [lindex $r 1] == {$3} }
        assert { [lindex $r 2] == {$4} }
        assert { [lindex $r 3] == [format "%s" $5] }
    }
    unset r
} {
    $redis crdt.del_reg $0 $3 $4 $5
}
# key field value gid timestamp vc
#  0   1     2    3    4        5
#CRDT.MSET <gid> <time> {k v vc} ...

basic_test "mset" {
    catch [$redis crdt.mset $3 $4 $0 $2 $5] error
} {
    set r [ $redis crdt.get $0 ]
    if { {$2} == {} } {
        assert {$r == {}}
    } else {
        assert { [lindex $r 0] == {$2} }
        assert { [lindex $r 1] == {$3} }
        assert { [lindex $r 2] == {$4} }
        assert { [lindex $r 3] == [format "%s" $5] }
    }
    unset r
} {
    $redis crdt.del_reg $0 $3 $4 $5
}
# key field value gid timestamp vc
#  0   1     2    3    4        5
basic_test "hash" {
    $redis crdt.hset $0 $3 $4 $5 2 $1 $2
} {
    set r [$redis crdt.hget $0 $1 ]
    if { {$2} == {} } {
        assert {$r == {}}
    } else {
        assert { [lindex $r 0] == {$2} }
        assert { [lindex $r 1] == {$3} }
        assert { [lindex $r 2] == {$4} }
        assert { [lindex $r 3] == [format "%s" $5] }
    }
    unset r
} {
    $redis crdt.rem_hash $0 $3 $4 $5 $1
}