start_server {tags {"crdt-command"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    test "set-command" {
        test "set k v" {
            r set k v
        } {OK}
        test "set k" {
            set _ [catch {
                r set k
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'set' command"
        } 
        test "set k v ex 1000" {
            r set k v ex 1000
        } {OK}
        test "set k v nx 1000" {
            set _ [catch {
                r set k v nx 1000 
            } retval]
            assert_equal $retval "ERR syntax error"
        }
        test "set px v px 123321" {
            r set px v px 123321 
        } {OK}
        test "set px v px" {
            set _ [catch {
                r set px v px
            } retval]
            assert_equal $retval "ERR syntax error"
        } 
        test "SET not-exists-key 'value' NX" {
            r SET not-exists-key "value" NX
        } {OK}
        test "SET not-exists-key 'new-value' NX" {
            r SET not-exists-key "new-value" NX
        } {}
        test "SET key-with-expire-and-NX 'hello' EX 10086 NX" {
            r SET key-with-expire-and-NX "hello" EX 10086 NX
        } {OK}
        test "SET key-with-pexpire-and-XX 'new value' PX 123321" {
            r SET key-with-pexpire-and-XX "new value" PX 123321
        } {OK}
        test "SET key 'value' EX 1000 PX 5000000" {
            set _ [catch {
                r SET key "value" EX 1000 PX 5000000 
            } retval]
            assert_equal $retval "ERR syntax error"
        }
    }
    test "get-command" {
        test "get" {    
            r set k v 
            r get k
        } {v}
        test "get k1" {
            r get k1
        } {}
        test "get h" {
            r hset h k v 
            set _ [catch {
                r get h
            } retval]
            assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
        }
    }
    test "mset" {
        test {MSET date "2012.3.30" time "11:00 a.m." weather "sunny"} {
            r MSET date "2012.3.30" time "11:00 a.m." weather "sunny"
        } {OK}
    }
    test "mget" {
        test {MGET date time weather} {
            r MGET date time weather
        } {2012.3.30 {11:00 a.m.} sunny}
        test {MGET date} {
            r MGET date
        } {2012.3.30}
        test {MGet a} {
            r MGet a
        } {{}}
        test {MGet a b c} {
            r MGet a b c
        } {{} {} {}}
        test {MGet} {
            set _ [catch {
                r mget
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'mget' command"
        }
    }
    test "hset" {
        test {HSET website google "www.g.cn"} {
            r hset website google "www.g.cn"
        } {1}
        test {hset a b c d e} {
            r hset a b c d e
        } {2}
        test {HSET website google "www.google.com"} {
            r HSET website google "www.google.com"
        } {0}
        test {HSET website google "www.g.cn" a} {
            set _ [catch {
                r HSET website google "www.g.cn" a
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'HSET' command"
        }
    }
    test "hdel" {
        test {hdel a b } {
            r del a
            r hset a b c
            r hdel a b
        } {1}
        test {second hdel b c} {
            r del b
            r hdel b c 
        } {0}
        test {hdel a} {
            set _ [catch {
                r hdel a
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'hdel' command"
        }
    }
    test "hgetall" {
        test "hgetall a" {
            r hset a b c d e 
            lsort [r hgetall a]
        } [lsort {b c d e}]
        test "hgetall b" {
            r hgetall b
        } {}
        test "hgetall c a" {
            set _ [catch {
                r hgetall c a
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'hgetall' command"
        } 
    }
    test "hkeys" {
        test "hkeys a" {
            r hset a b c d e 
            lsort [r hkeys a]
        } [lsort {b d}]
        test "hkeys b" {
            r hkeys b
        } {}
        test "hkeys c a" {
            set _ [catch {
                r hkeys c a
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'hkeys' command"
        } 
    }
    test "hvals" {
        test "hvals a" {
            r hset a b c d e 
            lsort [r hvals a]
        } [lsort {c e}]
        test "hvals b" {
            r hvals b
        } {}
        test "hvals c a" {
            set _ [catch {
                r hvals c a
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'hvals' command"
        } 
    }
    test "hmset" {
        test "hmset a b c d e" {
            r hmset a b c d e
        } {OK}
        test "hmset a " {
            r del a 
            r set a b
            set _ [catch {
                r hmset a b c d e
            } retval]
            assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
        } 
        test "hmset a" {
            set _ [catch {
                r hmset a
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'hmset' command"
        }
    }
    test "hmget" {
        test "hmget a b d" {
            r del a 
            r hmset a b c d e 
            r hmget a b d
        } {c e}
        test "hmget b c d" {
            r del b 
            r hmget b c d 
        } {{} {}}
        test "hmget" {
            set _ [catch {
                r hmget 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'hmget' command"
        }
    }
    test "del" {
        test "del k" {
            r del k
            r set k v 
            r del k
        } {1}
        test "del h" {
            r del h
            r hset h k v
            r del h
        } {1}
        test "del nil" {
            r del a 
            r del a 
        } {0}
        test "del" {
            set _ [catch {
                r del 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'del' command"
        }
    }
    test "expire" {
        test {expire k 1000} {
            r set k v
            r expire k 1000
        } {1}
        test {expire k -1} {
            r del k 
            r set k v
            r expire k -1 
        } {1}
        test {expire a 1000} {
            r del a 
            r expire a 1000
        } {0}
        test "expire" {
            set _ [catch {
                r expire 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'expire' command"
        }
    }
    test "persist-command" {
        test "persist k" {
            r set k v ex 1000
            r persist k
        } {1}
        test "persist k" {
            r del k 
            r persist k
        } {0}
        test "persist" {
            set _ [catch {
                r persist 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'persist' command"
        }
    }
    test "setex-command" {
        test "setex a 60 c" {
            r set a b 
            r setex a 60 c
        } {OK}
        test "setex cache_user_id 60 10086" {
            r setex cache_user_id 60 10086
        } {OK}
        test "setex a " {
            r del a 
            r hset a b c
            set _ [catch {
                r setex a 60 b
            } retval]
            assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
        }
        test "setex " {
            set _ [catch {
                r setex 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'setex' command"
        }
    }
    test "sadd-command" {
        test "sadd myset s1 s2" {
            r sadd myset s1 s2
        } {2}
        test "sadd myset - repeat" {
            r sadd myset s1 
        } {0}
        test "sadd" {
            set _ [catch {
                r sadd 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'sadd' command"
        }
    }
    test "srem-command" {
        test "srem myset1 s1 s2" {
            r srem myset1 s1 s2
        } {0}
        test "srem myset1 s1 s2" {
            r sadd myset1 s1 s2
            r srem myset1 s1 s2 s3
        } {2}
        test "srem myset1" {
            set _ [catch {
                r srem 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'srem' command"
        } 
    }
    test "spop-command" {
        test "spop myset2 => nil" {
            r spop myset2 
        } {}
        test "spop myset2 => s1" {
            r sadd myset2 s1
            r spop myset2 
        } {s1}
        test "spop myset2 2 => 1, 2" {
            r sadd myset2 s1 s2
            lsort [r spop myset2 2]
        } [lsort {s1 s2}]
        test "spop myset1" {
            set _ [catch {
                r spop 
            } retval]
            assert_equal $retval "ERR wrong number of arguments for 'spop' command"
        } 
    }
}