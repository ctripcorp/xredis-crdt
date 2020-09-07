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
proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc basic_test { type create check delete} {
    start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
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
        
        test [format "%s-del-tombstone1" $type] {
            set add1 {key field value 1 100000 {"1:1;2:1"} }
            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1
            set delete1 {key field {} 1 100000 {"1:2;2:1"} }
            run [replace [replace_client $delete {[lindex $peers 0]}] $delete1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $delete1] 1
            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $delete1] 1
            set add2 {key field value2 2 100000 {"1:1;2:2"}}
            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $delete1] 1
        }
        
        start_server { overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        

            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_stdouts [srv 0 stdout]
            lappend peer_gids 2
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            test "clean-peerof" {
                [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                wait [lindex $peers 0] 0 crdt.info 
                wait [lindex $peers 1] 0 crdt.info 
            }
            
            test [format "%s-del-tombstone2" $type] {
                set add1 {key field value 1 100000 {"1:11;2:11"} }
                puts [[lindex $peers 0] crdt.datainfo key ]
                run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
                
                print_log_file [lindex $peer_stdouts 0]
                run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1
                
                set delete1 {key field {} 1 100000 {"1:12;2:11"} }
                
                [lindex $peers 0] del key
                after 1000
                run [replace [replace_client $check {[lindex $peers 1]}] $delete1] 1
                run [replace [replace_client $create {[lindex $peers 1]}] $add1] 1
                
                run [replace [replace_client $check {[lindex $peers 1]}] $delete1] 1
                run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
                
                run [replace [replace_client $check {[lindex $peers 0]}] $delete1] 1
                set add2 {key field value2 2 100000 {"1:11;2:12"}}
                run [replace [replace_client $create {[lindex $peers 1]}] $add2] 1
                # print_log_file [lindex $peer_stdouts 0]
                run [replace [replace_client $check {[lindex $peers 1]}] $delete1] 1
                run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
                print_log_file [lindex $peer_stdouts 0]
                run [replace [replace_client $check {[lindex $peers 0]}] $delete1] 1
                
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


# # key field value gid timestamp vc
# #  0   1     2    3    4        5
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
    $redis crdt.del_hash $0 $3 $4 $5 
}