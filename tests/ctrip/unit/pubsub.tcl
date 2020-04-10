start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    proc __consume_subscribe_messages {client type channels} {
        set numsub -1
        set counts {}

        for {set i [llength $channels]} {$i > 0} {incr i -1} {
            set msg [$client read]
            assert_equal $type [lindex $msg 0]

            # when receiving subscribe messages the channels names
            # are ordered. when receiving unsubscribe messages
            # they are unordered
            set idx [lsearch -exact $channels [lindex $msg 1]]
            if {[string match "*unsubscribe" $type]} {
                assert {$idx >= 0}
            } else {
                assert {$idx == 0}
            }
            set channels [lreplace $channels $idx $idx]

            # aggregate the subscription count to return to the caller
            lappend counts [lindex $msg 2]
        }

        # we should have received messages for channels
        assert {[llength $channels] == 0}
        return $counts
    }

    proc subscribe {client channels} {
        $client subscribe {*}$channels
        __consume_subscribe_messages $client subscribe $channels
    }

    proc unsubscribe {client {channels {}}} {
        $client unsubscribe {*}$channels
        __consume_subscribe_messages $client unsubscribe $channels
    }

    proc psubscribe {client channels} {
        $client psubscribe {*}$channels
        __consume_subscribe_messages $client psubscribe $channels
    }

    proc punsubscribe {client {channels {}}} {
        $client punsubscribe {*}$channels
        __consume_subscribe_messages $client punsubscribe $channels
    }

    test "Pub/Sub PING" {
        set rd1 [redis_deferring_client]
        puts $rd1
        subscribe $rd1 somechannel
        # While subscribed to non-zero channels PING works in Pub/Sub mode.
        $rd1 ping
        $rd1 ping "foo"
        set reply1 [$rd1 read]
        set reply2 [$rd1 read]
        unsubscribe $rd1 somechannel
        # Now we are unsubscribed, PING should just return PONG.
        $rd1 ping
        set reply3 [$rd1 read]
        $rd1 close
        list $reply1 $reply2 $reply3
    } {{pong {}} {pong foo} PONG}

    test "PUBLISH/SUBSCRIBE basics" {
        set rd1 [redis_deferring_client]

        # subscribe to two channels
        assert_equal {1 2} [subscribe $rd1 {chan1 chan2}]
        assert_equal 1 [r publish chan1 hello]
        assert_equal 1 [r publish chan2 world]
        assert_equal {message chan1 hello} [$rd1 read]
        assert_equal {message chan2 world} [$rd1 read]

        # unsubscribe from one of the channels
        unsubscribe $rd1 {chan1}
        assert_equal 0 [r publish chan1 hello]
        assert_equal 1 [r publish chan2 world]
        assert_equal {message chan2 world} [$rd1 read]

        # unsubscribe from the remaining channel
        unsubscribe $rd1 {chan2}
        assert_equal 0 [r publish chan1 hello]
        assert_equal 0 [r publish chan2 world]

        # clean up clients
        $rd1 close
    }

    test "PUBLISH/SUBSCRIBE with two clients" {
        set rd1 [redis_deferring_client]
        set rd2 [redis_deferring_client]

        assert_equal {1} [subscribe $rd1 {chan1}]
        assert_equal {1} [subscribe $rd2 {chan1}]
        assert_equal 2 [r publish chan1 hello]
        assert_equal {message chan1 hello} [$rd1 read]
        assert_equal {message chan1 hello} [$rd2 read]

        # clean up clients
        $rd1 close
        $rd2 close
    }

    test "PUBLISH/SUBSCRIBE after UNSUBSCRIBE without arguments" {
        set rd1 [redis_deferring_client]
        assert_equal {1 2 3} [subscribe $rd1 {chan1 chan2 chan3}]
        unsubscribe $rd1
        assert_equal 0 [r publish chan1 hello]
        assert_equal 0 [r publish chan2 hello]
        assert_equal 0 [r publish chan3 hello]

        # clean up clients
        $rd1 close
    }

    test "SUBSCRIBE to one channel more than once" {
        set rd1 [redis_deferring_client]
        assert_equal {1 1 1} [subscribe $rd1 {chan1 chan1 chan1}]
        assert_equal 1 [r publish chan1 hello]
        assert_equal {message chan1 hello} [$rd1 read]

        # clean up clients
        $rd1 close
    }

    test "UNSUBSCRIBE from non-subscribed channels" {
        set rd1 [redis_deferring_client]
        assert_equal {0 0 0} [unsubscribe $rd1 {foo bar quux}]

        # clean up clients
        $rd1 close
    }

    test "PUBLISH/PSUBSCRIBE basics" {
        set rd1 [redis_deferring_client]

        # subscribe to two patterns
        assert_equal {1 2} [psubscribe $rd1 {foo.* bar.*}]
        assert_equal 1 [r publish foo.1 hello]
        assert_equal 1 [r publish bar.1 hello]
        assert_equal 0 [r publish foo1 hello]
        assert_equal 0 [r publish barfoo.1 hello]
        assert_equal 0 [r publish qux.1 hello]
        assert_equal {pmessage foo.* foo.1 hello} [$rd1 read]
        assert_equal {pmessage bar.* bar.1 hello} [$rd1 read]

        # unsubscribe from one of the patterns
        assert_equal {1} [punsubscribe $rd1 {foo.*}]
        assert_equal 0 [r publish foo.1 hello]
        assert_equal 1 [r publish bar.1 hello]
        assert_equal {pmessage bar.* bar.1 hello} [$rd1 read]

        # unsubscribe from the remaining pattern
        assert_equal {0} [punsubscribe $rd1 {bar.*}]
        assert_equal 0 [r publish foo.1 hello]
        assert_equal 0 [r publish bar.1 hello]

        # clean up clients
        $rd1 close
    }

    test "PUBLISH/PSUBSCRIBE with two clients" {
        set rd1 [redis_deferring_client]
        set rd2 [redis_deferring_client]

        assert_equal {1} [psubscribe $rd1 {chan.*}]
        assert_equal {1} [psubscribe $rd2 {chan.*}]
        assert_equal 2 [r publish chan.foo hello]
        assert_equal {pmessage chan.* chan.foo hello} [$rd1 read]
        assert_equal {pmessage chan.* chan.foo hello} [$rd2 read]

        # clean up clients
        $rd1 close
        $rd2 close
    }

    test "PUBLISH/PSUBSCRIBE after PUNSUBSCRIBE without arguments" {
        set rd1 [redis_deferring_client]
        assert_equal {1 2 3} [psubscribe $rd1 {chan1.* chan2.* chan3.*}]
        punsubscribe $rd1
        assert_equal 0 [r publish chan1.hi hello]
        assert_equal 0 [r publish chan2.hi hello]
        assert_equal 0 [r publish chan3.hi hello]

        # clean up clients
        $rd1 close
    }

    test "PUNSUBSCRIBE from non-subscribed channels" {
        set rd1 [redis_deferring_client]
        assert_equal {0 0 0} [punsubscribe $rd1 {foo.* bar.* quux.*}]

        # clean up clients
        $rd1 close
    }

    test "NUMSUB returns numbers, not strings (#1561)" {
        r pubsub numsub abc def
    } {abc 0 def 0}

    test "Mix SUBSCRIBE and PSUBSCRIBE" {
        set rd1 [redis_deferring_client]
        assert_equal {1} [subscribe $rd1 {foo.bar}]
        assert_equal {2} [psubscribe $rd1 {foo.*}]

        assert_equal 2 [r publish foo.bar hello]
        assert_equal {message foo.bar hello} [$rd1 read]
        assert_equal {pmessage foo.* foo.bar hello} [$rd1 read]

        # clean up clients
        $rd1 close
    }

    test "PUNSUBSCRIBE and UNSUBSCRIBE should always reply" {
        # Make sure we are not subscribed to any channel at all.
        r punsubscribe
        r unsubscribe
        # Now check if the commands still reply correctly.
        set reply1 [r punsubscribe]
        set reply2 [r unsubscribe]
        concat $reply1 $reply2
    } {punsubscribe {} 0 unsubscribe {} 0}

    ### Keyspace events notification tests

    test "Keyspace notifications: we receive keyspace notifications" {
        r config set notify-keyspace-events KA
        set rd1 [redis_deferring_client]
        assert_equal {1} [psubscribe $rd1 *]
        r set foo bar
        assert_equal {pmessage * __keyspace@9__:foo set} [$rd1 read]
        $rd1 close
    }

    test "Keyspace notifications: we receive keyevent notifications" {
        r config set notify-keyspace-events EA
        set rd1 [redis_deferring_client]
        assert_equal {1} [psubscribe $rd1 *]
        r set foo bar
        assert_equal {pmessage * __keyevent@9__:set foo} [$rd1 read]
        $rd1 close
    }

    test "Keyspace notifications: we can receive both kind of events" {
        r config set notify-keyspace-events KEAg
        set rd1 [redis_deferring_client]
        assert_equal {1} [psubscribe $rd1 *]
        r set foo bar
        assert_equal {pmessage * __keyspace@9__:foo set} [$rd1 read]
        assert_equal {pmessage * __keyevent@9__:set foo} [$rd1 read]

        r del foo 
        assert_equal {pmessage * __keyspace@9__:foo del}  [$rd1 read]
        assert_equal {pmessage * __keyevent@9__:del foo}  [$rd1 read]

        r crdt.set foo bar 1 1000 "1:1" 
        assert_equal {pmessage * __keyspace@9__:foo set} [$rd1 read]
        assert_equal {pmessage * __keyevent@9__:set foo} [$rd1 read]

        r CRDT.DEL_REG foo 1 1000 "1:2" 
        assert_equal {pmessage * __keyspace@9__:foo del}  [$rd1 read]
        assert_equal {pmessage * __keyevent@9__:del foo}  [$rd1 read]

        $rd1 close
    }

    test "Keyspace notifications: crdt.set and crdt.del_reg" {
        r config set notify-keyspace-events KEAg
        set rd1 [redis_deferring_client]
        assert_equal {1} [psubscribe $rd1 *]
        
        $rd1 close
    }

    # test "Keyspace notifications: we are able to mask events" {
    #     r config set notify-keyspace-events KEl
    #     r del mylist
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r set foo bar
    #     r lpush mylist a
    #     # No notification for set, because only list commands are enabled.
    #     assert_equal {pmessage * __keyspace@9__:mylist lpush} [$rd1 read]
    #     assert_equal {pmessage * __keyevent@9__:lpush mylist} [$rd1 read]
    #     $rd1 close
    # }

    # test "Keyspace notifications: general events test" {
    #     r config set notify-keyspace-events KEg
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r set foo bar
    #     r expire foo 1
    #     r del foo
    #     assert_equal {pmessage * __keyspace@9__:foo expire} [$rd1 read]
    #     assert_equal {pmessage * __keyevent@9__:expire foo} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:foo del} [$rd1 read]
    #     assert_equal {pmessage * __keyevent@9__:del foo} [$rd1 read]
    #     $rd1 close
    # }

    # test "Keyspace notifications: list events test" {
    #     r config set notify-keyspace-events KEl
    #     r del mylist
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r lpush mylist a
    #     r rpush mylist a
    #     r rpop mylist
    #     assert_equal {pmessage * __keyspace@9__:mylist lpush} [$rd1 read]
    #     assert_equal {pmessage * __keyevent@9__:lpush mylist} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:mylist rpush} [$rd1 read]
    #     assert_equal {pmessage * __keyevent@9__:rpush mylist} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:mylist rpop} [$rd1 read]
    #     assert_equal {pmessage * __keyevent@9__:rpop mylist} [$rd1 read]
    #     $rd1 close
    # }

    # test "Keyspace notifications: set events test" {
    #     r config set notify-keyspace-events Ks
    #     r del myset
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r sadd myset a b c d
    #     r srem myset x
    #     r sadd myset x y z
    #     r srem myset x
    #     assert_equal {pmessage * __keyspace@9__:myset sadd} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:myset sadd} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:myset srem} [$rd1 read]
    #     $rd1 close
    # }

    # test "Keyspace notifications: zset events test" {
    #     r config set notify-keyspace-events Kz
    #     r del myzset
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r zadd myzset 1 a 2 b
    #     r zrem myzset x
    #     r zadd myzset 3 x 4 y 5 z
    #     r zrem myzset x
    #     assert_equal {pmessage * __keyspace@9__:myzset zadd} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:myzset zadd} [$rd1 read]
    #     assert_equal {pmessage * __keyspace@9__:myzset zrem} [$rd1 read]
    #     $rd1 close
    # }

    test "Keyspace notifications: hash events test" {
        r config set notify-keyspace-events Khg
        r del myhash
        set rd1 [redis_deferring_client]
        assert_equal {1} [psubscribe $rd1 *]
        r hmset myhash yes 1 no 0
        assert_equal {pmessage * __keyspace@9__:myhash hset} [$rd1 read]
        r del myhash
        assert_equal {pmessage * __keyspace@9__:myhash del} [$rd1 read]
        r crdt.hset myhash 1 1000 "1:10" 2 yes 1 no 0
        assert_equal {pmessage * __keyspace@9__:myhash hset} [$rd1 read]
        r crdt.del_hash myhash 1 1000 "1:11"
        assert_equal {pmessage * __keyspace@9__:myhash del} [$rd1 read]
        $rd1 close
    }

    # test "Keyspace notifications: expired events (triggered expire)" {
    #     r config set notify-keyspace-events Ex
    #     r del foo
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r psetex foo 100 1
    #     wait_for_condition 50 100 {
    #         [r exists foo] == 0
    #     } else {
    #         fail "Key does not expire?!"
    #     }
    #     assert_equal {pmessage * __keyevent@9__:expired foo} [$rd1 read]
    #     $rd1 close
    # }

    # test "Keyspace notifications: expired events (background expire)" {
    #     r config set notify-keyspace-events Ex
    #     r del foo
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r psetex foo 100 1
    #     assert_equal {pmessage * __keyevent@9__:expired foo} [$rd1 read]
    #     $rd1 close
    # }

    # test "Keyspace notifications: evicted events" {
    #     r config set notify-keyspace-events Ee
    #     r config set maxmemory-policy allkeys-lru
    #     r flushdb
    #     set rd1 [redis_deferring_client]
    #     assert_equal {1} [psubscribe $rd1 *]
    #     r set foo bar
    #     r config set maxmemory 1
    #     assert_equal {pmessage * __keyevent@9__:evicted foo} [$rd1 read]
    #     r config set maxmemory 0
    #     $rd1 close
    # }

    test "Keyspace notifications: test CONFIG GET/SET of event flags" {
        r config set notify-keyspace-events gKE
        assert_equal {gKE} [lindex [r config get notify-keyspace-events] 1]
        r config set notify-keyspace-events {$lshzxeKE}
        assert_equal {$lshzxeKE} [lindex [r config get notify-keyspace-events] 1]
        r config set notify-keyspace-events KA
        assert_equal {AK} [lindex [r config get notify-keyspace-events] 1]
        r config set notify-keyspace-events EA
        assert_equal {AE} [lindex [r config get notify-keyspace-events] 1]
    }
}
proc wait { client index type}  {
    set retry 50
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        error "assertion: Master-Slave not correctly synchronized"
    }
}
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set peer_stdouts {}
    set rd {}
    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_stdouts [srv 0 stdout]
    lappend peer_gids 1
    lappend rd [redis_deferring_client]
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2 repl-diskless-sync-delay 1} module {crdt.so} } {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_stdouts [srv 0 stdout]
        lappend peer_gids 2
        lappend rd [redis_deferring_client]
        [lindex $peers 1] config crdt.set repl-diskless-sync-delay 1
        [lindex $peers 1] config set repl-diskless-sync-delay 1
        
        test "peerof" {
            [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
            [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
            wait [lindex $peers 0] 0 crdt.info 
            wait [lindex $peers 1] 0 crdt.info
        }

        test "after peerof set" {
            [lindex $peers 0] config set notify-keyspace-events KEA
            [lindex $peers 1] config set notify-keyspace-events KEA
            assert_equal {1} [psubscribe [lindex $rd 1] *]
            [lindex $peers 0] set foo bar
            assert_equal {pmessage * __keyspace@9__:foo set} [[lindex $rd 1] read]
            assert_equal {pmessage * __keyevent@9__:set foo} [[lindex $rd 1] read]
            punsubscribe [lindex $rd 1] *
        }

        test "after peerof hash" {
            [lindex $peers 0] config set notify-keyspace-events Kh
            [lindex $peers 1] config set notify-keyspace-events Kh
            [lindex $peers 0] del myhash
            assert_equal {1} [psubscribe [lindex $rd 1] *]
            [lindex $peers 0] hmset myhash yes 1 no 0
            # r hincrby myhash yes 10
            assert_equal {pmessage * __keyspace@9__:myhash hset} [[lindex $rd 1] read]
            # assert_equal {pmessage * __keyspace@9__:myhash hincrby} [$rd1 read]
            punsubscribe [lindex $rd 1] *
        }
    }
}