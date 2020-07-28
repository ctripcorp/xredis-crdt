
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}

proc log_content {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}
proc wait { client index type log }  {
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
        log_content $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}

start_server {tags {"crdt-del"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    set peers {}
    set hosts {}
    set ports {}
    set gids {}
    set stdouts {}
    lappend peers [srv 0 client]
    lappend hosts [srv 0 host]
    lappend ports [srv 0 port]
    lappend gids 1
    lappend stdouts [srv 0 stdout]
    set server_log [srv 0 stdout]
    set redis_server [srv 0 client]
    test {conflict is record} {
        r CRDT.SET key-1 val2 3 [expr [clock milliseconds] - 10]  "1:10;2:99;3:100" 
        r CRDT.SET key-1 val1 2 [clock milliseconds]  "1:10;2:100;3:99" 

        set conflict [crdt_stats $redis_server crdt_non_type_conflict]
        assert {$conflict >= 1}
        assert {[crdt_stats $redis_server crdt_modify_conflict] == 1}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*CONFLICT*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    
    test {conflict dropped is record} {
        r CRDT.SET key-2 val2 3 [clock milliseconds] "1:10;2:99;3:100"  
        r CRDT.SET key-2 val1 2 [expr [clock milliseconds] - 10]   "1:10;2:100;3:99"  

        set redis_server [srv 0 client]
        assert {[crdt_stats $redis_server crdt_non_type_conflict] == 2}
        assert {[crdt_stats $redis_server crdt_modify_conflict] == 2}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }
    test {different type modify} {
        $redis_server CRDT.SET key-3 val2 3 [clock milliseconds] "1:10;2:99;3:101"  
        catch {$redis_server CRDT.HSET key-3 2 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k v}
        
        set conflict [crdt_stats $redis_server crdt_type_conflict]
        assert {[crdt_stats $redis_server crdt_type_conflict] == 1}
        assert {[crdt_stats $redis_server crdt_modify_conflict] == 3}

        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    
    test {conflict is record} {
        $redis_server CRDT.HSET key-4 2 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k v 
        catch {r CRDT.SET key-4 val1 2 [clock milliseconds]  "1:10;2:100;3:99" }

        set conflict [crdt_stats $redis_server crdt_type_conflict]
        assert {[crdt_stats $redis_server crdt_type_conflict] == 2}
        assert {[crdt_stats $redis_server crdt_modify_conflict] == 4}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*CONFLICT*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {different type modify} {
        $redis_server CRDT.HSET key-5 2  [clock milliseconds]  "1:10;2:99;3:101" 2 k val1
        $redis_server CRDT.HSET key-5 3 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k val2
    
        assert {[crdt_stats $redis_server crdt_non_type_conflict] == 3}
        assert {[crdt_stats $redis_server crdt_modify_conflict] == 5}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    test {different type modify} {
        $redis_server CRDT.HSET key-6 3 [expr [clock milliseconds]-10]  "1:10;2:101;3:99" 2 k val2
        $redis_server CRDT.HSET key-6 2  [clock milliseconds]  "1:10;2:99;3:101" 2 k val1
        
    
        assert {[crdt_stats $redis_server crdt_non_type_conflict] == 4}
        assert {[crdt_stats $redis_server crdt_modify_conflict] == 6}
        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }
    }
    
    start_server {tags {"crdt-del"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend hosts [srv 0 host]
        lappend ports [srv 0 port]
        lappend stdouts [srv 0 stdout]
        lappend gids 2
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        [lindex $peers 1] CRDT.SET key-1 v25 2 [clock milliseconds]  "1:1;2:201;3:99"
        [lindex $peers 1] CRDT.HSET key-3 2 [expr [clock milliseconds]-10]  "1:2;2:202;3:99" 2 k v
        [lindex $peers 0] peerof [lindex $gids 1] [lindex $hosts 1] [lindex $ports 1]
        wait [lindex $peers 1] 0 crdt.info [lindex $stdouts 1]
        assert_equal [crdt_stats [lindex $peers 0] crdt_type_conflict] 3
        assert_equal [crdt_stats [lindex $peers 0] crdt_non_type_conflict] 5
        assert_equal [crdt_stats [lindex $peers 0] crdt_modify_conflict] 6
        assert_equal [crdt_stats [lindex $peers 0] crdt_merge_conflict] 2

        set before1 [crdt_stats [lindex $peers 1] crdt_non_type_conflict]
        set before0 [crdt_stats [lindex $peers 0] crdt_non_type_conflict]
        set num 50
        for {set j 0} {$j < $num} {incr j} {
            [lindex $peers 1] set $j $j
            [lindex $peers 1] expire $j 5
        } 
        after 6000
        assert_equal [crdt_stats [lindex $peers 0] crdt_non_type_conflict] $before0
        assert_equal [crdt_stats [lindex $peers 1] crdt_non_type_conflict] $before1
    }
}
