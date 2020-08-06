source tests/support/redis.tcl

proc randomRangeString {length {chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"}} {
    set range [expr {[string length $chars]-1}]

    set txt ""
    for {set i 0} {$i < $length} {incr i} {
       set pos [expr {int(rand()*$range)}]
       append txt [string range $chars $pos $pos]
    }
    return $txt
}

proc gen_write_load_with_interval {host port seconds interval} {
    set start_time [clock seconds]
    set r [redis $host $port 1]
    $r select 9
    while 1 {
        $r set [randomRangeString 20] [randomRangeString 30]
        $r setex 60000 [randomRangeString 20] [randomRangeString 30]
        set key [randomRangeString 30]
        $r hset $key [randomRangeString 30] [randomRangeString 30]
        $r expire $key 60000
        $r hmset [randomRangeString 30] [randomRangeString 30] [randomRangeString 30] [randomRangeString 30] [randomRangeString 30] [randomRangeString 30] [randomRangeString 30]

        set key [randomRangeString 30]
        $r set $key [randomRangeString 30]
        $r del $key

        set key [randomRangeString 30]
        $r hset $key [randomRangeString 30] [randomRangeString 30]
        $r del $key

        set key [randomRangeString 30]
        $r hset $key [randomRangeString 30] [randomRangeString 30]
        $r hdel $key

        after $interval
        if {[clock seconds]-$start_time > $seconds} {
            exit 0
        }
    }
}

gen_write_load_with_interval [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]