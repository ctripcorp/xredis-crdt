proc spawn_proxy {config_file stdout stderr} {
    set pid [exec java -jar tests/assets/xpipe-proxy/xpipe-proxy.jar $config_file >> $stdout 2>> $stderr &] 
    # send_data_packet $::test_server_fd server-spawned $pid
    return $pid
}

proc wait_proxy_started {pid stdout} {
    while 1 {
        if {[regexp -- " PID: $pid" [exec cat $stdout]]} {
            break
        }
    }
}

proc stop_proxy {pid} {
    catch {exec kill $pid}
    send_data_packet $::test_server_fd server-killed $pid
}

proc start_proxy {options {code undefined}} {
    # setup defaults
    set baseconfig "proxy_def.properties"
    set overrides {}
    set tags {}
    foreach {option value} $options {
        switch $option {
            "config" {
                set baseconfig $value 
            }
            "overrides" {
                set overrides $value
            }
            "tags" {
                set tags $value
                set ::tags [concat $::tags $value] 
            }
            default {
                error "Unknown option $option"
            }
        }
    }
    set data [split [exec cat "tests/assets/xpipe-proxy/$baseconfig"] "\n"]
    set config {}
    foreach line $data {
        if {[string length $line] > 0 && [string index $line 0] ne "#"} {
            set elements [split $line "="]
            set directive [lrange $elements 0 0]
            set arguments [lrange $elements 1 end]
            dict set config $directive $arguments
        }
    }
    set config_dir [tmpdir proxy]
    dict set config dir $config_dir 
    set config_file "$config_dir/proxy.properties"
    set fp [open $config_file w+]
    # set ::proxy_tcp [find_available_port [expr {$::proxy_tcp+1}]]
    # set ::proxy_tls [find_available_port [expr {$::proxy_tls+1}]]
    set ::proxy_tcp [find_available_server_port $::base_proxy_port]
    set ::proxy_tls [expr {$::proxy_tcp+10000}]
    set tcp_port $::proxy_tcp 
    set tls_port $::proxy_tls 
    dict set config tcp_port $tcp_port
    dict set config tls_port $tls_port

    foreach directive [dict keys $config] {
        puts -nonewline $fp "$directive="
        puts $fp [dict get $config $directive]
    }
    
    close $fp

    set stdout [format "%s/%s" [dict get $config "dir"] "stdout"]
    set stderr [format "%s/%s" [dict get $config "dir"] "stderr"]
    if {[info exists ::cur_test]} {
        set fd [open $stdout "a+"]
        puts $fd "### Starting proxy for test $::cur_test"
        close $fd
    }
    set server_started 0
    set pid [spawn_proxy $config_file $stdout $stderr]
    wait_proxy_started $pid $stdout
    dict set srv "config_file" $config_file
    dict set srv "config" $config
    dict set srv "pid" $pid
    dict set srv "tcp_port" $tcp_port
    dict set srv "tls_port" $tls_port
    dict set srv "host" $::host
    dict set srv "stdout" $stdout
    dict set srv "stderr" $stderr
    dict set srv "client" [xpipe_proxy $::host $tcp_port]
    if {$code ne "undefined"} {
        lappend ::servers $srv
        if {[catch { uplevel 1 $code } error]} {
            send_data_packet $::test_server_fd err $error
        }
        set ::servers [lrange $::servers 0 end-1]
    }
    set ::tags [lrange $::tags 0 end-[llength $tags]]
    stop_proxy $pid
}

proc proxy {{server 127.0.0.1} {port 8892}} {
    set fd [socket $server $port]
}

proc lstats {info} {
    regexp {L\((\d+)\.+?(\d+)\.+?(\d+)\.+?(\d+)\:(\d+)\)} $info match value1 value2 value3 value4 value5
    return $value5
}