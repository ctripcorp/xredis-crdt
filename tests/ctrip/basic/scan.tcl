start_server {tags {"scan"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
    test "SCAN basic" {
        r flushdb
        r debug populate 1000

        set cur 0
        set keys {}
        while 1 {
            set res [r scan $cur]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
        }

        set keys [lsort -unique $keys]
        assert_equal 1000 [llength $keys]
    }

    test "SCAN COUNT" {
        r flushdb
        r debug populate 1000

        set cur 0
        set keys {}
        while 1 {
            set res [r scan $cur count 5]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
        }

        set keys [lsort -unique $keys]
        assert_equal 1000 [llength $keys]
    }

    test "SCAN MATCH" {
        r flushdb
        r debug populate 1000

        set cur 0
        set keys {}
        while 1 {
            set res [r scan $cur match "key:1??"]
            set cur [lindex $res 0]
            set k [lindex $res 1]
            lappend keys {*}$k
            if {$cur == 0} break
        }

        set keys [lsort -unique $keys]
        assert_equal 100 [llength $keys]
    }

    foreach enc {hashtable} {
        test "SSCAN with encoding $enc" {
            # Create the Set
            r del set
            if {$enc eq {intset}} {
                set prefix ""
            } else {
                set prefix "ele:"
            }
            set elements {}
            for {set j 0} {$j < 100} {incr j} {
                lappend elements ${prefix}${j}
            }
            r sadd set {*}$elements

            # Test SSCAN
            set cur 0
            set keys {}
            while 1 {
                set res [r sscan set $cur]
                set cur [lindex $res 0]
                set k [lindex $res 1]
                lappend keys {*}$k
                if {$cur == 0} break
            }

            set keys [lsort -unique $keys]
            assert_equal 100 [llength $keys]
        }
    }

    test "SSCAN with integer encoded object (issue #1345)" {
        set objects {1 a}
        r del set
        r sadd set {*}$objects
        set res [r sscan set 0 MATCH *a* COUNT 100]
        assert_equal [lsort -unique [lindex $res 1]] {a}
        set res [r sscan set 0 MATCH *1* COUNT 100]
        assert_equal [lsort -unique [lindex $res 1]] {1}
    }

    test "SSCAN with PATTERN" {
        r del mykey
        r sadd mykey foo fab fiz foobar 1 2 3 4
        set res [r sscan mykey 0 MATCH foo* COUNT 10000]
        lsort -unique [lindex $res 1]
    } {foo foobar}

}
