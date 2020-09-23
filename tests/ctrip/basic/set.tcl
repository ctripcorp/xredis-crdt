start_server {
    tags {"set"}
    overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
} {
    proc create_set {key entries} {
        r del $key
        foreach entry $entries { r sadd $key $entry }
    }

    test {SADD, SCARD, SISMEMBER, SMEMBERS basics - regular set} {
        create_set myset {foo}
        assert_equal 1 [r sadd myset bar]
        assert_equal 0 [r sadd myset bar]
        assert_equal 2 [r scard myset]
        assert_equal 1 [r sismember myset foo]
        assert_equal 1 [r sismember myset bar]
        assert_equal 0 [r sismember myset bla]
        assert_equal {bar foo} [lsort [r smembers myset]]
    }

    test {SADD, SCARD, SISMEMBER, SMEMBERS basics - intset} {
        create_set myset {17}
        assert_equal 1 [r sadd myset 16]
        assert_equal 0 [r sadd myset 16]
        assert_equal 2 [r scard myset]
        assert_equal 1 [r sismember myset 16]
        assert_equal 1 [r sismember myset 17]
        assert_equal 0 [r sismember myset 18]
        assert_equal {16 17} [lsort [r smembers myset]]
    }

    test {SADD against non set} {
        r set mylist foo
        assert_error WRONGTYPE* {r sadd mylist bar}
    }

    test {Variadic SADD} {
        r del myset
        assert_equal 3 [r sadd myset a b c]
        assert_equal 2 [r sadd myset A a b c B]
        assert_equal [lsort {A a b c B}] [lsort [r smembers myset]]
    }

    test {SREM basics - regular set} {
        create_set myset {foo bar ciao}
        assert_equal 0 [r srem myset qux]
        assert_equal 1 [r srem myset foo]
        assert_equal {bar ciao} [lsort [r smembers myset]]
    }

    test {SREM basics - intset} {
        create_set myset {3 4 5}
        assert_equal 0 [r srem myset 6]
        assert_equal 1 [r srem myset 4]
        assert_equal {3 5} [lsort [r smembers myset]]
    }

    test {SREM with multiple arguments} {
        r del myset
        r sadd myset a b c d
        assert_equal 0 [r srem myset k k k]
        assert_equal 2 [r srem myset b d x y]
        lsort [r smembers myset]
    } {a c}

    test {SREM variadic version with more args needed to destroy the key} {
        r del myset
        r sadd myset 1 2 3
        r srem myset 1 2 3 4 5 6 7 8
    } {3}


    for {set i 1} {$i <= 5} {incr i} {
        r del [format "set%d" $i]
    }
    for {set i 0} {$i < 200} {incr i} {
        r sadd set1 $i
        r sadd set2 [expr $i+195]
    }
    foreach i {199 195 1000 2000} {
        r sadd set3 $i
    }
    for {set i 5} {$i < 200} {incr i} {
        r sadd set4 $i
    }
    r sadd set5 0

    set large "jlksdajfasndfkhsadifuasojfasmglskadjgksahuorsanvasdg"
    for {set i 1} {$i <= 5} {incr i} {
        r sadd [format "set%d" $i] $large
    }

    test "SUNION with two sets" {
        set expected [lsort -uniq "[r smembers set1] [r smembers set2]"]
        assert_equal $expected [lsort [r sunion set1 set2]]
    }

    test "SUNION with non existing keys" {
        set expected [lsort -uniq "[r smembers set1] [r smembers set2]"]
        assert_equal $expected [lsort [r sunion nokey1 set1 set2 nokey2]]
    }



    test "SUNION against non-set should throw error" {
        r set key1 x
        assert_error "WRONGTYPE*" {r sunion key1 noset}
    }
}