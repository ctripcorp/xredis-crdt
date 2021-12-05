proc start_bg_complex_string_data {host port db ops} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/bg_string_data.tcl $host $port $db $ops &
}

proc stop_bg_complex_data {handle} {
    catch {exec /bin/kill -9 $handle}
}

proc print_log_content {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {

        set peer1 [srv -1 client]
        set peer1_host [srv -1 host]
        set peer1_port [srv -1 port]
        set peer1_stdout [srv 0 stdout]
        set peer1_gid 1
        set peer2 [srv 0 client]
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_stdout [srv 0 stdout]
        set peer2_gid 2

        if {!$::swap} {
            set load_handle0 [start_bg_complex_string_data $peer1_host $peer1_port 9 100000]
            set load_handle1 [start_bg_complex_string_data $peer1_host $peer1_port 11 100000]
            set load_handle2 [start_bg_complex_string_data $peer2_host $peer2_port 12 100000]
        } else {
            set load_handle0 [start_bg_complex_string_data $peer1_host $peer1_port 0 100000]
            set load_handle1 [start_bg_complex_string_data $peer1_host $peer1_port 0 100000]
            set load_handle2 [start_bg_complex_string_data $peer2_host $peer2_port 0 100000]
        } 

        $peer1 config crdt.set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-diskless-sync-delay 1

        $peer2 peerof $peer1_gid $peer1_host $peer1_port
        $peer1 peerof $peer2_gid $peer2_host $peer2_port

        test {Test replication with parallel clients writing in differnet DBs} {
            after 2000
            stop_bg_complex_data $load_handle0
            stop_bg_complex_data $load_handle1
            stop_bg_complex_data $load_handle2
            set retry 10
            print_log_content $peer2_stdout
            while {$retry && ([$peer1 debug digest] ne [$peer2 debug digest])}\
            {
                after 1000
                incr retry -1
            }
            assert {[$peer1 dbsize] > 0}
            assert {[$peer2 dbsize] > 0}

            if {[$peer1 debug digest] ne [$peer2 debug digest]} {
                set csv1 [csvdump r]
                set csv2 [csvdump {r -1}]
                set fd [open /tmp/repldump1.txt w]
                puts -nonewline $fd $csv1
                close $fd
                set fd [open /tmp/repldump2.txt w]
                puts -nonewline $fd $csv2
                close $fd
                puts "Master - Slave inconsistency"
                puts "Run diff -u against /tmp/repldump*.txt for more info"
            }
            assert_equal [r debug digest] [r -1 debug digest]
        }
    }
}
