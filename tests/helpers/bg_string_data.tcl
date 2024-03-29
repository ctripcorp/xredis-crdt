source tests/support/redis.tcl
source tests/support/util.tcl

proc bg_string_data {host port db ops} {
    set r [redis $host $port]
    $r select $db
    createAllStringDataset $r $ops
}

bg_string_data [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
