
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}
proc get_vector_clock { client } {
    set info [ $client {crdt.info} {replication} ]
    regexp {\r\novc:(.*?)\r\n} $info match clock 
    set _ $clock
}
proc get_kill_client_addr { clients_info } {
    set lines [split $clients_info "\r\n"]
    set len [llength $lines]
    for {set j 0} {$j < $len} {incr j} { 
        set line [lindex $lines $j] 
        if { [regexp {(.*?)(cmd=client)$} $line match] != 1} {
            if {[regexp {addr=(.*?) fd=(.*?)} $line match addr ]} {
                return $addr
            }  
        }   
    }
}
# Full synchronization process,
# updated crdtServer.vectorClock in advance,
# if synchronization fails,
# there will be omissions in the next synchronization data
# pull request: https://github.com/ctripcorp/xredis-crdt/pull/10
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config crdt.set  repl-timeout 10
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config crdt.set  repl-timeout 10
        [lindex $peers 1] config set repl-diskless-sync-delay 1

        test "reply" {
            
            set n 200000
            set scan_n 5000
            for {set j 0} {$j <= $n } {incr j} {
                [lindex $peers 0] set [format "key-%s" $j] $j
            }
            set keys [[lindex $peers 0] scan $scan_n]
            set time [clock milliseconds]
            for {set j 0} {$j <= $scan_n} {incr j} {
                # [lindex $peers 0] crdt.set [lindex $keys [expr 2000 -$j]] $j [lindex peer_gids 0] [expr $time] [format "2:%s" [expr 10000 -$j]] 10000
                [lindex $peers 0] set [lindex $keys [expr $n -$j]] $j
            }
            set keys2 [[lindex $peers 0] scan $scan_n]
            for {set j 0} {$j <= $scan_n} {incr j} { 
                if {[lindex $keys $j] != [lindex $keys2 $j]} {
                    puts $j
                    puts [lindex $keys $j]
                    puts [lindex $keys2 $j]
                    assert {1 == 2}
                }
            }
            set old_vector_clock [get_vector_clock [lindex $peers 1]]
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0]  [lindex $peer_ports 0]
            wait_for_condition 10000 5 {
                [log_file_matches [lindex $peer_stdouts 0] "*\[crdtRdbSaveRio\] start*"]
            } else {
                fail "full sync fail"
            }
            set killed 0
            
            for {set j 0} {$j <= 200} {incr j} { 
                assert {[log_file_matches [lindex $peer_stdouts 0] "*CRDT.MERGE_END*"] == 0 }
                set kill_addr [get_kill_client_addr [[lindex $peers 1] CLIENT LIST] ]
                if {$kill_addr != {}} {
                    [lindex $peers 1] client kill  $kill_addr
                    set killed 1
                    break
                }
                after 50
            }
            assert { $killed eq {1} }
            set dbsize [[lindex $peers 1] dbsize]
            assert { $dbsize <= $n}
            after 100
            assert { [ [lindex $peers 1] dbsize] == $dbsize}
            assert { [get_vector_clock [lindex $peers 1]] eq  "1:0;2:0" }
        }
    }
}