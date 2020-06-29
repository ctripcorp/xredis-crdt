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
proc wait { client index type}  {
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
        error "assertion: Master-Slave not correctly synchronized"
    }
}

proc basic_test { type create check delete} {
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
        start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 2
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            [lindex $peers 1] peerof  [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            wait [lindex $peers 0] 0 crdt.info
            test [format "%s-peerof-create" $type] {
                run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
                after 500
                run [replace [replace_client $check {[lindex $peers 1]}] $argv] 1
            }
            test [format "%s-peerof-del" $type] {
                run [replace [replace_client $delete {[lindex $peers 0]}] $argv] 1
                after 500
                set result {key, field, {}}
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1
            }
        }
    }
    

    


    start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_gids  {}
        set slaves {}
        set slave_hosts {}
        set slave_ports {}
        set slave_logs {}

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids  1
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        start_server {overrides {crdt-gid 1} module {crdt.so}} {
            lappend slaves [srv 0 client]
            lappend slave_hosts [srv 0 host]
            lappend slave_ports [srv 0 port]
            lappend slave_logs  1
            [lindex $slaves 0] config crdt.set repl-diskless-sync-delay 1
            [lindex $slaves 0] config set repl-diskless-sync-delay 1
            start_server {overrides {crdt-gid 2} module {crdt.so}} {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_gids  2
                [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
                [lindex $peers 1] config set repl-diskless-sync-delay 1
                test "when after slave and peerof" {
                    [lindex $slaves 0] slaveof [lindex $peer_hosts 0] [lindex $peer_ports 0]
                    wait [lindex $peers 0] 0 info
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $slaves 0] info master_repl_offset]
                    }
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] crdt.info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $slaves 0] crdt.info master_repl_offset]
                    }
                    [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                    wait [lindex $peers 0] 0 crdt.info
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] crdt.info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $peers 1] crdt.info peer0_repl_offset]
                    }
                }
                test [format "after %s-set, check repl_offset" $type] {
                    set old [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    set argv {key field value} 
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
                    assert {
                        $old 
                        !=
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    }
                    after 1000
                    run [replace [replace_client $check {[lindex $slaves 0]}] $argv] 1
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $slaves 0] info master_repl_offset]
                    }
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] crdt.info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $slaves 0] crdt.info master_repl_offset]
                    }
                    run [replace [replace_client $check {[lindex $peers 1]}] $argv] 1
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] crdt.info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $peers 1] crdt.info peer0_repl_offset]
                    }
                }
                test [format "after %s-delete, check repl_offset" $type] {
                    set old [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    set argv {key field value} 
                    run [replace [replace_client $delete {[lindex $peers 0]}] $argv] 1
                    assert {
                        $old 
                        !=
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    }
                    set result {key field {}} 
                    after 1000
                    run [replace [replace_client $check {[lindex $slaves 0]}] $result] 1
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $slaves 0] info master_repl_offset]
                    }
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] crdt.info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $slaves 0] crdt.info master_repl_offset]
                    }
                    run [replace [replace_client $check {[lindex $peers 1]}] $result] 1
                    assert {
                        [get_info_replication_attr_value [lindex $peers 0] crdt.info master_repl_offset]
                        eq
                        [get_info_replication_attr_value [lindex $peers 1] crdt.info peer0_repl_offset]
                    }
                }
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

basic_test "mset" {
    $redis mset $0 $2
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