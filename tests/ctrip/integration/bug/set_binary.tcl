proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config set repl-diskless-sync-delay 1
    $master config crdt.set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set slave [srv 0 client]
        set slave_gid 1
        set slave_host [srv 0 host]
        set slave_port [srv 0 port]
        set slave_log [srv 0 stdout]
        start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
            set peer [srv 0 client]
            set peer_gid 2
            set peer_host [srv 0 host]
            set peer_port [srv 0 port]
            set peer_log [srv 0 stdout]
            
            $slave slaveof $master_host $master_port
            $peer peerof $master_gid $master_host $master_port
            wait_for_sync $slave
            wait_for_peer_sync $peer
            
            # puts data
            $master mset x 10 y "foo bar" z "x x x x x x x\n\n\r\n"

            $master set [binary format B* 01000000000000000000000] v
            $master set k [binary format B* 01000000000000000000000]
            $master set [binary format B* 01100000000000000000000] [binary format B* 10000000000000000000000] 
            $master hset h k [binary format B* 01000000000000000000000]
            $master hset [binary format B* 01000000000000000000001] [binary format B* 01000000000000000000011] [binary format B* 01000000000000000000111]
            # puts [$master get {YWG|BJS|RT}]
            set argvs {}
            for {set i 0} {$i < 100} {incr i} {
                 set argv {}
                 lappend argv [randomKey]
                 lappend argv [randomValue]
                 lappend argvs $argv
                 $master set  [lindex $argv 0] [lindex $argv 1]
                 $master hset hash_random [lindex $argv 0] [lindex $argv 1]
            }
            after 2000
            # read_file $slave_log
            assert_equal  [$slave get [binary format B* 01000000000000000000000]] v
            assert_equal [$slave get k] [binary format B* 01000000000000000000000]
            assert_equal  [$slave get [binary format B* 01100000000000000000000]] [binary format B* 10000000000000000000000] 
            assert_equal [$slave hget h k] [binary format B* 01000000000000000000000]
            assert_equal [$slave hget [binary format B* 01000000000000000000001] [binary format B* 01000000000000000000011]] [binary format B* 01000000000000000000111]
            assert_equal [$slave mget x y z ] [list 10 {foo bar} "x x x x x x x\n\n\r\n"]

            assert_equal  [$peer get [binary format B* 01000000000000000000000]] v
            assert_equal [$peer get k] [binary format B* 01000000000000000000000]
            assert_equal  [$peer get [binary format B* 01100000000000000000000]] [binary format B* 10000000000000000000000] 
            assert_equal [$peer hget h k] [binary format B* 01000000000000000000000]
            assert_equal [$peer hget [binary format B* 01000000000000000000001] [binary format B* 01000000000000000000011]] [binary format B* 01000000000000000000111]
            assert_equal [$peer mget x y z ] [list 10 {foo bar} "x x x x x x x\n\n\r\n"]

            for {set i 0} {$i < 100} {incr i} {
                 set  argv [lindex argvs $i]
                 assert_equal [$slave get  [lindex $argv 0]] [lindex $argv 1]
                 assert_equal [$slave hget hash_random [lindex $argv 0]] [lindex $argv 1]
                 assert_equal [$slave get  [lindex $argv 0]] [lindex $argv 1]
                 assert_equal [$slave hget hash_random [lindex $argv 0]] [lindex $argv 1]
            }

        }
    }
}


