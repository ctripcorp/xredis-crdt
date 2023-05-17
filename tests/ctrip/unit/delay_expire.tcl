start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        $peer config set non-last-write-delay-expire-time 2000
        assert_equal [$peer config get non-last-write-delay-expire-time] "non-last-write-delay-expire-time 2000"


        #"key" use keymod == gid(2)
        test "wait string delay expire" {
            $peer peerof 1 $master_host $master_port
            $master peerof 2 $peer_host $peer_port
            wait_for_peer_sync $peer 
            wait_for_peer_sync $master 
            $master del key

            $master set key v 
            wait_for_condition  100 10 {
                [$peer get key] == "v"
            } else {
                fail "sync set command fail"
            }
            $master expire key 2
            wait_for_condition  50 10 {
                [$peer ttl key] > 0
            } else {
                fail "sync expire command fail"
            }
            $peer peerof 1 127.0.0.1 0
            after 2500
            assert_equal  [$peer dbsize] 1
            assert_equal  [$master dbsize] 0
            after 1000
            assert_equal  [$peer dbsize] 1
            after 1000
            assert_equal  [$peer dbsize] 0
        }

        test "exec get command undelay expire" {
            $peer peerof 1 $master_host $master_port
            $master peerof 2 $peer_host $peer_port
            wait_for_peer_sync $peer 
            wait_for_peer_sync $master 
            $master del key

            $master set key v 
            $master expire key 2
            wait_for_condition  50 10 {
                [$peer ttl key] > 0
            } else {
                fail "sync expire command fail"
            }
            $peer peerof 1 127.0.0.1 0
            after 2500
            assert_equal  [$peer dbsize] 1
            assert_equal  [$master dbsize] 0
            assert_equal  [$peer get key] {}
            assert_equal  [$peer dbsize] 0
        }

        test "exec get crdt.set command timeout  will del data" {
            $peer peerof 1 $master_host $master_port
            $master peerof 2 $peer_host $peer_port
            wait_for_peer_sync $peer 
            wait_for_peer_sync $master 
            $master del key

            $master set key v 
            $master expire key 2
            wait_for_condition  50 10  {
                [$peer ttl key] > 0
            } else {
                fail "sync expire command fail"
            }
            $peer peerof 1 127.0.0.1 0
            $master set key v1
            after 4500
            $peer peerof 1 $master_host $master_port
            wait_for_peer_sync $peer 
            assert_equal  [$master get key] {}
            assert_equal  [$peer get key] {}
        }

        test "exec get crdt.set command delay expire" {
            $peer peerof 1 $master_host $master_port
            $master peerof 2 $peer_host $peer_port
            wait_for_peer_sync $peer 
            wait_for_peer_sync $master 
            $master del key

            $master set key v 
            $master expire key 2
            wait_for_condition  50 10  {
                [$peer ttl key] > 0
            } else {
                fail "sync expire command fail"
            }
            $peer peerof 1 127.0.0.1 0
            $master set key v1
            after 2500
            $peer peerof 1 $master_host $master_port
            wait_for_peer_sync $peer 
            assert_equal  [$master get key] v1
            assert_equal  [$peer get key] v1
            after 2000
            assert_equal  [$master get key] v1
            assert_equal  [$peer get key] v1
        }

        
    }
}


