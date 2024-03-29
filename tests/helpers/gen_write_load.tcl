source tests/support/redis.tcl

proc gen_write_load {host port seconds} {
    set start_time [clock seconds]
    set r [redis $host $port 1]
    $r select 9
    while 1 {
        $r set [expr rand()] [expr rand()]
        $r hset [expr rand()] [expr rand()] [expr rand()]
        $r hmset [expr rand()] [expr rand()] [expr rand()] [expr rand()] [expr rand()] [expr rand()] [expr rand()]
        $r sadd [expr rand()] [expr rand()] [expr rand()]
        $r incr [expr rand()] 
        if {[clock seconds]-$start_time > $seconds} {
            exit 0
        }
    }
}

gen_write_load [lindex $argv 0] [lindex $argv 1] [lindex $argv 2]
