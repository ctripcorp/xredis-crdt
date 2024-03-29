source tests/support/redis.tcl
source tests/support/util.tcl

proc bg_hash_data {host port db ops} {
    set r [redis $host $port]
    $r select $db
    createAllHashDataset $r $ops
}

bg_hash_data [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
