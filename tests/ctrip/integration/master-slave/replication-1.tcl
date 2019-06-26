start_server {tags {"psync2"} overrides {crdt-gid 1} module {crdt.so} } {
start_server {overrides {crdt-gid 1} module {crdt.so}} {
start_server {overrides {crdt-gid 1} module {crdt.so}} {
start_server {overrides {crdt-gid 1} module {crdt.so}} {
start_server {overrides {crdt-gid 1} module {crdt.so}} {
    set master_id 0                 ; # Current master
    set start_time [clock seconds]  ; # Test start time
    set counter_value 0             ; # Current value of the Redis counter "x"

    # Config
    set debug_msg 0                 ; # Enable additional debug messages

    set no_exit 0                   ; # Do not exit at end of the test

    set duration 1                 ; # Total test seconds

    set genload 1                   ; # Load master with writes at every cycle

    set genload_time 5000           ; # Writes duration time in ms

    set disconnect 1                ; # Break replication link between random
                                      # master and slave instances while the
                                      # master is loaded with writes.

    set disconnect_period 1000      ; # Disconnect repl link every N ms.

    for {set j 0} {$j < 5} {incr j} {
        set R($j) [srv [expr 0-$j] client]
        set R_host($j) [srv [expr 0-$j] host]
        set R_port($j) [srv [expr 0-$j] port]
        if {$debug_msg} {puts "Log file: [srv [expr 0-$j] stdout]"}
    }

    set cycle 1
    test "\[REPLICATION-1\]: --- CYCLE $cycle ---" {
        incr cycle
    }

    # Create a random replication layout.
    # Start with switching master (this simulates a failover).

    # 1) Select the new master.
    set master_id [randomInt 5]
    set used [list $master_id]
    test "\[REPLICATION-1\]: Set #$master_id as master" {
        $R($master_id) slaveof no one
        if {$counter_value == 0} {
            $R($master_id) set x $counter_value
        }
    }

    # 2) Attach all the slaves to a random instance
    while {[llength $used] != 5} {
        while 1 {
            set slave_id [randomInt 5]
            if {[lsearch -exact $used $slave_id] == -1} break
        }
        set rand [randomInt [llength $used]]
        set mid [lindex $used $rand]
        set master_host $R_host($mid)
        set master_port $R_port($mid)

        test "\[REPLICATION-1\]: Set #$slave_id to replicate from #$mid" {
            $R($slave_id) slaveof $master_host $master_port
        }
        lappend used $slave_id
    }

    test "\[REPLICATION-1\]: Bring the master back again for next test" {
        $R($master_id) slaveof no one
        set master_host $R_host($master_id)
        set master_port $R_port($master_id)
        for {set j 0} {$j < 5} {incr j} {
            if {$j == $master_id} continue
            $R($j) slaveof $master_host $master_port
        }

        # Wait for slaves to sync
        wait_for_condition 50 1000 {
            [status $R($master_id) connected_slaves] == 4
        } else {
            fail "Slave not reconnecting"
        }

        set val [randstring 20 20 alpha]
        $R($master_id) set key $val
        set temp_val [$R($master_id) get key]
        assert { $temp_val eq $val}
        after 5
        for {set j 0} {$j < 5} {incr j} {
            if {$j == $master_id} continue
            set current_master_host [status $R($j) master_host]
            set current_master_port [status $R($j) master_port]
            assert { $current_master_host eq $master_host}
            assert { $current_master_port == $master_port}
        }
    }



    if {$no_exit} {
        while 1 { puts -nonewline .; flush stdout; after 1000}
    }

}}}}}