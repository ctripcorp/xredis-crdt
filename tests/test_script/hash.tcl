

test_local_redis "hash" {
    while {1} {
        set load_handle0 [start_write_script $master_host $master_port 7000  { 
            $r hset h k v
            $r hset h k v1
            $r del h  
            $r hset h k 1
            $r hdel h k 
        } ]
        set load_handle1 [start_write_script $peer_host $peer_port 7000  { 
            $r hset h k v
            $r hset h k v1
            $r del h  
            $r hset h k 1
            $r hdel h k 
        } ]
        set load_handle2 [start_write_script $peer2_host $peer2_port 7000  { 
            $r hset h k v
            $r hset h k v1
            $r del h  
            $r hset h k 1
            $r hdel h k 
        } ]
        after 8000
        stop_write_load $load_handle0
        stop_write_load $load_handle1
        stop_write_load $load_handle2
        after 10000

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
            }
            if { [$master crdt.datainfo k] != [$peer2 crdt.datainfo k] }  {
                puts "master and peer2 diff" 
                puts [$master crdt.datainfo k]
                puts [$peer2 crdt.datainfo k]
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

