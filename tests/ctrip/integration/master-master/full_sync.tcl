
proc log_file_matches {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    string match $pattern $content
}


set dl yes
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    set master [srv 0 client]
    $master config crdt.set repl-diskless-sync $dl
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_gid  1
    set slaves {}

    $master config crdt.set repl-diskless-sync-delay 1

    # Start to write random val(set k v). for 5 sec
    # the data will be used in full-sync
    set load_handle0 [start_write_load $master_host $master_port 3]
    set load_handle1 [start_write_load $master_host $master_port 5]
    set load_handle2 [start_write_load $master_host $master_port 20]
    set load_handle3 [start_write_load $master_host $master_port 8]
    set load_handle4 [start_write_load $master_host $master_port 4]

    after 5000
    # Stop the write load
    stop_write_load $load_handle0
    stop_write_load $load_handle1
    stop_write_load $load_handle2
    stop_write_load $load_handle3
    stop_write_load $load_handle4

    set keynum [$master dbsize]
    puts {master key numbers: }
    puts $keynum

    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        lappend slaves [srv 0 client]
        start_server {config {crdt.conf} overrides {crdt-gid 3} module {crdt.so}} {
            lappend slaves [srv 0 client]
            start_server {config {crdt.conf} overrides {crdt-gid 4} module {crdt.so}} {
                lappend slaves [srv 0 client]
                test "Connect multiple slaves at the same time (issue #141), diskless=$dl" {
                    # Send PEEROF commands to slaves
                    [lindex $slaves 0] peerof $master_gid $master_host $master_port
                    [lindex $slaves 1] peerof $master_gid $master_host $master_port
                    [lindex $slaves 2] peerof $master_gid $master_host $master_port

                    # Wait for all the three slaves to reach the "online"
                    # state from the POV of the master.
                    set retry 500
                    while {$retry} {
                        set info [r -3 info crdt]
                        if {[string match {*slave0:*state=online*slave1:*state=online*slave2:*state=online*} $info]} {
                            break
                        } else {
                            incr retry -1
                            after 100
                        }
                    }
                    if {$retry == 0} {
                        error "assertion:Slaves not correctly synchronized"
                    }

                    # Wait that slaves acknowledge they are online so
                    # we are sure that DBSIZE and DEBUG DIGEST will not
                    # fail because of timing issues.
                    wait_for_condition 500 100 {
                        [lindex [[lindex $slaves 0] crdt.role slave $master_gid] 3] eq {connected} &&
                        [lindex [[lindex $slaves 1] crdt.role slave $master_gid] 3] eq {connected} &&
                        [lindex [[lindex $slaves 2] crdt.role slave $master_gid] 3] eq {connected}
                    } else {
                        fail "Slaves still not connected after some time"
                    }


                    # Make sure that slaves and master have same
                    # number of keys
                    wait_for_condition 500 100 {
                        [$master dbsize] == [[lindex $slaves 0] dbsize] &&
                        [$master dbsize] == [[lindex $slaves 1] dbsize] &&
                        [$master dbsize] == [[lindex $slaves 2] dbsize]
                    } else {
                        fail "Different number of keys between masted and slave after too long time."
                    }

                }
           }
        }
    }
}