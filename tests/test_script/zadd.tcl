

test_local_redis "zadd" {

    set run 1
    while {$run} {
        set load_handle0 [start_write_script $master_host $master_port 7000  { 
            $r zadd k [randomFloat 1 100] a
            $r zincrby k [randomFloat 1 100] a
            $r zadd k 2 b
            $r zrem k a 
            $r zrem k b
            $r zincrby k [randomFloat 1 100] b
            $r del k 
        } ]
        set load_handle1 [start_write_script $peer_host $peer_port 7000  { 
            $r zincrby k [randomFloat 1 100] a 
            $r zadd k [randomFloat 1 100] b 
            $r zincrby k [randomFloat 1 100] b
            $r zrem k a 
            $r zrem k b
            $r zadd k 3 a
            $r del k 
        } ]
        set load_handle2 [start_write_script $peer2_host $peer2_port 7000  { 
            $r zincrby k [randomFloat 1 100] a 
            $r zadd k [randomFloat 1 100] b 
            $r zincrby k [randomFloat 1 100] b
            $r zrem k a 
            $r zrem k b
            $r zadd k 3 a
            $r del k 
            
        } ]
        after 8000
        stop_write_load $load_handle0
        stop_write_load $load_handle1
        stop_write_load $load_handle2
        after 20000

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

