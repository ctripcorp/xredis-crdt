
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

start_server {tags {"crdt-del"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {

    set server_log [srv 0 stdout]

    test {conflict is record} {
        r CRDT.SET key-1 val2 3 [expr [clock milliseconds] - 10]  "1:10;2:99;3:100" 
        r CRDT.SET key-1 val1 2 [clock milliseconds]  "1:10;2:100;3:99" 

        set redis_server [srv 0 client]
        set conflict [crdt_stats $redis_server crdt_conflict]
        assert {$conflict >= 1}

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
        set conflict [crdt_stats $redis_server crdt_conflict]
        assert {$conflict >= 2}

        wait_for_condition 50 1000 {
            [log_file_matches $server_log "*drop*"]
        } else {
            fail "server is not able to detect conflict"
        }

    }

}
