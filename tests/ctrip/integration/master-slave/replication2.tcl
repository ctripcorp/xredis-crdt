
proc get_current_memory {client} {
    set info [$client info memory]
    set regstr [format "\r\n%s:(.*?)\r\n" "used_memory"]
    regexp $regstr $info match value 
    set _ $value
}

proc crdt_info_property { client property } {
    set info [ $client crdt.info]
    if {[regexp "\r\n$property:(.*?)\r\n" $info _ value]} {
        set _ $value
    }
}
start_server {tags {"only add rc"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_gid  1
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set repl-backlog-size 1mb
    $master config set repl-backlog-size 1mb
    # $master config crdt.set repl-backlog-ttl 10
    $master config set maxmemory-policy allkeys-lru
    start_server {tags {"slave"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set slave [srv 0 client]
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_stdout [srv 0 stdout]
        set slave_gid  1
        start_server {tags {"peer"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so}} {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_stdout [srv 0 stdout]
            set peer_gid  2
            set load_handle [start_write_script $master_host $master_port 10000 {
                $r sadd [randomInt 123456789] a b c
                # $r srem myset a
                # $r del myset
                $r set [randomInt 123456789] [randomInt 123456789]
                $r set [randomInt 123456789] [randomString]
                $r mset [randomInt 123456789] [randomValue] mykv3 [randomValue]
                $r hset [randomInt 123456789] [randomKey] [randomValue]
                $r incrby [randomInt 123456789] 10
                $r incrbyfloat [randomInt 123456789] 20.0
                $r zadd [randomInt 123456789]  [randomFloat -99999999 999999999] mfield
                $r zadd [randomInt 123456789] [randomInt 9999999] [randomValue] [randomInt 9999999] [randomValue]
                $r zincrby [randomInt 123456789] [randomFloat -999999999 99999999] mfield
                # $r del myrc
                # $r del mykv
                # $r del myhash
                # $r del myzset2  
            }]
             set load_handle1 [start_write_script $master_host $master_port 10000 {
                $r sadd [randomInt 123456789] a b c
                # $r srem myset a
                # $r del myset
                $r set [randomInt 123456789] [randomInt 123456789]
                $r set [randomInt 123456789] [randomString]
                $r mset [randomInt 123456789] [randomValue] mykv3 [randomValue]
                $r hset [randomInt 123456789] [randomKey] [randomValue]
                $r incrby [randomInt 123456789] 10
                $r incrbyfloat [randomInt 123456789] 20.0
                $r zadd [randomInt 123456789]  [randomFloat -99999999 999999999] mfield
                $r zadd [randomInt 123456789] [randomInt 9999999] [randomValue] [randomInt 9999999] [randomValue]
                $r zincrby [randomInt 123456789] [randomFloat -999999999 99999999] mfield
                # $r del myrc
                # $r del mykv
                # $r del myhash
                # $r del myzset2 
            }]
            set load_handle2 [start_write_script $master_host $master_port 10000 {
                $r sadd [randomInt 123456789] a b c
                # $r srem myset a
                # $r del myset
                $r set [randomInt 123456789] [randomInt 123456789]
                $r set [randomInt 123456789] [randomString]
                $r mset [randomInt 123456789] [randomValue] mykv3 [randomValue]
                $r hset [randomInt 123456789] [randomKey] [randomValue]
                $r incrby [randomInt 123456789] 10
                $r incrbyfloat [randomInt 123456789] 20.0
                $r zadd [randomInt 123456789]  [randomFloat -99999999 999999999] mfield
                $r zadd [randomInt 123456789] [randomInt 9999999] [randomValue] [randomInt 9999999] [randomValue]
                $r zincrby [randomInt 123456789] [randomFloat -999999999 99999999] mfield
                # $r del myrc
                # $r del mykv
                # $r del myhash
                # $r del myzset2  
            }]
            after 10000
            puts [$master dbsize]
            stop_write_load $load_handle
            stop_write_load $load_handle1
            stop_write_load $load_handle2
            $peer peerof $master_gid $master_host $master_port
            $slave slaveof $master_host $master_port
            set n 50
            while {$n} {
                # puts [$master info persistence]
                # puts [crdt_info_property $master rdb_bgsave_in_progress]
                # puts [status $master rdb_bgsave_in_progress]
                assert {[expr [crdt_info_property $master rdb_bgsave_in_progress] + [status $master rdb_bgsave_in_progress]] < 2}
                # puts [status $slave master_link_status]
                # puts [crdt_status $peer peer0_link_status] 
                if {[status $slave master_link_status] == "up" && [crdt_status $peer peer0_link_status]  == "up"} {
                    break
                }
                incr n -1
                after 100
            }
        }
    }
   
}