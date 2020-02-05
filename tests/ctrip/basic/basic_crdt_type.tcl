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
            set argv {key field value 1 100000 "1:1" }
            run [replace [replace_client $create {[lindex $peers 0]}] $argv] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $argv] 1
        }
        test [format "%s-del" $type] {
            set argv {key field value 1 100000 "1:1" }
            run [replace [replace_client $delete {[lindex $peers 0]}] $argv] 1
            set result {key field {} 1 100000 "1:1" }
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
            [lindex $peers 0] peerof  [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            wait [lindex $peers 0] 0 crdt.info
            wait [lindex $peers 1] 0 crdt.info
            
            test [format "%s-peerof-create" $type] {
                set argv2 {key field value 1 100000 "1:2"}
                run [replace [replace_client $create {[lindex $peers 0]}] $argv2] 1
                after 2000
                run [replace [replace_client $check {[lindex $peers 1]}] $argv2] 1
            }
            test [format "%s-peerof-del" $type] {
                set argv2 {key field value 1 100000 "1:2"}
                run [replace [replace_client $delete {[lindex $peers 0]}] $argv2] 1
                after 100
                set result {key field {} 1 100000 "1:2" }
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1
            }
            test [format "%s-time-order" $type] {
                set argv1 {key field value 1 100000 {"1:4;2:1"}}
                run [replace [replace_client $create {[lindex $peers 1]}] $argv1] 1
                set argv2 {key field old 2 100000 {"1:3;2:1"} }
                run [replace [replace_client $create {[lindex $peers 1]}] $argv2] 1
                run [replace [replace_client $check {[lindex $peers 1]}] $argv1] 1
            }
            
            test [format "%s-tombstone-vc" $type] {
                set argv1 {tombstone field value 2 100000 {"1:10;2:10"} }
                run [replace [replace_client $create {[lindex $peers 1]}] $argv1] 1
                run [replace [replace_client $check {[lindex $peers 1]}] $argv1] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 0]}] $argv1] 1
                set del {tombstone field value 2 100000 {"1:10;2:11"} }
                set result {tombstone field {} 2 100000 {"1:10;2:11"} }
                run [replace [replace_client $delete {[lindex $peers 1]}] $del] 1
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

                run [replace [replace_client $create {[lindex $peers 1]}] $argv1] 1
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            }
            test [format "%s-tombstone-time" $type] {
                set result {tombstone field {} 2 100000 {"1:10;2:11"} }
                set argv2 {tombstone field value2 1 99999 {"1:11;2:10"}}
                run [replace [replace_client $create {[lindex $peers 1]}] $argv2] 1
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1


                set argv3 {tombstone field value3 1 100001 {"1:11;2:10"}}
                run [replace [replace_client $create {[lindex $peers 0]}] $argv3] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $argv3] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 1]}] $argv3] 1
            }
            test [format "%s-tombstone-gid1" $type] {
                set del2 {tombstone field value3 1 100001 {"1:12;2:11"}}
                set result {tombstone field {} 1 100000 {"1:12;2:11"} }
                run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1

                set argv4 {tombstone field value4 2 100001 {"1:11;2:12"}}
                run [replace [replace_client $create {[lindex $peers 1]}] $argv4] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1

                
            }
            test [format "%s-tombstone-gid2" $type] {            
                set argv5 {tombstone field value5 1 100001 {"1:13;2:13"}}
                set result {tombstone field {} 1 100000 {"1:13;2:14"} }
                run [replace [replace_client $create {[lindex $peers 0]}] $argv5] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $argv5] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 1]}] $argv5] 1

                set del3 {tombstone field value5 2 100001 {"1:13;2:14"}}
                run [replace [replace_client $delete {[lindex $peers 1]}] $del3] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 1]}] $result] 1

                set argv6 {tombstone field value6 1 100001 {"1:14;2:13"}}
                run [replace [replace_client $create {[lindex $peers 0]}] $argv6] 1
                run [replace [replace_client $check {[lindex $peers 0]}] $argv6] 1
                after 100
                run [replace [replace_client $check {[lindex $peers 1]}] $argv6] 1
            }
        }
    }

    start_server {tags {[format "crdt-double-delete-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_gids {}

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 3
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1

        test [format "%s-double-delete1" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:10;2:10;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:10;2:11;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:11;2:11;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:11;2:12;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:11;2:12;3:1"}}
            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }

        test [format "%s-double-delete2" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:20;2:20;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:20;2:21;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:21;2:21;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:21;2:22;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:21;2:22;3:1"}}

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        test [format "%s-double-delete3" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:30;2:30;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:30;2:31;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:31;2:31;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:31;2:32;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:31;2:32;3:1"}}

            

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        test [format "%s-double-delete4" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:40;2:40;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:40;2:41;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:41;2:41;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:41;2:42;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:41;2:42;3:1"}}

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

        }
        test [format "%s-double-delete5" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:50;2:50;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:50;2:51;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:51;2:51;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:51;2:52;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:51;2:52;3:1"}}

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
    
        }
        test [format "%s-double-delete6" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:60;2:60;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:60;2:61;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:61;2:61;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:61;2:62;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:61;2:62;3:1"}}

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
    
        }
        

    }
    

    start_server {tags {[format "crdt-double-diffent-delete-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_gids {}

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 3
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        
        
        test [format "%s-double-delete1" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:10;2:10;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:10;2:11;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:11;2:11;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:11;2:12;3:1"}}

            set result {tombstone2 field {} 2 200001 {"1:11;2:12;3:1"}}
            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }

        test [format "%s-double-delete2" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:20;2:20;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:20;2:21;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:21;2:21;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:21;2:22;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:21;2:22;3:1"}}

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        test [format "%s-double-delete3" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:30;2:30;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:30;2:31;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:31;2:31;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:31;2:32;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:31;2:32;3:1"}}

            

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add1] 1

            # run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1 
            # run [replace [replace_client $check {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        test [format "%s-double-delete4" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:40;2:40;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:40;2:41;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:41;2:41;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:41;2:42;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:41;2:42;3:1"}}

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

        }
        test [format "%s-double-delete5" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:50;2:50;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:50;2:51;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:51;2:51;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:51;2:52;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:51;2:52;3:1"}}

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
    
        }
        test [format "%s-double-delete6" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:60;2:60;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:60;2:61;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:61;2:61;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:61;2:62;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:61;2:62;3:1"}}

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
    
        }

        
        

    }
    start_server {tags {[format "crdt-double-diffent-delete-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_gids {}

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 3
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        
        
        test [format "%s-double-delete1" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:10;2:10;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:10;2:11;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:11;2:11;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:11;2:12;3:1"}}

            set result {tombstone2 field {} 2 200001 {"1:11;2:12;3:1"}}
            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
        }

        test [format "%s-double-delete2" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:20;2:20;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:20;2:21;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:21;2:21;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:21;2:22;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:21;2:22;3:1"}}

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
        }
        test [format "%s-double-delete3" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:30;2:30;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:30;2:31;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:31;2:31;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:31;2:32;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:31;2:32;3:1"}}

            

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1

            # run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1 
            # run [replace [replace_client $checkHash {[lindex $peers 0]}] $add2] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
        }
        test [format "%s-double-delete4" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:40;2:40;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:40;2:41;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:41;2:41;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:41;2:42;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:41;2:42;3:1"}}

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

        }
        test [format "%s-double-delete5" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:50;2:50;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:50;2:51;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:51;2:51;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:51;2:52;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:51;2:52;3:1"}}

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
    
        }
        test [format "%s-double-delete6" $type] {
            set add1 {tombstone2 field value 1 200001 {"1:60;2:60;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:60;2:61;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:61;2:61;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:61;2:62;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:61;2:62;3:1"}}

            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
    
        }
    }
    start_server {tags {[format "crdt-create-%s" $type]} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set peers {}
        set peer_hosts {}
        set peer_ports {}
        set peer_gids {}

        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids 3
        [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 0] config set repl-diskless-sync-delay 1
        test "tombstone -add" {
            set add1 {tombstone2 field value 1 200001 {"1:10;2:10;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:10;2:11;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:10;2:10;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:10;2:11;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:11;2:12;3:1"}}

            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
        }
        test "tombstone -add2" {
            set add1 {tombstone2 field value 1 200001 {"1:20;2:20;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:20;2:21;3:1"}}
            set add2 {tombstone2 field value2 1 200001 {"1:20;2:20;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:20;2:21;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:21;2:22;3:1"}}

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        test "tombstone -add3" {
            set add1 {tombstone2 field value 1 200001 {"1:30;2:30;3:1"}}
            set del1 {tombstone2 field value 2 200001 {"1:30;2:31;3:1"}}
            set add2 {tombstone2 field value2 1 200000 {"1:31;2:30;3:1"}}
            set add3 {tombstone2 field value2 1 200001 {"1:31;2:30;3:1"}}
            set del2 {tombstone2 field value2 1 200001 {"1:32;2:30;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:31;2:32;3:1"}}

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $create {[lindex $peers 0]}] $add3] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $add3] 1
            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1 
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        
        test "tombstone-del" {
            set add1 {tombstone2 field value 1 200001 {"1:41;2:40;3:1"}}
            set del1 {tombstone2 field value 1 200001 {"1:42;2:40;3:1"}}
            set add2 {tombstone2 field value2 2 200001 {"1:40;2:41;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:40;2:42;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:41;2:42;3:1"}}

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $delete {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $create {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
        test "tombstone-del" {
            set add1 {tombstone2 field value 1 200001 {"1:51;2:50;3:1"}}
            set del1 {tombstone2 field value 1 200001 {"1:52;2:50;3:1"}}
            set add2 {tombstone2 field value2 2 200001 {"1:50;2:51;3:1"}}
            set del2 {tombstone2 field value2 2 200001 {"1:50;2:52;3:1"}}
            set result {tombstone2 field {} 2 200001 {"1:51;2:52;3:1"}}

            run [replace [replace_client $createHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $add2] 1
            run [replace [replace_client $deleteHash {[lindex $peers 0]}] $del2] 1
            run [replace [replace_client $checkHash {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $delete {[lindex $peers 0]}] $del1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
            run [replace [replace_client $create {[lindex $peers 0]}] $add1] 1
            run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
        }
    }
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
        start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            lappend peers [srv 0 client]
            lappend peer_hosts [srv 0 host]
            lappend peer_ports [srv 0 port]
            lappend peer_gids 2
            [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
            [lindex $peers 1] config set repl-diskless-sync-delay 1
            start_server {tags {[format "crdt-basic-%s" $type]} overrides {crdt-gid 3} config {crdt.conf} module {crdt.so} } {
                lappend peers [srv 0 client]
                lappend peer_hosts [srv 0 host]
                lappend peer_ports [srv 0 port]
                lappend peer_gids 3
                [lindex $peers 2] config crdt.set repl-diskless-sync-delay 1
                [lindex $peers 2] config set repl-diskless-sync-delay 1
                test "test" {
                    set argv1 {key field old 1 100000 {"1:3;2:1"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv1] 1
                    set argv2 {key field value 2 100000 {"1:4;2:2"}}
                    run [replace [replace_client $create {[lindex $peers 1]}] $argv2] 1

                    [lindex $peers 2] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
                    [lindex $peers 2] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
                    
                    wait [lindex $peers 1] 0 crdt.info
                    wait [lindex $peers 0] 0 crdt.info
                    run [replace [replace_client $check {[lindex $peers 2]}] $argv2] 1
                }
                test [format "%s-before-del" $type] {
                    set del {key field value 2 100000 {"1:13;2:12"} }
                    run [replace [replace_client $delete {[lindex $peers 0]}] $del] 1
                    set add {key field value 1 100000 {"1:13;2:11"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $add] 1
                    set result {key field {} 1 100000 {"1:13;2:12"} }
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                }
                test [format "%s-expire" $type] {
                    set add {key field value 1 100000 {"1:20;2:20"} }
                    set result {key field {} 1 100000 {"1:20;2:20"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $add] 1
                    run [replace [replace_client $check {[lindex $peers 0]}] $add] 1
                    [lindex $peers 0] expire key 1
                    after 1000
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1
                    set add {key field value 1 100000 {"1:20;2:20"} }
                    run [replace [replace_client $check {[lindex $peers 0]}] $result] 1

                }
            
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
                    set argv {key field value 1 100000 {"1:3;2:1"} }
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
                    set argv {key field old 1 100000 {"1:3;2:1"} }
                    run [replace [replace_client $delete {[lindex $peers 0]}] $argv] 1
                    assert {
                        $old 
                        !=
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    }
                    set result {key field {} 1 100000 {"1:3;2:1"} }
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
                test [format "after %s-conflict , check repl_offset" $type] {
                    set old [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    set argv1 {key field v1 1 100000 {"1:100;2:99"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv1] 1
                    set argv2 {key field v2 2 100000 {"1:99;2:100"} }
                    run [replace [replace_client $create {[lindex $peers 0]}] $argv2] 1
                    
                    assert {
                        $old 
                        !=
                        [get_info_replication_attr_value [lindex $peers 0] info master_repl_offset]
                    }
                    set result {key field v1 1 100000 {"1:100;2:100"} }
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
                    run [replace [replace_client $create {[lindex $peers 1]}] $argv2] 1
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

# key field value gid timestamp vc
#  0   1     2    3    4        5
basic_test "kv" {
    catch [$redis crdt.set $0 $2 $3 $4 $5 10000] error
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