proc test_delay_expire {type val_is_num set_func get_func } {
    start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_log [srv 0 stdout]
        $master config set loglevel "debug"
        $master config set non-last-write-delay-expire-time 2000
        assert_equal [$master config get non-last-write-delay-expire-time] "non-last-write-delay-expire-time 2000"
        start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_log [srv 0 stdout]
            $peer config set loglevel "debug"

            proc set_val {client key subkey val} $set_func 
            proc get_val {client key subkey default_val} $get_func
            #"key" use keymod == gid(1)
            if {$val_is_num} {
                set val 10
            } else {
                set val "v"
            }
            test "wait $type delay expire" {
                $master peerof 2 $peer_host $peer_port
                $peer peerof 1 $master_host $master_port
                wait_for_peer_sync $master 
                wait_for_peer_sync $peer 
                $peer del key

                set_val $peer key subkey $val
                
                wait_for_condition  100 10 {
                    [get_val $master key subkey $val] == $val
                } else {
                    fail "sync set command fail"
                }
                $peer expire key 2
                wait_for_condition  50 10 {
                    [$master ttl key] > 0
                } else {
                    fail "sync expire command fail"
                }
                $master peerof 2 127.0.0.1 0
                after 2500
                assert_equal  [$master dbsize] 1
                assert_equal  [$peer dbsize] 0
                after 1000
                assert_equal  [$master dbsize] 1
                after 1000
                assert_equal  [$master dbsize] 0
            }

            test "exec $type read command undelay expire" {
                $master peerof 2 $peer_host $peer_port
                $peer peerof 1 $master_host $master_port
                wait_for_peer_sync $master 
                wait_for_peer_sync $peer 
                $peer del key

                set_val $peer key subkey $val
                
                wait_for_condition  100 10 {
                    [get_val $master key subkey $val] == $val
                } else {
                    fail "sync set command fail"
                }
                $peer expire key 2
                wait_for_condition  50 10 {
                    [$master ttl key] > 0
                } else {
                    fail "sync expire command fail"
                }

                $master peerof 2 127.0.0.1 0
                after 2500
                assert_equal  [$master dbsize] 1
                assert_equal  [$peer dbsize] 0
                assert_equal  [get_val $master key subkey $val] {}
                assert_equal  [$master dbsize] 0
            }

            test "exec $type  crdt sync command timeout  will del data" {
                $master peerof 2 $peer_host $peer_port
                $peer peerof 1 $master_host $master_port
                wait_for_peer_sync $master 
                wait_for_peer_sync $peer 
                $peer del key

                set_val $peer key subkey $val
                
                wait_for_condition  100 10 {
                    [get_val $master key subkey $val] == $val
                } else {
                    fail "sync set command fail"
                }
                $peer expire key 2
                wait_for_condition  50 10 {
                    [$master ttl key] > 0
                } else {
                    fail "sync expire command fail"
                }

                
                $master peerof 2 127.0.0.1 0
                $peer PERSIST key
                
                after 4500
                $master peerof 2 $peer_host $peer_port
                wait_for_peer_sync $master
                after 1000
                assert_equal  [get_val $master key subkey $val] {}
                assert_equal  [get_val $peer key subkey $val] {}
            }

            test "exec $type  crdt sync command delay expire" {
                $master peerof 2 $peer_host $peer_port
                $peer peerof 1 $master_host $master_port
                wait_for_peer_sync $master 
                wait_for_peer_sync $peer 
                $peer del key

                set_val $peer key subkey $val
                wait_for_condition  100 10 {
                    [get_val $master key subkey $val] == $val
                } else {
                    fail "sync set command fail"
                }
                $peer expire key 2
                wait_for_condition  50 10 {
                    [$master ttl key] > 0
                } else {
                    fail "sync expire command fail"
                }

                $master peerof 2 127.0.0.1 0
                $peer PERSIST key
                after 2500
                $master peerof 2 $peer_host $peer_port
                wait_for_peer_sync $master 
                assert_equal  [get_val $master key subkey $val] $val
                assert_equal  [get_val  $peer  key subkey $val] $val
                after 2000
                assert_equal  [get_val $master key subkey $val] $val
                assert_equal  [get_val $peer   key subkey $val] $val
            }
        }
    }

}

test_delay_expire "hash" 0 {
    $client hset $key $subkey $val
} { 
    return [$client hget $key $subkey] 
}

test_delay_expire "set" 0 {
    $client sadd $key $subkey 
} { 
    if {[$client SISMEMBER $key $subkey] == 1} {
        return $default_val
    } else {
        return {}
    }
}

test_delay_expire "zset" 1 {
    $client zadd $key $val $subkey 
} { 
    return [$client zscore $key $subkey]
}

test_delay_expire "count" 1 {
    $client set $key $val 
} { 
    return [$client get $key ]
}

