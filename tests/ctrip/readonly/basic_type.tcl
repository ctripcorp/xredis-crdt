proc replace_client { str client } {
    regsub -all {\$redis} $str $client str
    return $str
}
proc replace { str argv } {
    set len [llength $argv]
    for {set i 0} {$i < $len} {incr i} {
        set regstr [format {\$%s} $i]
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
    catch [uplevel $level $script ] result
    return $result
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

proc basic_test { type create check delete} {
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

            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 1
            [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 0] config set repl-diskless-sync-delay 1
            [lindex $peers 0] slaveof $master_host $master_port
            wait $master 0 info $master_stdout
            test [format "%s-readonly" $type] {
                set argv {key field value} 
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
                set argv {key field value} 
                run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $argv] 1
            }
            test [format "%s-del1" $type] {
                set argv {key field value} 
                run [replace [replace_client $delete {[lindex $peers 0]}] $argv] 1
                set result {key field {}}
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            }
            test [format "%s-del2" $type] {
                set argv {key field value} 
                run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $argv] 1
                [lindex $peers 0] del key
                set result {key field {}}
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            }
            
        }
        
    }
    
    
}

#$0 key 
#$1 field
#$2 value
basic_test "kv" {
    $redis set $0 $2
} {
    assert {[$redis get $0 ] eq {$2}}
} {
    $redis del $0
} 


basic_test "hash" {
    $redis hset $0 $1 $2
} {
    assert {[$redis hget $0 $1 ] eq {$2}}
} {
    $redis hdel $0 $1
}