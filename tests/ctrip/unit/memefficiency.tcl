proc get_current_memory {client} {
    set info [$client info memory]
    set regstr [format "\r\n%s:(.*?)\r\n" "used_memory"]
    regexp $regstr $info match value 
    set _ $value
}

# if redis reached maxmemory, 
proc almost_equal { target base } {
    set equal 0
    if { $target >= $base && $target < $base + $base/100 } {
        set equal 1
    }
    set _ $equal
}

proc wait_swap_finished {client} {
    for {set i 0} {$i < 36000} {incr i} {
        set info [$client info swaps]
        regexp "\r\nswap_inprogress:(.*?)\r\n" $info match swap_inprogress
        regexp "\r\nswap_last_finish:(.*?)\r\n" $info match swap_last_finish
        set elpased [expr [clock seconds] - $swap_last_finish]
        # puts "$i: swap_inprogress($swap_inprogress) swap_last_finish($swap_last_finish) dbsize([$client dbsize])"
        # swap finished: no swap in progress and swap finished for longer than 1s
        if {$swap_inprogress == 0 && $elpased > 1} {
            break
        } else {
            after 100
        }
    }
}

test "stand-alone" {
    start_server {tags {"stand-alone"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_gid  1
        $master config set maxmemory-policy allkeys-lru
        $master config set maxmemory [expr [get_current_memory $master] + 4194304]

        for {set i 0 } { $i < 20000} {incr i} {
            $master set $i $i
        }

        set master_dbsize [$master dbsize]
        assert [almost_equal $master_dbsize 20000]
        assert_equal [$master tombstonesize] 0
    }
}

test "stand-alone  some type" {
    start_server {tags {"stand-alone  some type"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_gid  1
        $master config set maxmemory-policy allkeys-lru
        $master config set maxmemory 5mb
        for {set i 0 } { $i < 1000} {incr i} {
            $master set $i $i 
        }
        for {set i 1000} {$i < 2000} {incr i} {
            $master set $i a
        }
        for {set i 2000} {$i < 3000} {incr i} {
            $master hset $i $i $i 
        }
        for {set i 3000} {$i < 4000} {incr i} {
            $master sadd $i $i [expr $i + 1] 
        }
        for {set i 4000} {$i < 5000} {incr i} {
            $master zadd $i $i $i 
        }
        # assert {[$master dbsize] < 100}
        assert_equal [$master tombstonesize] 0
        set master_dbsize [$master dbsize]
        assert [almost_equal $master_dbsize 5000]
        assert {$master_dbsize >= 5000 && $master_dbsize < 5050}
    }
}

test "only add rc" {
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
        start_server {tags {"only add rc"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
            
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_gid  1
            
            start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
                set peer [srv 0 client]
                set peer_host [srv 0 host]
                set peer_port [srv 0 port]
                set peer_stdout [srv 0 stdout]
                set peer_gid  2
                $peer peerof $master_gid $master_host $master_port
                $slave slaveof $master_host $master_port 
                # puts [$slave config get "maxmemory"]
                wait_for_peer_sync $peer 
                wait_for_sync $slave
                # puts [$slave config get "maxmemory"]
                for {set i 1000 } { $i < 2000} {incr i} {
                    $master set $i $i 
                }
                after 1000
                $master config set maxmemory [get_current_memory $master]
                for {set i 0 } { $i < 1000} {incr i} {
                    $master set $i $i 
                }
                after 2000
                assert {[$master dbsize] > 0}
                # puts "master([$master dbsize]) peer([$peer dbsize]) slave([$slave dbsize])"
                assert [almost_equal [$master dbsize] [$peer dbsize]]
                assert [almost_equal [$master dbsize] [$slave dbsize]]
                assert_equal [$master tombstonesize] 0
                assert_equal [$peer tombstonesize] 0
                assert_equal [$slave tombstonesize] 0
                
                assert_equal [crdt_stats $master evicted_tombstones] 0
                assert_equal [crdt_stats $peer evicted_tombstones] 0
                assert_equal [crdt_stats $slave evicted_tombstones] 0
            }
        }
    }
}

test "some db" {
    start_server {tags {"some db"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_gid  1
        $master config crdt.set repl-diskless-sync-delay 1
        $master config set repl-diskless-sync-delay 1
        $master config crdt.set repl-backlog-size 1mb
        $master config set repl-backlog-size 1mb
        $master config crdt.set repl-backlog-ttl 10
        $master config set maxmemory-policy allkeys-lru
        start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
            set peer [srv 0 client]
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_stdout [srv 0 stdout]
            set peer_gid  2
            $peer peerof $master_gid $master_host $master_port
            wait_for_peer_sync $peer 
            $peer peerof 3 127.0.0.1 0
            assert {[$master tombstonesize] == 0}
            for {set i 1000 } { $i < 2000} {incr i} {
                $master set $i $i 
                $master del $i
            }
            assert {[$master tombstonesize] == 1000}

            for {set i 500 } { $i < 1000} {incr i} {
                $master set $i $i
            }
            $master config set maxmemory [get_current_memory $master]
            for {set i 0 } { $i < 500} {incr i} {
                $master set $i $i
            }
            after 1000
            assert [almost_equal [$master dbsize] 1000]
            assert [almost_equal [$master dbsize] [$peer dbsize]]
            assert_equal [$master tombstonesize]  [$peer tombstonesize]
            assert_equal [crdt_stats $master evicted_tombstones] 0
            assert_equal [crdt_stats $peer evicted_tombstones] 0
        }
    }
}

test "other db tombstone" {
    start_server {tags {"other db tombstone"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
        set master [srv 0 client]
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_gid  1
        $master config crdt.set repl-diskless-sync-delay 1
        $master config set repl-diskless-sync-delay 1
        $master config crdt.set repl-backlog-size 1mb
        $master config set repl-backlog-size 1mb
        $master config crdt.set repl-backlog-ttl 10
        $master config set maxmemory-policy allkeys-lru
        $master peerof 3 127.0.0.1 0
        start_server {tags {"other db tombstone"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_gid  1
            $slave slaveof $master_host $master_port
            start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
                set peer [srv 0 client]
                set peer_host [srv 0 host]
                set peer_port [srv 0 port]
                set peer_stdout [srv 0 stdout]
                set peer_gid  2
                $peer peerof $master_gid $master_host $master_port
                $slave slaveof $master_host $master_port
                wait_for_peer_sync $peer 
                wait_for_sync $slave
                $peer peerof 3 127.0.0.1 0
                assert {[$master tombstonesize] == 0}
                $master select 2
                for {set i 1000 } { $i < 2000} {incr i} {
                    $master set $i $i 
                    $master del $i
                }
                after 1000
                assert {[$master tombstonesize] == 1000}
                $peer select 2
                assert_equal [$peer tombstonesize] 1000
                # puts [$master crdt.info replication]
                after 1000
                
                $master select 9
                for {set i 500 } { $i < 1000} {incr i} {
                    $master set $i $i
                }
                $master config set maxmemory [get_current_memory $master]
                for {set i 0 } { $i < 500} {incr i} {
                    $master set $i $i
                }
                after 1000
                $peer select 9
                $slave select 9
                set master_size [$master dbsize]
                set peer_size [$peer dbsize]
                set slave_size [$slave dbsize]
                assert [almost_equal $master_size $peer_size]
                assert [almost_equal $master_size $slave_size]
                if {[$master tombstonesize] > 0} {
                    assert_equal $master_size 1000
                }
                $master select 2
                $peer select 2
                $slave select 2
                assert_equal [$master tombstonesize] [$peer tombstonesize]
                assert_equal [crdt_stats $master evicted_tombstones] 0
                assert_equal [crdt_stats $peer evicted_tombstones] 0
                assert_equal [crdt_stats $slave evicted_tombstones] 0
            }
        }
    }
}
