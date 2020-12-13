# test_local_redis "rc" {
# create_crdts "rc" {
test_local_redis "rc" {
    set run 10
    while {$run} {
    
        set load_handle0 [start_write_script $master_host $master_port 7000  { 
            $r mset k 1
            $r incrbyfloat k 3
            $r del k 
            $r incrby k 1
            $r mset k "abc" 
        } ]
        set load_handle1 [start_write_script $peer_host $peer_port 7000  { 
            $r mset k 2
            $r incrbyfloat k 2
            $r mset k "bac" 
            $r del k 
            $r incrby k 2
        } ]
        set load_handle2 [start_write_script $peer2_host $peer2_port 7000  { 
            $r mset k 3
            $r incrby k 1
            $r mset k "cba" 
            $r del k
            $r incrby k 3
            $r del k 
            $r incrby k 2
        } ]
        after 8000
        stop_write_load $load_handle0
        stop_write_load $load_handle1
        stop_write_load $load_handle2
        after 10000
        incr run -1
        if { [$master crdt.memory] != [$peer crdt.memory] } {
            puts "diff" 
            puts [$master crdt.memory]
            puts [$peer crdt.memory]
        }
        test "set" {
            if { [$master crdt.datainfo k] != [$peer crdt.datainfo k] }  {
                puts "master and peer diff" 
                puts [$master crdt.datainfo k]
                puts [$peer crdt.datainfo k]
                set run 0
            }
            if { [$master crdt.datainfo k] != [$peer2 crdt.datainfo k] }  {
                puts "master and peer2 diff" 
                puts [$master crdt.datainfo k]
                puts [$peer2 crdt.datainfo k]
                set run 0
            }

            if { [$master crdt.memory] != [$peer crdt.memory] } {
                puts "master and peer diff" 
                puts [$master crdt.memory]
                puts [$peer crdt.memory]
            }

            if { [$master crdt.memory] != [$peer2 crdt.memory] } {
                puts "master and peer2 diff" 
                puts [$master crdt.memory]
                puts [$peer2 crdt.memory]
            }
        }
    }
    
}

