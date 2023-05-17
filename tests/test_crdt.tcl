# Redis test suite. Copyright (C) 2009 Salvatore Sanfilippo antirez@gmail.com
# This software is released under the BSD License. See the COPYING file for
# more information.

package require Tcl 8.5

set tcl_precision 17
source tests/support/redis.tcl
source tests/support/crdt.tcl
source tests/support/xpipe_proxy.tcl
source tests/support/server.tcl
source tests/support/proxy_server.tcl
source tests/support/tmpfile.tcl
source tests/support/test.tcl
source tests/support/util.tcl
source tests/support/aof.tcl
source tests/test_script/utils.tcl


set ::ci_failed_tests {
    # ubuntu failed
    ctrip/unit/restart_backstream 
    ctrip/integration/master-slave/slave-update-peer-offset-when-master-slave-add-sync
    ctrip/integration/bug/slave-non-read-only-peer-backlog
    ctrip/integration/master-slave/slave-update-peer-offset-when-master-slave-full-sync
    ctrip/master-not-crdt/slave-update-peer-repl-offset
    ctrip/unit/multi
    ctrip/unit/gc
    ctrip/integration/master-slave/psync2
    # macos failed
    ctrip/unit/memefficiency
    ctrip/unit/merge_different_type
}
set ::all_tests {
    ctrip/integration/bug/hash-datamiss
    ctrip/unit/delay_expire
    ctrip/unit/offline_peer
    ctrip/api/result_diff
    ctrip/proxy/config
    ctrip/proxy/one_proxy_peerof
    ctrip/proxy/two_proxy_peerof
    ctrip/proxy/ping 
    ctrip/proxy/rdb
    ctrip/proxy/slave

    ctrip/integration/master-slave/rdb
    ctrip/backstream/lazy_peerof
    ctrip/backstream/some_data
    ctrip/backstream/config_rdb
    ctrip/backstream/config
    ctrip/backstream/rdb
    ctrip/master-not-crdt/load-redis-rdb
    ctrip/integration/master-slave/replication2
    ctrip/integration/composite/peer-offset-check
    ctrip/unit/hash
    ctrip/unit/string
    ctrip/unit/expire
    ctrip/unit/rc1 
    ctrip/unit/rc2 
    ctrip/unit/rc3 
    ctrip/unit/rc4 
    ctrip/unit/rc5
    ctrip/master-not-crdt/convert-set-on-load
    ctrip/master-not-crdt/convert-zset-on-load
    ctrip/integration/bug/free-replication-blocklog
    ctrip/integration/bug/peerof_other_peer_when_master-peer_full_sync
    ctrip/unit/crdt_set
    ctrip/unit/counter2
    ctrip/unit/counter
    ctrip/unit/crdt_zset5
    ctrip/unit/crdt_zset1
    ctrip/unit/crdt_zset2 
    ctrip/unit/crdt_zset3 
    ctrip/unit/crdt_zset4 
    ctrip/unit/crdt_command
    ctrip/basic/set
    ctrip/readonly/basic_crdt_type_del
    ctrip/basic/basic_crdt_type_del
    ctrip/basic/basic_type
    ctrip/master-not-crdt/slave-redis
    ctrip/unit/aof

    ctrip/unit/crdt_publish
    ctrip/integration/master-slave/rdb3
    ctrip/integration/bug/redis-unfree-client-when-master-to-slave
    ctrip/integration/bug/hash-miss-send-when-full-sync
    ctrip/integration/bug/full-sync-timeout

    ctrip/integration/composite/full-sync
    ctrip/unit/crdt_register
    ctrip/unit/crdt_hash
    ctrip/basic/scan
    ctrip/integration/bug/set_binary
    ctrip/integration/bug/del_hash_tombstone_when_merge_hash
    ctrip/master-not-crdt/master-offset
    ctrip/integration/bug/master_is_non_crdt_stream_copy_to_slave
    ctrip/integration/bug/peer-full-sync-losing-meta-data
    ctrip/integration/master-master/full_sync_memory_limit
    ctrip/master-not-crdt/convert-zipmap-hash-on-load
    ctrip/integration/bug/hashtombstone_purge_kv

    ctrip/master-not-crdt/full-sync-error-datatype
    ctrip/master-not-crdt/full-sync-error-datatype2
    ctrip/master-not-crdt/add-sync-stop
    ctrip/master-not-crdt/crdt-redis-when-inited-not-full-sync-from-redis
    ctrip/master-not-crdt/jump-vectorclock
    ctrip/master-not-crdt/master-redis-peer
    ctrip/integration/master-master/full_sync-3
    ctrip/integration/master-master/replication-2
    ctrip/integration/master-master/full_sync-2
    ctrip/integration/bug/slave-non-read-only-send-slave
    
    ctrip/integration/master-slave/auth-gid
    ctrip/integration/bug/master-master-add-sync-when-slave-change-to-master
    
    ctrip/master-not-crdt/more-write-db
    ctrip/master-not-crdt/update-peer-repl-offset
    ctrip/integration/master-slave/more-write-db
    ctrip/integration/master-slave/slave-peer-offset
    ctrip/master-not-crdt/peerof
    ctrip/unit/namespace
    
    ctrip/master-not-crdt/crdt_replid_reuse
    ctrip/integration/bug/not_remember_slave_key_with_expire_when_master_is_non_crdt
    ctrip/readonly/basic_crdt_type
    ctrip/readonly/basic_type

    ctrip/unit/peerof
    ctrip/unit/dict-expend

    ctrip/integration/bug/slave-merge-expired-object-bug
    ctrip/integration/bug/peerof
    ctrip/integration/master-master/add_sync
    ctrip/master-not-crdt/master-redis-peer2
    ctrip/master-not-crdt/master-redis-slave-crdt
    ctrip/master-not-crdt/full-sync-stop
    

    ctrip/integration/master-master/replication
    ctrip/integration/master-master/full_sync
    ctrip/integration/master-master/partial-sync

    ctrip/integration/composite/concurrent-conflict-full
    ctrip/integration/composite/master-slave-failover
    ctrip/unit/crdt_conflict
    ctrip/unit/crdt_del_conflict
    
    ctrip/integration/master-slave/rdb2
    ctrip/integration/master-slave/replication-psync

    ctrip/unit/crdt_del
    ctrip/unit/crdt_hdel_mem_leak
    ctrip/unit/pubsub
    ctrip/integration/bug/redis-crash-when-full-sync-hash-merge
    ctrip/integration/bug/redis-when-full-sync-mater-timeout-vectorclock-update
    ctrip/integration/master-slave/replication
    ctrip/integration/master-slave/replication-1
    ctrip/integration/master-slave/replication-2
    ctrip/integration/master-slave/replication-3
    ctrip/integration/master-slave/replication-4
    ctrip/integration/master-slave/psync2-reg
    
    ctrip/unit/zset
    ctrip/master-not-crdt/convert-data-on-load

    ctrip/unit/peerof_backstream
    
    ctrip/integration/bug/stack_overflow
}   

