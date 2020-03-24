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
start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1} module {crdt.so}} {
    proc __consume_crdt_subscribe_messages {client type channels} {
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

    proc crdtsubscribe {client channels} {
        $client crdt.subscribe {*}$channels
        __consume_crdt_subscribe_messages $client crdtsubscribe $channels
    }

    proc crdtunsubscribe {client {channels {}}} {
        $client crdt.unsubscribe {*}$channels
        __consume_crdt_subscribe_messages $client crdtunsubscribe $channels
    }

    proc crdtpsubscribe {client channels} {
        $client crdt.psubscribe {*}$channels
        __consume_crdt_subscribe_messages $client crdtpsubscribe $channels
    }

    proc crdtpunsubscribe {client {channels {}}} {
        $client crdt.punsubscribe {*}$channels
        __consume_crdt_subscribe_messages $client crdtpunsubscribe $channels
    }

    test "Pub/Sub PING" {
        set rd1 [redis_deferring_client]
        puts $rd1
        crdtsubscribe $rd1 somechannel
        # While subscribed to non-zero channels PING works in Pub/Sub mode.
        $rd1 ping
        $rd1 ping "foo"
        set reply1 [$rd1 read]
        set reply2 [$rd1 read]
        crdtunsubscribe $rd1 somechannel
        # Now we are unsubscribed, PING should just return PONG.
        $rd1 ping
        set reply3 [$rd1 read]
        $rd1 close
        list $reply1 $reply2 $reply3
    } {{pong {}} {pong foo} PONG}

    test "PUBLISH/SUBSCRIBE basics" {
        set rd1 [redis_deferring_client]

        # subscribe to two channels
        assert_equal {1 2} [crdtsubscribe $rd1 {chan1 chan2}]
        assert_equal 1 [r crdtpublish chan1 hello]
        assert_equal 1 [r crdtpublish chan2 world]
        assert_equal {message chan1 hello} [$rd1 read]
        assert_equal {message chan2 world} [$rd1 read]

        # unsubscribe from one of the channels
        crdtunsubscribe $rd1 {chan1}
        assert_equal 0 [r crdtpublish chan1 hello]
        assert_equal 1 [r crdtpublish chan2 world]
        assert_equal {message chan2 world} [$rd1 read]

        # unsubscribe from the remaining channel
        crdtunsubscribe $rd1 {chan2}
        assert_equal 0 [r crdtpublish chan1 hello]
        assert_equal 0 [r crdtpublish chan2 world]

        # clean up clients
        $rd1 close
    }
    test "PUBLISH/SUBSCRIBE with two clients" {
        set rd1 [redis_deferring_client]
        set rd2 [redis_deferring_client]

        assert_equal {1} [crdtsubscribe $rd1 {chan1}]
        assert_equal {1} [crdtsubscribe $rd2 {chan1}]
        assert_equal 2 [r crdtpublish chan1 hello]
        assert_equal {message chan1 hello} [$rd1 read]
        assert_equal {message chan1 hello} [$rd2 read]

        # clean up clients
        $rd1 close
        $rd2 close
    }

    test "PUBLISH/SUBSCRIBE after UNSUBSCRIBE without arguments" {
        set rd1 [redis_deferring_client]
        assert_equal {1 2 3} [crdtsubscribe $rd1 {chan1 chan2 chan3}]
        crdtunsubscribe $rd1
        assert_equal 0 [r crdtpublish chan1 hello]
        assert_equal 0 [r crdtpublish chan2 hello]
        assert_equal 0 [r crdtpublish chan3 hello]

        # clean up clients
        $rd1 close
    }

    test "SUBSCRIBE to one channel more than once" {
        set rd1 [redis_deferring_client]
        assert_equal {1 1 1} [crdtsubscribe $rd1 {chan1 chan1 chan1}]
        assert_equal 1 [r crdtpublish chan1 hello]
        assert_equal {message chan1 hello} [$rd1 read]

        # clean up clients
        $rd1 close
    }

    test "UNSUBSCRIBE from non-subscribed channels" {
        set rd1 [redis_deferring_client]
        assert_equal {0 0 0} [crdtunsubscribe $rd1 {foo bar quux}]

        # clean up clients
        $rd1 close
    }

    test "PUBLISH/PSUBSCRIBE basics" {
        set rd1 [redis_deferring_client]

        # subscribe to two patterns
        assert_equal {1 2} [crdtpsubscribe $rd1 {foo.* bar.*}]
        assert_equal 1 [r crdtpublish foo.1 hello]
        assert_equal 1 [r crdtpublish bar.1 hello]
        assert_equal 0 [r crdtpublish foo1 hello]
        assert_equal 0 [r crdtpublish barfoo.1 hello]
        assert_equal 0 [r crdtpublish qux.1 hello]
        assert_equal {pmessage foo.* foo.1 hello} [$rd1 read]
        assert_equal {pmessage bar.* bar.1 hello} [$rd1 read]

        # # unsubscribe from one of the patterns
        assert_equal {1} [crdtpunsubscribe $rd1 {foo.*}]
        assert_equal 0 [r crdtpublish foo.1 hello]
        assert_equal 1 [r crdtpublish bar.1 hello]
        assert_equal {pmessage bar.* bar.1 hello} [$rd1 read]

        # unsubscribe from the remaining pattern
        assert_equal {0} [crdtpunsubscribe $rd1 {bar.*}]
        assert_equal 0 [r crdtpublish foo.1 hello]
        assert_equal 0 [r crdtpublish bar.1 hello]

        # clean up clients
        $rd1 close
    }

    test "PUBLISH/PSUBSCRIBE with two clients" {
        set rd1 [redis_deferring_client]
        set rd2 [redis_deferring_client]

        assert_equal {1} [crdtpsubscribe $rd1 {chan.*}]
        assert_equal {1} [crdtpsubscribe $rd2 {chan.*}]
        assert_equal 2 [r crdtpublish chan.foo hello]
        assert_equal {pmessage chan.* chan.foo hello} [$rd1 read]
        assert_equal {pmessage chan.* chan.foo hello} [$rd2 read]

        # clean up clients
        $rd1 close
        $rd2 close
    }

    test "PUBLISH/PSUBSCRIBE after PUNSUBSCRIBE without arguments" {
        set rd1 [redis_deferring_client]
        assert_equal {1 2 3} [crdtpsubscribe $rd1 {chan1.* chan2.* chan3.*}]
        crdtpunsubscribe $rd1
        assert_equal 0 [r crdtpublish chan1.hi hello]
        assert_equal 0 [r crdtpublish chan2.hi hello]
        assert_equal 0 [r crdtpublish chan3.hi hello]

        # clean up clients
        $rd1 close
    }

    test "PUNSUBSCRIBE from non-subscribed channels" {
        set rd1 [redis_deferring_client]
        assert_equal {0 0 0} [crdtpunsubscribe $rd1 {foo.* bar.* quux.*}]

        # clean up clients
        $rd1 close
    }

    test "NUMSUB returns numbers, not strings (#1561)" {
        r crdt.pubsub numsub abc def
    } {abc 0 def 0}

    test "Mix SUBSCRIBE and PSUBSCRIBE" {
        set rd1 [redis_deferring_client]
        assert_equal {1} [crdtsubscribe $rd1 {foo.bar}]
        assert_equal {2} [crdtpsubscribe $rd1 {foo.*}]

        assert_equal 2 [r crdtpublish foo.bar hello]
        assert_equal {message foo.bar hello} [$rd1 read]
        assert_equal {pmessage foo.* foo.bar hello} [$rd1 read]

        # clean up clients
        $rd1 close
    }

    test "PUNSUBSCRIBE and UNSUBSCRIBE should always reply" {
        # Make sure we are not subscribed to any channel at all.
        r crdt.punsubscribe
        r crdt.unsubscribe
        # Now check if the commands still reply correctly.
        set reply1 [r crdt.punsubscribe]
        set reply2 [r crdt.unsubscribe]
        concat $reply1 $reply2
    } {crdtpunsubscribe {} 0 crdtunsubscribe {} 0}

    

    set peers {}
    set peer_hosts {}
    set peer_ports {}
    set peer_gids  {}
    set rd {}

    lappend peers [srv 0 client]
    lappend peer_hosts [srv 0 host]
    lappend peer_ports [srv 0 port]
    lappend peer_gids  1
    lappend rd [redis_deferring_client]
    [lindex $peers 0] config crdt.set repl-diskless-sync-delay 1
    [lindex $peers 0] config set repl-diskless-sync-delay 1
    start_server {config {crdt.conf} overrides {crdt-gid 2} module {crdt.so}} {
        lappend peers [srv 0 client]
        lappend peer_hosts [srv 0 host]
        lappend peer_ports [srv 0 port]
        lappend peer_gids  2
        lappend rd [redis_deferring_client]
         [lindex $peers 1] peerof [lindex $peer_gids 0] [lindex $peer_hosts 0] [lindex $peer_ports 0]
        [lindex $peers 0] peerof [lindex $peer_gids 1] [lindex $peer_hosts 1] [lindex $peer_ports 1]
        wait [lindex $peers 0] 0 crdt.info 
        wait [lindex $peers 1] 0 crdt.info
        test "peer sub" {
            assert_equal {1} [crdtsubscribe [lindex $rd 1] test]
            [lindex $peers 0] crdtPUBLISH test foo
            assert_equal {message test foo} [[lindex $rd 1] read]
            crdtunsubscribe [lindex $rd 1] test
        }
        test "peer psub" {
            assert_equal {1} [crdtpsubscribe [lindex $rd 1] test.*]
            [lindex $peers 0] crdtPUBLISH test.1 foo
            assert_equal {pmessage test.* test.1 foo} [[lindex $rd 1] read]
            crdtpunsubscribe [lindex $rd 1] test
        }

    }

    
}