source tests/support/redis.tcl

proc gen_write_db_load {host port seconds db} {
    set start_time [clock seconds]
    set r [redis $host $port 1]
    $r select $db
    while 1 {
        $r set [expr rand()] [expr rand()]
        $r hset [expr rand()] [expr rand()] [expr rand()]
        $r hmset [expr rand()] [expr rand()] [expr rand()] [expr rand()] [expr rand()] [expr rand()] [expr rand()]
        if {[clock seconds]-$start_time > $seconds} {
            exit 0
        }
    }
}

gen_write_db_load [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
