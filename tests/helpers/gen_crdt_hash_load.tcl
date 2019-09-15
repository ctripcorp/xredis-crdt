source tests/support/redis.tcl

proc gen_crdt_hash_load {host port seconds} {
    set start_time [clock seconds]
    set r [redis $host $port 1]
    $r select 9
    set x 1
    set y 1
    while 1 {
        $r CRDT.HSET [expr rand()] 1 [clock milliseconds] [format "1:%lld;2:%lld" $x $y] 4 [expr rand()] [expr rand()] [expr rand()] [expr rand()]
        incr x
        incr y
        if {[clock seconds]-$start_time > $seconds} {
            exit 0
        }
    }

}

gen_crdt_hash_load [lindex $argv 0] [lindex $argv 1] [lindex $argv 2]