set ::temp_tests { 
    
    
    #
    test_script/peer_master
    test_script/change_master_slave
    test_script/sync_master
    test_script/sync_slave
    test_script/check
    test_script/peer_master
    test_script/change_master_slave    
#

    ctrip/master-not-crdt/update-peer-repl-offset
    ctrip/master-not-crdt/master-redis-slave-crdt
    
    #
    test_script/rc
    test_script/zadd
    ctrip/unit/crdt_zset2
    ctrip/unit/zset
    ctrip/unit/crdt_zset
    
    ctrip/unit/crdt_set
    ctrip/unit/zset
    test_script/zadd
    test_script/rc
    ctrip/unit/crdt_set
    ctrip/unit/counter
    ctrip/basic/basic_type
    ctrip/master-not-crdt/convert-data-on-load
    ctrip/unit/crdt_zset
    
    ctrip/unit/module_memory
    ctrip/unit/counter
    ctrip/unit/crdt_zset
    ctrip/unit/zset
    ctrip/basic/basic_type
    
    
     
    #####
    ctrip/integration/bug/redis-crash-when-full-sync-hash-merge
    ctrip/integration/bug/redis-when-full-sync-mater-timeout-vectorclock-update
    
    
    ctrip/unit/merge_different_type
    ctrip/integration/composite/master-slave-failover
    ctrip/unit/crdt_hdel_mem_leak
    ctrip/unit/gc
    
    ctrip/unit/crdt_conflict
    ctrip/unit/crdt_del_conflict

    ctrip/integration/master-slave/replication
    ctrip/integration/master-slave/replication-1
    ctrip/integration/master-slave/replication-2
    ctrip/integration/master-slave/replication-3
    ctrip/integration/master-slave/replication-4
    ctrip/integration/master-slave/psync2
    ctrip/integration/master-slave/psync2-reg


    ctrip/integration/master-master/replication
    ctrip/integration/master-master/full_sync
    ctrip/integration/master-master/full_sync-2
    ctrip/integration/master-master/partial-sync
    ctrip/integration/master-master/replication-2
    ctrip/integration/master-master/full_sync-3

    ctrip/integration/composite/full-sync
    ctrip/integration/composite/concurrent-conflict-full
    ctrip/integration/composite/master-slave-failover
    ctrip/integration/master-slave/replication-psync

}


