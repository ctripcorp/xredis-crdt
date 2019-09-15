

proc start_bg_hash_data {host port db ops} {
    set tclsh [info nameofexecutable]
    exec $tclsh tests/helpers/bg_hash_data.tcl $host $port $db $ops &
}

proc stop_bg_hash_data {handle} {
    catch {exec /bin/kill -9 $handle}
}

start_server {tags {"crdt-hash"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {

    set redis_host [srv 0 host]
    set redis_port [srv 0 port]

    test {"[crdt_hash.tcl]basic hset and hget"} {
        r hset k-hash f1 v1
        r hget k-hash f1
    } {v1}

    test {"[crdt_hash.tcl]hset and hget an empty item"} {
        r hset k-hash-1 k1 {}
        r hget k-hash-1 k1
    } {}

    test {"[crdt_hash.tcl]Very big payload in HGET/HMSET"} {
        set buf [string repeat "abcd" 1000000]
        r hmset k-hash-2 field $buf
        r hget k-hash-2 field
    } [string repeat "abcd" 1000000]

    test {"over write key"} {
        r hmset k-hash-3 f v f1 v1 f2 v2
        r hset k-hash-3 f3 v2
        r hset k-hash-3 f v2
        r hget k-hash-3 f
    } {v2}

    test {"[crdt_hash.tcl]big hash map"} {
        set load_handle0 [start_bg_hash_data $redis_host $redis_port 9 100000]
        after 1000
        stop_bg_hash_data $load_handle0
    }

    test {"[crdt_hash.tcl]big hash map - 2"} {
        set load_handle0 [start_write_load $redis_host $redis_port 3]
        set load_handle1 [start_write_load $redis_host $redis_port 5]
        after 1000
        stop_write_load $load_handle0
        stop_write_load $load_handle1
    }
}

start_server {tags {"crdt-hash-more"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {

    set redis_host [srv 0 host]
    set redis_port [srv 0 port]

    test {"[crdt-hash.tcl]Test Concurrent-1"} {
        r CRDT.HSET k-hash-1 1 [clock milliseconds] "1:100" 4 f v f1 v1
        after 1
        r CRDT.HSET k-hash-1 1 [clock milliseconds] "1:101" 4 f v2
        r hget k-hash-1 f
    } {v2}

    test {"[crdt_hash.tcl]Test Concurrent-2"} {
        r CRDT.HSET k-hash-2 1 [clock milliseconds] "1:101;2:100" 6 f v f1 v1 f2 v2
        r CRDT.HSET k-hash-2 2 [expr [clock milliseconds] - 2000] "1:101;2:101" 2 f1 v3
        r hget k-hash-2 f1
    } {v3}

    test {"[crdt_hash.tcl]Test Concurrent-3"} {
        r CRDT.HSET k-hash-3 1 [clock milliseconds] "1:101;2:100" 6 f v f1 v1 f2 v2
        r CRDT.HSET k-hash-3 2 [expr [clock milliseconds] + 2000] "1:100;2:101" 2 f1 v3
        r hget k-hash-3 f1
    } {v3}


    # del concurrent conflict with set, set wins
    test {"[crdt_hash.tcl]Test Concurrent DEL-1"} {
        r CRDT.HSET k-hash-5 1 [clock milliseconds] "1:101;2:100" 6 f v f1 v1 f2 v2
        after 1
        r CRDT.DEL_HASH k-hash-5 2 [expr [clock milliseconds] - 2000] "1:100;2:100" "1:99:2:100"
        r hget k-hash-5 f
    } {v}

    # del concurrent with del
    test {"[crdt_hash.tcl]Test Concurrent DEL-2"} {
        r CRDT.HSET k-hash-6 1 [clock milliseconds] "1:100;2:100" 6 f v f1 v1 f2 v2
        r CRDT.DEL_HASH k-hash-6 2 [clock milliseconds] "1:101;2:101" "1:101;2:100"
        r CRDT.DEL_HASH k-hash-6 1 [clock milliseconds] "1:101;2:100" "1:101;2:100"
        r hget k-hash-6 f
    } {}

    test {"[crdt_hash.tcl]crdt hash lot"} {
        set hash_handle0 [start_crdt_hash_load $redis_host $redis_port 3]
        set hash_handle1 [start_crdt_hash_load $redis_host $redis_port 5]
        after 1000
        stop_crdt_hash_load $hash_handle0
        stop_crdt_hash_load $hash_handle1
    }

    # del normal
    test {"[crdt_hash.tcl]Test Normal DEL"} {
        r CRDT.HSET k-hash-7 1 [clock milliseconds] "1:200;2:200" 6 f v f1 v1 f2 v2
        r del k-hash-7
        r hget k-hash-7 f
    } {}

    # hdel normal
    test {"[crdt_hash.tcl]Test Normal H-DEL"} {
        r CRDT.HSET k-hash-8 1 [clock milliseconds] "1:201;2:200" 6 f v f1 v1 f2 v2
        r hdel k-hash-8 f
        r hget k-hash-8 f
    } {}
}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set slaves {}
    $master config set repl-diskless-sync-delay 1

    # set load_handle0 [start_write_load $master_host $master_port 3]
    # set load_handle1 [start_write_load $master_host $master_port 5]

    $master hmset k-hash-101 f v

    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        lappend slaves [srv 0 client]

        # stop_write_load $load_handle0
        # stop_write_load $load_handle1
        # after 1000
        test "Connect multiple slaves at the same time " {
            # Send SLAVEOF commands to slaves
            [lindex $slaves 0] slaveof $master_host $master_port

            # Wait for all the three slaves to reach the "online"
            # state from the POV of the master.
            set retry 500
            while {$retry} {
                set info [r -1 info]
                if {[string match {*slave0:*state=online*} $info]} {
                    break
                } else {
                    incr retry -1
                    after 100
                }
            }
            if {$retry == 0} {
                error "assertion:Slaves not correctly synchronized"
            }
        }

        # Make sure that slaves and master have same
        # number of keys
        wait_for_condition 500 100 {
            [$master dbsize] == [[lindex $slaves 0] dbsize]
        } else {
            fail "Different number of keys between masted and slave after too long time."
        }

        test "master-set-slave-get" {
            $master hmset k-hash-10 f v f1 v1 f2 v2 f3 v3 f4 v4
            after 100
            [lindex $slaves 0] hget k-hash-10 f4
        } {v4}

        test "huge hset/hmset between master and slave" {
            set load_handle2 [start_write_load $master_host $master_port 3]
            set load_handle3 [start_write_load $master_host $master_port 5]
            after 100
            stop_write_load $load_handle2
            stop_write_load $load_handle3
        }

        # Make sure that slaves and master have same
        # number of keys
        wait_for_condition 500 100 {
            [$master dbsize] == [[lindex $slaves 0] dbsize]
        } else {
            fail "Different number of keys between masted and slave after too long time."
        }
    }
}