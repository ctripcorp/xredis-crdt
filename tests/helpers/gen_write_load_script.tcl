source tests/support/redis.tcl
source tests/support/util.tcl
proc run {script level} {
    catch [uplevel $level $script ] result opts
}
proc gen_write_load {host port seconds script} {
    set start_time [clock seconds]
    set r [redis $host $port 1]
    $r select 9
    set num 10000
    while {$num} {
        run $script 1
        if {[clock seconds]-$start_time > $seconds} {
            exit 0
        }
        # incr num -1
    }
}

gen_write_load [lindex $argv 0] [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