# Index to the next test to run in the ::all_tests list.
set ::next_test 0

set ::host 127.0.0.1
set ::base_port 21111
set ::port 21111
set ::base_proxy_port 41111
set ::proxy_tcp 41111
set ::proxy_tls 51111
set ::traceleaks 0
set ::valgrind 0
set ::stack_logging 1
set ::verbose 0
set ::quiet 0
set ::denytags {}
set ::allowtags {}
set ::external 0; # If "1" this means, we are running against external instance
set ::file ""; # If set, runs only the tests in this comma separated list
set ::curfile ""; # Hold the filename of the current suite
set ::accurate 0; # If true runs fuzz tests with more iterations
set ::force_failure 0
set ::timeout 600; # 10 minutes without progresses will quit the test.
set ::last_progress [clock seconds]
set ::active_servers {} ; # Pids of active Redis instances.

# Set to 1 when we are running in client mode. The Redis test uses a
# server-client model to run tests simultaneously. The server instance
# runs the specified number of client instances that will actually run tests.
# The server is responsible of showing the result to the user, and exit with
# the appropriate exit code depending on the test outcome.
set ::client 0
set ::numclients 16
set ::loop_wait_fail 0

proc execute_tests name {
    set path "tests/$name.tcl"
    set ::curfile $path
    source $path
    send_data_packet $::test_server_fd done "$name"
}

# Setup a list to hold a stack of server configs. When calls to start_server
# are nested, use "srv 0 pid" to get the pid of the inner server. To access
# outer servers, use "srv -1 pid" etcetera.
set ::servers {}
proc srv {args} {
    set level 0
    if {[string is integer [lindex $args 0]]} {
        set level [lindex $args 0]
        set property [lindex $args 1]
    } else {
        set property [lindex $args 0]
    }
    set srv [lindex $::servers end+$level]
    dict get $srv $property
}

# Provide easy access to the client for the inner server. It's possible to
# prepend the argument list with a negative level to access clients for
# servers running in outer blocks.
proc r {args} {
    set level 0
    if {[string is integer [lindex $args 0]]} {
        set level [lindex $args 0]
        set args [lrange $args 1 end]
    }
    [srv $level "client"] {*}$args
}

