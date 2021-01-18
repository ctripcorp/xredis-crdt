
proc check {current peer peer2 k} {
    set m_info [$current crdt.datainfo $k]
    set p_info [$peer crdt.datainfo $k]
    set p2_info [$peer2 crdt.datainfo $k]
    if { $m_info != $p_info }  {
        puts "master and peer diff" 
        puts $m_info
        puts $p_info
        if {[string length $m_info] != [string length $p_info]} {
            set run 0
        }
    }
    if { $m_info != $p2_info }  {
        puts "master and peer2 diff" 
        puts $m_info
        puts $p2_info
        if {[string length $m_info] != [string length $p2_info]} {
            set run 0
        }
    }
}


test_local_redis "sadd" {

         
    set run 1
    while {$run} {
        set load_handle0 [start_write_script $master_host $master_port 7000  { 
            $r sadd k a b c
            $r srem k a 
            $r del k 
        } ]
        set load_handle1 [start_write_script $peer_host $peer_port 7000  { 
            $r sadd k a b c
            $r srem k b 

            $r del k
        } ]
        set load_handle2 [start_write_script $peer2_host $peer2_port 7000  { 
            $r sadd k a b c
            $r srem k c  
            $r del k
        } ]
        #            $r sadd k [randomValue] [randomValue]
        #            $r sadd k [randomValue] [randomValue]
        after 8000
        stop_write_load $load_handle0
        stop_write_load $load_handle1
        stop_write_load $load_handle2
        after 10000
        # cp $master_log $peer_log $peer2_log
        
        test "sadd" {
            set m_info [$master crdt.datainfo k]
            set p_info [$peer crdt.datainfo k]
            set p2_info [$peer2 crdt.datainfo k]
            if { $m_info != $p_info }  {
                puts "master and peer diff" 
                puts $m_info
                puts $p_info
                if {[string length $m_info] != [string length $p_info]} {
                    set run 0
                }
            }
            if { $m_info != $p2_info }  {
                puts "master and peer2 diff" 
                puts $m_info
                puts $p2_info
                if {[string length $m_info] != [string length $p2_info]} {
                    set run 0
                }
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
    # }    
}

