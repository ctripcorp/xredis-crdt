start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config set hz 100
    
    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        $peer config set hz 100
        $peer config crdt.set repl-timeout 120
        $peer peerof 1 $master_host $master_port
        $master peerof 2 $peer_host $peer_port
        wait_for_peer_sync $peer 
        wait_for_peer_sync $master
        set peer_data_info [$peer crdt.datainfo z]
        set master_data_info [$master crdt.datainfo z]
        $master zrem z f 
        if {[$master tombstonesize] == 1} {
            #only test gc old null tombstone
            set try 10
            while  {$try > 0} {
                if {[$master tombstonesize] == 0} {
                    break;
                }
                after 500
                set try [expr {$try-1}]
            }
            assert {$try > 0}
        } else {
            assert {[$peer crdt.datainfo z] == $peer_data_info}
            assert {[$master crdt.datainfo z] == $master_data_info}
        }
        
        assert_equal [$master zremrangebyrank z 10 -1] 0
        assert {[$master crdt.datainfo z] == $master_data_info}
        after 1000
        assert {[$peer crdt.datainfo z] == $peer_data_info}


        assert_equal [$master zremrangebyscore z 1 11] 0
        assert {[$master crdt.datainfo z] == $master_data_info}
        after 1000
        assert {[$peer crdt.datainfo z] == $peer_data_info}

       
        assert_equal [$master zremrangebylex z "\[a" "\[z"] 0
        assert {[$master crdt.datainfo z] == $master_data_info}
        after 1000
        assert {[$peer crdt.datainfo z] == $peer_data_info}
        #add zset key

        $master zadd z 10 f 
        while 1 {
            if {[$peer zscore z f] == 10} {
                break;
            }
        }
        set peer_data_info [$peer crdt.datainfo z]
        set master_data_info [$master crdt.datainfo z]
        $master zrem z f1 
        if {[$master tombstonesize] == 1} {
            #only test gc old null tombstone
            set try 10
            while  {$try > 0} {
                if {[$master tombstonesize] == 0} {
                    break;
                }
                after 500
                set try [expr {$try-1}]
            }
            assert {$try > 0}
        } elseif {[$master tombstonesize] == 0} {
            assert {[$peer crdt.datainfo z] == $peer_data_info}
            assert {[$master crdt.datainfo z] == $master_data_info}
        }

        $master crdt.debug_gc zset 0
        assert_equal [$master zremrangebyrank z 1 -1] 0
        
        assert_equal [$master tombstonesize] 0
        assert {[$master crdt.datainfo z] == $master_data_info}
        after 1000
        assert {[$peer crdt.datainfo z] == $peer_data_info}

        assert_equal [$master zremrangebyscore z 11 15] 0
        assert_equal [$master tombstonesize] 0
        assert {$master_data_info == [$master crdt.datainfo z]}
        after 1000
        assert {[$peer crdt.datainfo z] == $peer_data_info}
        
        assert_equal [$master zremrangebylex z "\[g" "\[z"] 0
        assert_equal [$master tombstonesize] 0
        assert {[$master crdt.datainfo z] == $master_data_info}
        after 1000
        assert {[$peer crdt.datainfo z] == $peer_data_info}
    }
}