proc reconnect {args} {
    set level [lindex $args 0]
    if {[string length $level] == 0 || ![string is integer $level]} {
        set level 0
    }

    set srv [lindex $::servers end+$level]
    set host [dict get $srv "host"]
    set port [dict get $srv "port"]
    set config [dict get $srv "config"]
    set client [redis $host $port]
    dict set srv "client" $client

    # select the right db when we don't have to authenticate
    if {![dict exists $config "requirepass"]} {
        $client select 9
    }

    # re-set $srv in the servers list
    lset ::servers end+$level $srv
}

proc redis_deferring_client {args} {
    set level 0
    if {[llength $args] > 0 && [string is integer [lindex $args 0]]} {
        set level [lindex $args 0]
        set args [lrange $args 1 end]
    }

    # create client that defers reading reply
    set client [redis [srv $level "host"] [srv $level "port"] 1]

    # select the right db and read the response (OK)
    $client select 9
    $client read
    return $client
}

# Provide easy access to INFO properties. Same semantic as "proc r".
proc s {args} {
    set level 0
    if {[string is integer [lindex $args 0]]} {
        set level [lindex $args 0]
        set args [lrange $args 1 end]
    }
    status [srv $level "client"] [lindex $args 0]
}

proc cleanup {} {
    if {!$::quiet} {puts -nonewline "Cleanup: may take some time... "}
    flush stdout
    catch {exec rm -rf {*}[glob tests/tmp/redis.conf.*]}
    catch {exec rm -rf {*}[glob tests/tmp/server.*]}
    catch {exec rm -rf {*}[glob tests/tmp/proxy.*]}
    catch {exec rm -rf {*}[glob tests/tmp/*.*]}
    if {!$::quiet} {puts "OK"}
}

proc test_server_main {} {
    cleanup
    set tclsh [info nameofexecutable]
    # Open a listening socket, trying different ports in order to find a
    # non busy one.
    set port [find_available_port 11111]
    if {!$::quiet} {
        puts "Starting test server at port $port"
    }
    socket -server accept_test_clients -myaddr 127.0.0.1 $port

    # Start the client instances
    set ::clients_pids {}
    set start_port [expr {$::base_port+100}]
    set start_proxy_port [expr {$::base_proxy_port+100}]
    # Limit the range of ports used by each client （10000/16=625）
    for {set j 0} {$j < $::numclients} {incr j} {
        set p [exec $tclsh [info script] {*}$::argv \
            --client $port --base_port $start_port --base_proxy_port $start_proxy_port &]
        lappend ::clients_pids $p
        incr start_port 625
        incr start_proxy_port 625
    }

    # Setup global state for the test server
    set ::idle_clients {}
    set ::active_clients {}
    array set ::active_clients_task {}
    array set ::clients_start_time {}
    set ::clients_time_history {}
    set ::failed_tests {}

    # Enter the event loop to handle clients I/O
    after 100 test_server_cron
    vwait forever
}

# This function gets called 10 times per second.
proc test_server_cron {} {
    set elapsed [expr {[clock seconds]-$::last_progress}]

    if {$elapsed > $::timeout} {
        set err "\[[colorstr red TIMEOUT]\]: clients state report follows."
        puts $err
        show_clients_state
        kill_clients
        force_kill_all_servers
        the_end
    }

    after 100 test_server_cron
}

proc accept_test_clients {fd addr port} {
    fconfigure $fd -encoding binary
    fileevent $fd readable [list read_from_test_client $fd]
}

# This is the readable handler of our test server. Clients send us messages
# in the form of a status code such and additional data. Supported
# status types are:
#
# ready: the client is ready to execute the command. Only sent at client
#        startup. The server will queue the client FD in the list of idle
#        clients.
# testing: just used to signal that a given test started.
# ok: a test was executed with success.
# err: a test was executed with an error.
# exception: there was a runtime exception while executing the test.
# done: all the specified test file was processed, this test client is
#       ready to accept a new task.
proc read_from_test_client fd {
    set bytes [gets $fd]
    set payload [read $fd $bytes]
    foreach {status data} $payload break
    set ::last_progress [clock seconds]

    if {$status eq {ready}} {
        if {!$::quiet} {
            puts "\[$status\]: $data"
        }
        signal_idle_client $fd
    } elseif {$status eq {done}} {
        set elapsed [expr {[clock seconds]-$::clients_start_time($fd)}]
        set all_tests_count [llength $::all_tests]
        set running_tests_count [expr {[llength $::active_clients]-1}]
        set completed_tests_count [expr {$::next_test-$running_tests_count}]
        puts "\[$completed_tests_count/$all_tests_count [colorstr yellow $status]\]: $data ($elapsed seconds)"
        lappend ::clients_time_history $elapsed $data
        signal_idle_client $fd
        set ::active_clients_task($fd) DONE
    } elseif {$status eq {ok}} {
        if {!$::quiet} {
            puts "\[[colorstr green $status]\]: $data"
        }
        set ::active_clients_task($fd) "(OK) $data"
    } elseif {$status eq {err}} {
        set err "\[[colorstr red $status]\]: $data"
        puts $err
        lappend ::failed_tests $err
        set ::active_clients_task($fd) "(ERR) $data"
    } elseif {$status eq {exception}} {
        puts "\[[colorstr red $status]\]: $data"
        kill_clients
        force_kill_all_servers
        exit 1
    } elseif {$status eq {testing}} {
        set ::active_clients_task($fd) "(IN PROGRESS) $data"
    } elseif {$status eq {server-spawned}} {
        lappend ::active_servers $data
    } elseif {$status eq {server-killed}} {
        set ::active_servers [lsearch -all -inline -not -exact $::active_servers $data]
    } else {
        if {!$::quiet} {
            puts "\[$status\]: $data"
        }
    }
}

proc show_clients_state {} {
    # The following loop is only useful for debugging tests that may
    # enter an infinite loop. Commented out normally.
    foreach x $::active_clients {
        if {[info exist ::active_clients_task($x)]} {
            puts "$x => $::active_clients_task($x)"
        } else {
            puts "$x => ???"
        }
    }
}

proc kill_clients {} {
    foreach p $::clients_pids {
        catch {exec kill $p}
    }
}

proc force_kill_all_servers {} {
    foreach p $::active_servers {
        puts "Killing still running Redis server $p"
        catch {exec kill -9 $p}
    }
}

# A new client is idle. Remove it from the list of active clients and
# if there are still test units to run, launch them.
proc signal_idle_client fd {
    # Remove this fd from the list of active clients.
    set ::active_clients \
        [lsearch -all -inline -not -exact $::active_clients $fd]

    if 0 {show_clients_state}

    # New unit to process?
    if {$::next_test != [llength $::all_tests]} {
        if {!$::quiet} {
            puts [colorstr bold-white "Testing [lindex $::all_tests $::next_test]"]
            set ::active_clients_task($fd) "ASSIGNED: $fd ([lindex $::all_tests $::next_test])"
        }
        set ::clients_start_time($fd) [clock seconds]
        send_data_packet $fd run [lindex $::all_tests $::next_test]
        lappend ::active_clients $fd
        incr ::next_test
    } else {
        lappend ::idle_clients $fd
        if {[llength $::active_clients] == 0} {
            if {[llength $::failed_tests] == 0 && $::loop_wait_fail} {
                cleanup
                set ::next_test 0
                foreach client $::idle_clients {
                    signal_idle_client $client
                }
                set ::idle_clients {}
            } else {
                the_end
            }
        }
    }
}

# The the_end function gets called when all the test units were already
# executed, so the test finished.
proc the_end {} {
    # TODO: print the status, exit with the rigth exit code.
    puts "\n                   The End\n"
    puts "Execution time of different units:"
    foreach {time name} $::clients_time_history {
        puts "  $time seconds - $name"
    }
    if {[llength $::failed_tests]} {
        puts "\n[colorstr bold-red {!!! WARNING}] The following tests failed:\n"
        foreach failed $::failed_tests {
            puts "*** $failed"
        }
        #cleanup
        exit 1
    } else {
        puts "\n[colorstr bold-white {\o/}] [colorstr bold-green {All tests passed without errors!}]\n"
        #cleanup
        exit 0
    }
}

# The client is not even driven (the test server is instead) as we just need
# to read the command, execute, reply... all this in a loop.
proc test_client_main server_port {
    set ::test_server_fd [socket localhost $server_port]
    fconfigure $::test_server_fd -encoding binary
    send_data_packet $::test_server_fd ready [pid]
    while 1 {
        set bytes [gets $::test_server_fd]
        set payload [read $::test_server_fd $bytes]
        foreach {cmd data} $payload break
        if {$cmd eq {run}} {
            execute_tests $data
        } else {
            error "Unknown test client command: $cmd"
        }
    }
}

proc send_data_packet {fd status data} {
    set payload [list $status $data]
    puts $fd [string length $payload]
    puts -nonewline $fd $payload
    flush $fd
}

proc print_help_screen {} {
    puts [join {
        "--valgrind         Run the test over valgrind."
        "--stack-logging    Enable OSX leaks/malloc stack logging."
        "--accurate         Run slow randomized tests for more iterations."
        "--quiet            Don't show individual tests."
        "--single <unit>    Just execute the specified unit (see next option)."
        "--list-tests       List all the available test units."
        "--clients <num>    Number of test clients (default 16)."
        "--timeout <sec>    Test timeout in seconds (default 10 min)."
        "--force-failure    Force the execution of a test that always fails."
        "--help             Print this help screen."
    } "\n"]
}

# parse arguments
for {set j 0} {$j < [llength $argv]} {incr j} {
    set opt [lindex $argv $j]
    set arg [lindex $argv [expr $j+1]]
    if {$opt eq {--tags}} {
        foreach tag $arg {
            if {[string index $tag 0] eq "-"} {
                lappend ::denytags [string range $tag 1 end]
            } else {
                lappend ::allowtags $tag
            }
        }
        incr j
    } elseif {$opt eq {--valgrind}} {
        set ::valgrind 1
    } elseif {$opt eq {--stack-logging}} {
        if {[string match {*Darwin*} [exec uname -a]]} {
            set ::stack_logging 1
        }
    } elseif {$opt eq {--quiet}} {
        set ::quiet 1
    } elseif {$opt eq {--host}} {
        set ::external 1
        set ::host $arg
        incr j
    } elseif {$opt eq {--port}} {
        set ::port $arg
        incr j
    } elseif {$opt eq {--base_port}} {
        set ::port $arg
        set ::base_port $arg
        incr j
    } elseif {$opt eq {--base_proxy_port}} {
        set ::base_proxy_port $arg
        set ::proxy_tcp $arg
        set ::proxy_tls [expr {$arg+10000}]
        incr j
    } elseif {$opt eq {--accurate}} {
        set ::accurate 1
    } elseif {$opt eq {--force-failure}} {
        set ::force_failure 1
    } elseif {$opt eq {--single}} {
        set ::all_tests $arg
        incr j
    } elseif {$opt eq {--list-tests}} {
        foreach t $::all_tests {
            puts $t
        }
        exit 0
    } elseif {$opt eq {--client}} {
        set ::client 1
        set ::test_server_port $arg
        incr j
    } elseif {$opt eq {--clients}} {
        set ::numclients $arg
        incr j
    } elseif {$opt eq {--timeout}} {
        set ::timeout $arg
        incr j
    } elseif {$opt eq {--help}} {
        print_help_screen
        exit 0
    } elseif {$opt eq {--loop_wait_fail}} {
        set ::loop_wait_fail 1
    } else {
        puts "Wrong argument: $opt"
        exit 1
    }
}
proc attach_to_crdt_replication_stream {gid host port} {
    # set s [socket [srv 0 "host"] [srv 0 "port"]]
    set s [socket $host $port]
    puts -nonewline $s [format "crdt.authGid %s\r\n" $gid]
    flush $s
    while 1 {
        set count [gets $s]
        set prefix [string range $count 0 0]
        if {$prefix ne {}} break; # Newlines are allowed as PINGs.
    }
    
    fconfigure $s -translation binary
    puts -nonewline $s "SYNC\r\n"
    flush $s

    # Get the count
    while 1 {
        set count [gets $s]
        set prefix [string range $count 0 0]
        if {$prefix ne {}} break; # Newlines are allowed as PINGs.
    }
    if {$prefix ne {$}} {
        error "attach_to_replication_stream error. Received '$count' as count."
    }
    set count [string range $count 1 end]

    # Consume the bulk payload
    while {$count} {
        set buf [read $s $count]
        set count [expr {$count-[string length $buf]}]
    }
    return $s
}
proc attach_to_replication_stream {} {
    set s [socket [srv 0 "host"] [srv 0 "port"]]
    fconfigure $s -translation binary
    puts -nonewline $s "SYNC\r\n"
    flush $s

    # Get the count
    while 1 {
        set count [gets $s]
        set prefix [string range $count 0 0]
        if {$prefix ne {}} break; # Newlines are allowed as PINGs.
    }
    if {$prefix ne {$}} {
        error "attach_to_replication_stream error. Received '$count' as count."
    }
    set count [string range $count 1 end]

    # Consume the bulk payload
    while {$count} {
        set buf [read $s $count]
        set count [expr {$count-[string length $buf]}]
    }
    return $s
}

proc read_from_replication_stream {s} {
    fconfigure $s -blocking 0
    set attempt 0
    while {[gets $s count] == -1} {
        if {[incr attempt] == 10} return ""
        after 100
    }
    fconfigure $s -blocking 1
    set count [string range $count 1 end]

    # Return a list of arguments for the command.
    set res {}
    for {set j 0} {$j < $count} {incr j} {
        read $s 1
        set arg [::redis::redis_bulk_read $s]
        if {$j == 0} {set arg [string tolower $arg]}
        lappend res $arg
    }
    return $res
}

proc assert_replication_stream {s patterns} {
    for {set j 0} {$j < [llength $patterns]} {incr j} {
        assert_match [lindex $patterns $j] [read_from_replication_stream $s]
    }
}

proc close_replication_stream {s} {
    close $s
}

# With the parallel test running multiple Redis instances at the same time
# we need a fast enough computer, otherwise a lot of tests may generate
# false positives.
# If the computer is too slow we revert the sequential test without any
# parallelism, that is, clients == 1.
proc is_a_slow_computer {} {
    set start [clock milliseconds]
    for {set j 0} {$j < 1000000} {incr j} {}
    set elapsed [expr [clock milliseconds]-$start]
    expr {$elapsed > 200}
}

if {$::client} {
    if {[catch { test_client_main $::test_server_port } err]} {
        set estr "Executing test client: $err.\n$::errorInfo"
        if {[catch {send_data_packet $::test_server_fd exception $estr}]} {
            puts $estr
        }
        exit 1
    }
} else {
    if {[is_a_slow_computer]} {
        puts "** SLOW COMPUTER ** Using a single client to avoid false positives."
        set ::numclients 1
    }

    if {[catch { test_server_main } err]} {
        if {[string length $err] > 0} {
            # only display error when not generated by the test suite
            if {$err ne "exception"} {
                puts $::errorInfo
            }
            exit 1
        }
    }
}
