source tests/support/redis.tcl

proc gen_write_load {host port seconds type} {
    set start_time [clock seconds]
    set r [redis $host $port 1]
    $r select 9
    set zset_index 0 
    set hash_index 0 
    set set_index 0
    set string_index 0
    while 1 {
        if {$type eq "zset" || $type eq "all"} {
            set zset_index [expr $zset_index + 1]
            $r zadd zset_test_$zset_index 1 zset_1_$zset_index
            $r zadd zset_test_$zset_index 2 zset_2_$zset_index
            $r zadd zset_test_$zset_index 3 zset_3_$zset_index
            $r expire zset_test_$zset_index 2
        }

        if {$type eq "hash" || $type eq "all"} {
            set hash_index [expr $hash_index + 1]
            $r hset hash_test_$hash_index hash_1_$hash_index v 
            $r hset hash_test_$hash_index hash_2_$hash_index v 
            $r hset hash_test_$hash_index hash_3_$hash_index v 
            $r expire hash_test_$hash_index 2
        }
        
        if {$type eq "hash" || $type eq "all"} {
            set set_index [expr $hash_index + 1]
            $r sadd sadd_test_$set_index  sadd_1_$set_index
            $r sadd sadd_test_$set_index  sadd_2_$set_index
            $r sadd sadd_test_$set_index  sadd_3_$set_index
            $r expire sadd_test_$set_index 2
        }

        if {$type eq "hash" || $type eq "all"} {
            set string_index [expr $string_index + 1]
            $r set string_test_$string_index v 
            $r expire string_test_$string_index 2
        }
       

        if {[clock seconds]-$start_time > $seconds} {
            exit 0
        }
    }
}

gen_write_load [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
