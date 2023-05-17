start_redis {overrides {repl-diskless-sync-delay 1}} {
    set redis_not_crdt [srv 0 client]
    set redis_not_crdt_host [srv 0 host]
    set redis_not_crdt_port [srv 0 port]

    start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
        set masterA [srv 0 client]
        set masterA_host [srv 0 host]
        set masterA_port [srv 0 port]

        start_server {config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
            set slaveA [srv 0 client]
            set slaveA_host [srv 0 host]
            set slaveA_port [srv 0 port]

            start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
                set masterB [srv 0 client]
                set masterB_host [srv 0 host]
                set masterB_port [srv 0 port]

                start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
                    set slaveB [srv 0 client]
                    set slaveB_host [srv 0 host]
                    set slaveB_port [srv 0 port]
                    set is_debug 0

                    test "deploy" {
                        assert_equal [$redis_not_crdt PING] PONG
                        assert_equal [$masterA PING] PONG
                        assert_equal [$masterB PING] PONG
                        assert_equal [$slaveA PING] PONG
                        assert_equal [$slaveB PING] PONG

                        $slaveA slaveof $masterA_host $masterA_port
                        $slaveB slaveof $masterB_host $masterB_port
                        wait_for_sync $slaveA
                        wait_for_sync $slaveB

                        $masterA peerof 2 $masterB_host $masterB_port
                        $masterB peerof 1 $masterA_host $masterA_port
                        wait_for_peer_sync $masterA
                        wait_for_peer_sync $masterB

                        $masterA set A A
                        $masterB set B B

                        after 1000

                        assert_equal [$masterA get A] A
                        assert_equal [$masterB get A] A
                        assert_equal [$slaveA get A] A
                        assert_equal [$slaveB get A] A

                        assert_equal [$masterA get B] B
                        assert_equal [$masterB get B] B
                        assert_equal [$slaveA get B] B
                        assert_equal [$slaveB get B] B

                        assert_equal [$redis_not_crdt get A] {}
                        assert_equal [$redis_not_crdt get B] {}

                        if {$is_debug} {
                            puts "masterA: $masterA_port, slaveA: $slaveA_port"
                            puts "masterB: $masterB_port, slaveB: $slaveB_port"
                        }
                    }

                    test "missing hash key" {
                        # wait for replication
                        set total 200000
                        set expire 30

                        for {set i 0} {$i < $total} {incr i} {
                            if {$i % 10000 == 0 && $is_debug} {
                                puts "round-$i: [$redis_not_crdt dbsize], [$masterA dbsize], [$masterB dbsize]"
                            }

                            set mail [randomInt 40000]
                            set request_id [randomKey]
                            set access_id [randomKey]

                            if { rand() < 0 } {
                                set master $masterA
                                set slave $slaveA
                                set name "A"
                            } else {
                                set master $masterB
                                set slave $slaveB
                                set name "B"
                            }

                            set sent [$slave hgetall $mail]

                            if {$sent == {} } {
                                if { [$slave exists $mail] == 1 } {
                                    $master hset $mail $request_id $access_id
                                    if { $is_debug } { puts "$name hset?" }
                                } else  {
                                    $master hset $mail $request_id $access_id
                                    $master expire $mail $expire
                                    if { $is_debug } { puts "[clock seconds]: name=$name, expire $mail $expire" }
                                    set setnx_res [$redis_not_crdt setnx $mail 1]
                                    if { $setnx_res != 1 } {
                                        puts "[clock seconds] name=$name, mail:$mail, ttl:[$redis_not_crdt ttl $mail]"
                                    }
                                    assert_equal $setnx_res 1
                                    $redis_not_crdt expire $mail [expr $expire-10]
                                }
                            }

                        }


                    }
                }
            }
        }
    }
}