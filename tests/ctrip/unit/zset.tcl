proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
start_server {tags {"zset"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    set r_log [srv 0 stdout]
    r crdt.debug_gc zset 0
    proc create_zset {key items} {
        r del $key
        foreach {score entry} $items {
            r zadd $key $score $entry
        }
    }

    proc basics {encoding} {
        if {$encoding == "ziplist"} {
            r config set zset-max-ziplist-entries 128
            r config set zset-max-ziplist-value 64
        } elseif {$encoding == "skiplist"} {
            #crdt only skiplist now
            r config set zset-max-ziplist-entries 0
            r config set zset-max-ziplist-value 0
        } else {
            puts "Unknown sorted set encoding"
            exit
        }

        test "Check encoding - $encoding" {
            r del ztmp
            r zadd ztmp 10 x
            # assert_encoding $encoding ztmp
            # module object is raw
            assert_encoding raw ztmp
        }
        test "ZSET basic ZADD and score update - $encoding" {
            r del ztmp
            r zadd ztmp 10 x
            r zadd ztmp 20 y 
            r zadd ztmp 30 z
            assert_equal {x y z} [r zrange ztmp 0 -1]

            r zadd ztmp 1 y
            assert_equal {y x z} [r zrange ztmp 0 -1]
        }

        test "ZSET element can't be set to NaN with ZADD - $encoding" {
            assert_error "*not*float*" {r zadd myzset nan abc}
        }

        test "ZSET element can't be set to NaN with ZINCRBY" {
            assert_error "*not*float*" {r zincrby myzset nan abc}
        }

        test "ZADD with options syntax error with incomplete pair" {
            r del ztmp
            catch {r zadd ztmp xx 10 x 20} err
            set err
        } {ERR*}

        # test "ZADD XX option without key - $encoding" {
        #     r del ztmp
        #     assert {[r zadd ztmp xx 10 x] == 0}
        #   assert {[r type ztmp] eq {none}}
        # }

        # test "ZADD XX existing key - $encoding" {
        #     r del ztmp
        #     r zadd ztmp 10 x
        #     assert {[r zadd ztmp xx 20 y] == 0}
        #     assert {[r zcard ztmp] == 1}
        # }

        test "ZADD XX returns the number of elements actually added" {
            r del ztmp
            r zadd ztmp 10 x
            set retval [r zadd ztmp 10 x 20 y 30 z]
            assert {$retval == 2}
        }

        test "ZADD XX updates existing elements score" {
            r del ztmp
            r zadd ztmp 10 x 20 y 30 z
            r zadd ztmp xx 5 foo 11 x 21 y 40 zap
            assert {[r zcard ztmp] == 3}
            assert {[r zscore ztmp x] == 11}
            assert {[r zscore ztmp y] == 21}
        }

        test "ZADD XX and NX are not compatible" {
            r del ztmp
            catch {r zadd ztmp xx nx 10 x} err
            set err
        } {ERR*}

        test "ZADD NX with non exisitng key" {
            r del ztmp
            r zadd ztmp nx 10 x 20 y 30 z
            assert {[r zcard ztmp] == 3}
        }

        test "ZADD NX only add new elements without updating old ones" {
            r del ztmp
            r zadd ztmp 10 x 20 y 30 z
            assert {[r zadd ztmp nx 11 x 21 y 100 a 200 b] == 2}
            assert {[r zscore ztmp x] == 10}
            assert {[r zscore ztmp y] == 20}
            assert {[r zscore ztmp a] == 100}
            assert {[r zscore ztmp b] == 200}
        }

        test "ZADD INCR works like ZINCRBY" {
            r del ztmp
            r zadd ztmp 10 x 20 y 30 z
            r zadd ztmp INCR 15 x
            assert {[r zscore ztmp x] == 25}
        }

        test "ZADD INCR works with a single score-elemenet pair" {
            r del ztmp
            r zadd ztmp 10 x 20 y 30 z
            catch {r zadd ztmp INCR 15 x 10 y} err
            set err
        } {ERR*}

        test "ZADD CH option changes return value to all changed elements" {
            r del ztmp
            r zadd ztmp 10 x 20 y 30 z
            assert {[r zadd ztmp 11 x 21 y 30 z] == 0}
            assert {[r zadd ztmp ch 12 x 22 y 30 z] == 2}
        }

        # test "ZINCRBY calls leading to NaN result in error" {
        #     r zincrby myzset +inf abc
        #     assert_error "*NaN*" {r zincrby myzset -inf abc}
        # }

        test {ZADD - Variadic version base case} {
            r del myzset
            list [r zadd myzset 10 a 20 b 30 c] [r zrange myzset 0 -1 withscores]
        } {3 {a 10 b 20 c 30}}

        test {ZADD - Return value is the number of actually added items} {
            list [r zadd myzset 5 x 20 b 30 c] [r zrange myzset 0 -1 withscores]
        } {1 {x 5 a 10 b 20 c 30}}

        test {ZADD - Variadic version does not add nothing on single parsing err} {
            r del myzset
            catch {r zadd myzset 10 a 20 b 30.badscore c} e
            assert_match {*ERR*not*float*} $e
            r exists myzset
        } {0}

        test {ZADD - Variadic version will raise error on missing arg} {
            r del myzset
            catch {r zadd myzset 10 a 20 b 30 c 40} e
            assert_match {*ERR*syntax*} $e
        }

        test {ZINCRBY does not work variadic even if shares ZADD implementation} {
            r del myzset
            catch {r zincrby myzset 10 a 20 b 30 c} e
            assert_match {*ERR*wrong*number*arg*} $e
        }

        test "ZCARD basics - $encoding" {
            r del ztmp
            r zadd ztmp 10 a 20 b 30 c
            assert_equal 3 [r zcard ztmp]
            assert_equal 0 [r zcard zdoesntexist]
        }

        test "ZREM removes key after last element is removed" {
            r del ztmp
            r zadd ztmp 10 x
            r zadd ztmp 20 y

            assert_equal 1 [r exists ztmp]
            assert_equal 0 [r zrem ztmp z]
            assert_equal 1 [r zrem ztmp y]
            assert_equal 1 [r zrem ztmp x]
            assert_equal 0 [r exists ztmp]
        }

        test "ZREM ZINCRBY" {
            r del ztmp
            r zincrby ztmp 10 x 
            r zrem ztmp x 
            r zincrby ztmp 1 x 
            assert_equal 1 [r zscore ztmp x]
        }

        test "ZREM variadic version" {
            r del ztmp
            r zadd ztmp 10 a 20 b 30 c
            assert_equal 2 [r zrem ztmp x y a b k]
            assert_equal 0 [r zrem ztmp foo bar]
            assert_equal 1 [r zrem ztmp c]
            r exists ztmp
        } {0}

        test "ZREM variadic version -- remove elements after key deletion" {
            r del ztmp
            r zadd ztmp 10 a 20 b 30 c
            r zrem ztmp a b c d e f g
        } {3}

        test "ZRANGE basics - $encoding" {
            r del ztmp
            r zadd ztmp 1 a
            r zadd ztmp 2 b
            r zadd ztmp 3 c
            r zadd ztmp 4 d

            assert_equal {a b c d} [r zrange ztmp 0 -1]
            assert_equal {a b c} [r zrange ztmp 0 -2]
            assert_equal {b c d} [r zrange ztmp 1 -1]
            assert_equal {b c} [r zrange ztmp 1 -2]
            assert_equal {c d} [r zrange ztmp -2 -1]
            assert_equal {c} [r zrange ztmp -2 -2]

            # out of range start index
            assert_equal {a b c} [r zrange ztmp -5 2]
            assert_equal {a b} [r zrange ztmp -5 1]
            assert_equal {} [r zrange ztmp 5 -1]
            assert_equal {} [r zrange ztmp 5 -2]

            # out of range end index
            assert_equal {a b c d} [r zrange ztmp 0 5]
            assert_equal {b c d} [r zrange ztmp 1 5]
            assert_equal {} [r zrange ztmp 0 -5]
            assert_equal {} [r zrange ztmp 1 -5]

            # withscores
            assert_equal {a 1 b 2 c 3 d 4} [r zrange ztmp 0 -1 withscores]
        }

        test "ZREVRANGE basics - $encoding" {
            r del ztmp
            r zadd ztmp 1 a
            r zadd ztmp 2 b
            r zadd ztmp 3 c
            r zadd ztmp 4 d

            assert_equal {d c b a} [r zrevrange ztmp 0 -1]
            assert_equal {d c b} [r zrevrange ztmp 0 -2]
            assert_equal {c b a} [r zrevrange ztmp 1 -1]
            assert_equal {c b} [r zrevrange ztmp 1 -2]
            assert_equal {b a} [r zrevrange ztmp -2 -1]
            assert_equal {b} [r zrevrange ztmp -2 -2]

            # out of range start index
            assert_equal {d c b} [r zrevrange ztmp -5 2]
            assert_equal {d c} [r zrevrange ztmp -5 1]
            assert_equal {} [r zrevrange ztmp 5 -1]
            assert_equal {} [r zrevrange ztmp 5 -2]

            # out of range end index
            assert_equal {d c b a} [r zrevrange ztmp 0 5]
            assert_equal {c b a} [r zrevrange ztmp 1 5]
            assert_equal {} [r zrevrange ztmp 0 -5]
            assert_equal {} [r zrevrange ztmp 1 -5]

            # withscores
            assert_equal {d 4 c 3 b 2 a 1} [r zrevrange ztmp 0 -1 withscores]
        }

        test "ZRANK/ZREVRANK basics - $encoding" {
            r del zranktmp
            r zadd zranktmp 10 x
            r zadd zranktmp 20 y
            r zadd zranktmp 30 z
            assert_equal 0 [r zrank zranktmp x]
            assert_equal 1 [r zrank zranktmp y]
            assert_equal 2 [r zrank zranktmp z]
            assert_equal "" [r zrank zranktmp foo]
            assert_equal 2 [r zrevrank zranktmp x]
            assert_equal 1 [r zrevrank zranktmp y]
            assert_equal 0 [r zrevrank zranktmp z]
            assert_equal "" [r zrevrank zranktmp foo]
        }

        test "ZRANK - after deletion - $encoding" {
            r zrem zranktmp y
            assert_equal 0 [r zrank zranktmp x]
            assert_equal 1 [r zrank zranktmp z]
        }

        test "ZINCRBY - can create a new sorted set - $encoding" {
            r del zset
            r zincrby zset 1 foo
            assert_equal {foo} [r zrange zset 0 -1]
            assert_equal 1 [r zscore zset foo]
        }

        test "ZINCRBY - increment and decrement - $encoding" {
            r zincrby zset 2 foo
            r zincrby zset 1 bar
            assert_equal {bar foo} [r zrange zset 0 -1]

            r zincrby zset 10 bar
            r zincrby zset -5 foo
            r zincrby zset -5 bar
            assert_equal {foo bar} [r zrange zset 0 -1]

            assert_equal -2 [r zscore zset foo]
            assert_equal  6 [r zscore zset bar]
        }

        test "ZINCRBY return value" {
            r del ztmp
            set retval [r zincrby ztmp 1.0 x]
            assert {$retval == 1.0}
        }

        proc create_default_zset {} {
            create_zset zset {-inf a 1 b 2 c 3 d 4 e 5 f +inf g}
        }

        test "ZRANGEBYSCORE/ZREVRANGEBYSCORE/ZCOUNT basics" {
            create_default_zset

            # inclusive range
            assert_equal {a b c} [r zrangebyscore zset -inf 2]
            assert_equal {b c d} [r zrangebyscore zset 0 3]
            assert_equal {d e f} [r zrangebyscore zset 3 6]
            assert_equal {e f g} [r zrangebyscore zset 4 +inf]
            assert_equal {c b a} [r zrevrangebyscore zset 2 -inf]
            assert_equal {d c b} [r zrevrangebyscore zset 3 0]
            assert_equal {f e d} [r zrevrangebyscore zset 6 3]
            assert_equal {g f e} [r zrevrangebyscore zset +inf 4]
            assert_equal 3 [r zcount zset 0 3]

            # exclusive range
            assert_equal {b}   [r zrangebyscore zset (-inf (2]
            assert_equal {b c} [r zrangebyscore zset (0 (3]
            assert_equal {e f} [r zrangebyscore zset (3 (6]
            assert_equal {f}   [r zrangebyscore zset (4 (+inf]
            assert_equal {b}   [r zrevrangebyscore zset (2 (-inf]
            assert_equal {c b} [r zrevrangebyscore zset (3 (0]
            assert_equal {f e} [r zrevrangebyscore zset (6 (3]
            assert_equal {f}   [r zrevrangebyscore zset (+inf (4]
            assert_equal 2 [r zcount zset (0 (3]

            # test empty ranges
            r zrem zset a
            r zrem zset g

            # inclusive
            assert_equal {} [r zrangebyscore zset 4 2]
            assert_equal {} [r zrangebyscore zset 6 +inf]
            assert_equal {} [r zrangebyscore zset -inf -6]
            assert_equal {} [r zrevrangebyscore zset +inf 6]
            assert_equal {} [r zrevrangebyscore zset -6 -inf]

            # exclusive
            assert_equal {} [r zrangebyscore zset (4 (2]
            assert_equal {} [r zrangebyscore zset 2 (2]
            assert_equal {} [r zrangebyscore zset (2 2]
            assert_equal {} [r zrangebyscore zset (6 (+inf]
            assert_equal {} [r zrangebyscore zset (-inf (-6]
            assert_equal {} [r zrevrangebyscore zset (+inf (6]
            assert_equal {} [r zrevrangebyscore zset (-6 (-inf]

            # empty inner range
            assert_equal {} [r zrangebyscore zset 2.4 2.6]
            assert_equal {} [r zrangebyscore zset (2.4 2.6]
            assert_equal {} [r zrangebyscore zset 2.4 (2.6]
            assert_equal {} [r zrangebyscore zset (2.4 (2.6]
        }

        test "ZRANGEBYSCORE with WITHSCORES" {
            create_default_zset
            assert_equal {b 1 c 2 d 3} [r zrangebyscore zset 0 3 withscores]
            assert_equal {d 3 c 2 b 1} [r zrevrangebyscore zset 3 0 withscores]
        }

        test "ZRANGEBYSCORE with LIMIT" {
            create_default_zset
            assert_equal {b c}   [r zrangebyscore zset 0 10 LIMIT 0 2]
            assert_equal {d e f} [r zrangebyscore zset 0 10 LIMIT 2 3]
            assert_equal {d e f} [r zrangebyscore zset 0 10 LIMIT 2 10]
            assert_equal {}      [r zrangebyscore zset 0 10 LIMIT 20 10]
            assert_equal {f e}   [r zrevrangebyscore zset 10 0 LIMIT 0 2]
            assert_equal {d c b} [r zrevrangebyscore zset 10 0 LIMIT 2 3]
            assert_equal {d c b} [r zrevrangebyscore zset 10 0 LIMIT 2 10]
            assert_equal {}      [r zrevrangebyscore zset 10 0 LIMIT 20 10]
        }

        test "ZRANGEBYSCORE with LIMIT and WITHSCORES" {
            create_default_zset
            assert_equal {e 4 f 5} [r zrangebyscore zset 2 5 LIMIT 2 3 WITHSCORES]
            assert_equal {d 3 c 2} [r zrevrangebyscore zset 5 2 LIMIT 2 3 WITHSCORES]
        }

        test "ZRANGEBYSCORE with non-value min or max" {
            assert_error "*not*float*" {r zrangebyscore fooz str 1}
            assert_error "*not*float*" {r zrangebyscore fooz 1 str}
            assert_error "*not*float*" {r zrangebyscore fooz 1 NaN}
        }

        proc create_default_lex_zset {} {
            create_zset zset {0 alpha 0 bar 0 cool 0 down
                              0 elephant 0 foo 0 great 0 hill
                              0 omega}
        }

        test "ZRANGEBYLEX/ZREVRANGEBYLEX/ZLEXCOUNT basics" {
            create_default_lex_zset

            # inclusive range
            assert_equal {alpha bar cool} [r zrangebylex zset - \[cool]
            assert_equal {bar cool down} [r zrangebylex zset \[bar \[down]
            assert_equal {great hill omega} [r zrangebylex zset \[g +]
            assert_equal {cool bar alpha} [r zrevrangebylex zset \[cool -]
            assert_equal {down cool bar} [r zrevrangebylex zset \[down \[bar]
            assert_equal {omega hill great foo elephant down} [r zrevrangebylex zset + \[d]
            assert_equal 3 [r zlexcount zset \[ele \[h]

            # exclusive range
            assert_equal {alpha bar} [r zrangebylex zset - (cool]
            assert_equal {cool} [r zrangebylex zset (bar (down]
            assert_equal {hill omega} [r zrangebylex zset (great +]
            assert_equal {bar alpha} [r zrevrangebylex zset (cool -]
            assert_equal {cool} [r zrevrangebylex zset (down (bar]
            assert_equal {omega hill} [r zrevrangebylex zset + (great]
            assert_equal 2 [r zlexcount zset (ele (great]

            # inclusive and exclusive
            assert_equal {} [r zrangebylex zset (az (b]
            assert_equal {} [r zrangebylex zset (z +]
            assert_equal {} [r zrangebylex zset - \[aaaa]
            assert_equal {} [r zrevrangebylex zset \[elez \[elex]
            assert_equal {} [r zrevrangebylex zset (hill (omega]
        }
        
        test "ZLEXCOUNT advanced" {
            create_default_lex_zset
    
            assert_equal 9 [r zlexcount zset - +]
            assert_equal 0 [r zlexcount zset + -]
            assert_equal 0 [r zlexcount zset + \[c]
            assert_equal 0 [r zlexcount zset \[c -]
            assert_equal 8 [r zlexcount zset \[bar +]
            assert_equal 5 [r zlexcount zset \[bar \[foo]
            assert_equal 4 [r zlexcount zset \[bar (foo]
            assert_equal 4 [r zlexcount zset (bar \[foo]
            assert_equal 3 [r zlexcount zset (bar (foo]
            assert_equal 5 [r zlexcount zset - (foo]
            assert_equal 1 [r zlexcount zset (maxstring +]
        }

        test "ZRANGEBYSLEX with LIMIT" {
            create_default_lex_zset
            assert_equal {alpha bar} [r zrangebylex zset - \[cool LIMIT 0 2]
            assert_equal {bar cool} [r zrangebylex zset - \[cool LIMIT 1 2]
            assert_equal {} [r zrangebylex zset \[bar \[down LIMIT 0 0]
            assert_equal {} [r zrangebylex zset \[bar \[down LIMIT 2 0]
            assert_equal {bar} [r zrangebylex zset \[bar \[down LIMIT 0 1]
            assert_equal {cool} [r zrangebylex zset \[bar \[down LIMIT 1 1]
            assert_equal {bar cool down} [r zrangebylex zset \[bar \[down LIMIT 0 100]
            assert_equal {omega hill great foo elephant} [r zrevrangebylex zset + \[d LIMIT 0 5]
            assert_equal {omega hill great foo} [r zrevrangebylex zset + \[d LIMIT 0 4]
        }

        test "ZRANGEBYLEX with invalid lex range specifiers" {
            assert_error "*not*string*" {r zrangebylex fooz foo bar}
            assert_error "*not*string*" {r zrangebylex fooz \[foo bar}
            assert_error "*not*string*" {r zrangebylex fooz foo \[bar}
            assert_error "*not*string*" {r zrangebylex fooz +x \[bar}
            assert_error "*not*string*" {r zrangebylex fooz -x \[bar}
        }

        test "ZREMRANGEBYSCORE basics" {
            proc remrangebyscore {min max} {
                create_zset zset {1 a 2 b 3 c 4 d 5 e}
                assert_equal 1 [r exists zset]
                r zremrangebyscore zset $min $max
            }

            # inner range
            assert_equal 3 [remrangebyscore 2 4]
            assert_equal {a e} [r zrange zset 0 -1]

            # start underflow
            assert_equal 1 [remrangebyscore -10 1]
            assert_equal {b c d e} [r zrange zset 0 -1]

            # end overflow
            assert_equal 1 [remrangebyscore 5 10]
            assert_equal {a b c d} [r zrange zset 0 -1]

            # switch min and max
            assert_equal 0 [remrangebyscore 4 2]
            assert_equal {a b c d e} [r zrange zset 0 -1]

            # -inf to mid
            assert_equal 3 [remrangebyscore -inf 3]
            assert_equal {d e} [r zrange zset 0 -1]

            # mid to +inf
            assert_equal 3 [remrangebyscore 3 +inf]
            assert_equal {a b} [r zrange zset 0 -1]

            # -inf to +inf
            assert_equal 5 [remrangebyscore -inf +inf]
            assert_equal {} [r zrange zset 0 -1]

            # exclusive min
            assert_equal 4 [remrangebyscore (1 5]
            assert_equal {a} [r zrange zset 0 -1]
            assert_equal 3 [remrangebyscore (2 5]
            assert_equal {a b} [r zrange zset 0 -1]

            # exclusive max
            assert_equal 4 [remrangebyscore 1 (5]
            assert_equal {e} [r zrange zset 0 -1]
            assert_equal 3 [remrangebyscore 1 (4]
            assert_equal {d e} [r zrange zset 0 -1]

            # exclusive min and max
            assert_equal 3 [remrangebyscore (1 (5]
            assert_equal {a e} [r zrange zset 0 -1]

            # destroy when empty
            assert_equal 5 [remrangebyscore 1 5]
            assert_equal 0 [r exists zset]
        }

        test "ZREMRANGEBYSCORE with non-value min or max" {
            assert_error "*not*float*" {r zremrangebyscore fooz str 1}
            assert_error "*not*float*" {r zremrangebyscore fooz 1 str}
            assert_error "*not*float*" {r zremrangebyscore fooz 1 NaN}
        }

        test "ZREMRANGEBYRANK basics" {
            proc remrangebyrank {min max} {
                create_zset zset {1 a 2 b 3 c 4 d 5 e}
                assert_equal 1 [r exists zset]
                r zremrangebyrank zset $min $max
            }

            # inner range
            assert_equal 3 [remrangebyrank 1 3]
            assert_equal {a e} [r zrange zset 0 -1]

            # start underflow
            assert_equal 1 [remrangebyrank -10 0]
            assert_equal {b c d e} [r zrange zset 0 -1]

            # start overflow
            assert_equal 0 [remrangebyrank 10 -1]
            assert_equal {a b c d e} [r zrange zset 0 -1]

            # end underflow
            assert_equal 0 [remrangebyrank 0 -10]
            assert_equal {a b c d e} [r zrange zset 0 -1]

            # end overflow
            assert_equal 5 [remrangebyrank 0 10]
            assert_equal {} [r zrange zset 0 -1]

            # destroy when empty
            assert_equal 5 [remrangebyrank 0 4]
            assert_equal 0 [r exists zset]
        }

    #     test "ZUNIONSTORE against non-existing key doesn't set destination - $encoding" {
    #         r del zseta
    #         assert_equal 0 [r zunionstore dst_key 1 zseta]
    #         assert_equal 0 [r exists dst_key]
    #     }

    #     test "ZUNIONSTORE with empty set - $encoding" {
    #         r del zseta zsetb
    #         r zadd zseta 1 a
    #         r zadd zseta 2 b
    #         r zunionstore zsetc 2 zseta zsetb
    #         r zrange zsetc 0 -1 withscores
    #     } {a 1 b 2}

    #     test "ZUNIONSTORE basics - $encoding" {
    #         r del zseta zsetb zsetc
    #         r zadd zseta 1 a
    #         r zadd zseta 2 b
    #         r zadd zseta 3 c
    #         r zadd zsetb 1 b
    #         r zadd zsetb 2 c
    #         r zadd zsetb 3 d

    #         assert_equal 4 [r zunionstore zsetc 2 zseta zsetb]
    #         assert_equal {a 1 b 3 d 3 c 5} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZUNIONSTORE with weights - $encoding" {
    #         assert_equal 4 [r zunionstore zsetc 2 zseta zsetb weights 2 3]
    #         assert_equal {a 2 b 7 d 9 c 12} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZUNIONSTORE with a regular set and weights - $encoding" {
    #         r del seta
    #         r sadd seta a
    #         r sadd seta b
    #         r sadd seta c

    #         assert_equal 4 [r zunionstore zsetc 2 seta zsetb weights 2 3]
    #         assert_equal {a 2 b 5 c 8 d 9} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZUNIONSTORE with AGGREGATE MIN - $encoding" {
    #         assert_equal 4 [r zunionstore zsetc 2 zseta zsetb aggregate min]
    #         assert_equal {a 1 b 1 c 2 d 3} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZUNIONSTORE with AGGREGATE MAX - $encoding" {
    #         assert_equal 4 [r zunionstore zsetc 2 zseta zsetb aggregate max]
    #         assert_equal {a 1 b 2 c 3 d 3} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZINTERSTORE basics - $encoding" {
    #         assert_equal 2 [r zinterstore zsetc 2 zseta zsetb]
    #         assert_equal {b 3 c 5} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZINTERSTORE with weights - $encoding" {
    #         assert_equal 2 [r zinterstore zsetc 2 zseta zsetb weights 2 3]
    #         assert_equal {b 7 c 12} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZINTERSTORE with a regular set and weights - $encoding" {
    #         r del seta
    #         r sadd seta a
    #         r sadd seta b
    #         r sadd seta c
    #         assert_equal 2 [r zinterstore zsetc 2 seta zsetb weights 2 3]
    #         assert_equal {b 5 c 8} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZINTERSTORE with AGGREGATE MIN - $encoding" {
    #         assert_equal 2 [r zinterstore zsetc 2 zseta zsetb aggregate min]
    #         assert_equal {b 1 c 2} [r zrange zsetc 0 -1 withscores]
    #     }

    #     test "ZINTERSTORE with AGGREGATE MAX - $encoding" {
    #         assert_equal 2 [r zinterstore zsetc 2 zseta zsetb aggregate max]
    #         assert_equal {b 2 c 3} [r zrange zsetc 0 -1 withscores]
    #     }

    #     foreach cmd {ZUNIONSTORE ZINTERSTORE} {
    #         test "$cmd with +inf/-inf scores - $encoding" {
    #             r del zsetinf1 zsetinf2

    #             r zadd zsetinf1 +inf key
    #             r zadd zsetinf2 +inf key
    #             r $cmd zsetinf3 2 zsetinf1 zsetinf2
    #             assert_equal inf [r zscore zsetinf3 key]

    #             r zadd zsetinf1 -inf key
    #             r zadd zsetinf2 +inf key
    #             r $cmd zsetinf3 2 zsetinf1 zsetinf2
    #             assert_equal 0 [r zscore zsetinf3 key]

    #             r zadd zsetinf1 +inf key
    #             r zadd zsetinf2 -inf key
    #             r $cmd zsetinf3 2 zsetinf1 zsetinf2
    #             assert_equal 0 [r zscore zsetinf3 key]

    #             r zadd zsetinf1 -inf key
    #             r zadd zsetinf2 -inf key
    #             r $cmd zsetinf3 2 zsetinf1 zsetinf2
    #             assert_equal -inf [r zscore zsetinf3 key]
    #         }

    #         test "$cmd with NaN weights $encoding" {
    #             r del zsetinf1 zsetinf2

    #             r zadd zsetinf1 1.0 key
    #             r zadd zsetinf2 1.0 key
    #             assert_error "*weight*not*float*" {
    #                 r $cmd zsetinf3 2 zsetinf1 zsetinf2 weights nan nan
    #             }
    #         }
    #     }
    }

    # basics ziplist
    basics skiplist

    # test {ZINTERSTORE regression with two sets, intset+hashtable} {
    #     r del seta setb setc
    #     r sadd set1 a
    #     r sadd set2 10
    #     r zinterstore set3 2 set1 set2
    # } {0}

    # test {ZUNIONSTORE regression, should not create NaN in scores} {
    #     r zadd z -inf neginf
    #     r zunionstore out 1 z weights 0
    #     r zrange out 0 -1 withscores
    # } {neginf 0}

    # test {ZINTERSTORE #516 regression, mixed sets and ziplist zsets} {
    #     r sadd one 100 101 102 103
    #     r sadd two 100 200 201 202
    #     r zadd three 1 500 1 501 1 502 1 503 1 100
    #     r zinterstore to_here 3 one two three WEIGHTS 0 0 1
    #     r zrange to_here 0 -1
    # } {100}

    # test {ZUNIONSTORE result is sorted} {
    #     # Create two sets with common and not common elements, perform
    #     # the UNION, check that elements are still sorted.
    #     r del one two dest
    #     set cmd1 [list r zadd one]
    #     set cmd2 [list r zadd two]
    #     for {set j 0} {$j < 1000} {incr j} {
    #         lappend cmd1 [expr rand()] [randomInt 1000]
    #         lappend cmd2 [expr rand()] [randomInt 1000]
    #     }
    #     {*}$cmd1
    #     {*}$cmd2
    #     assert {[r zcard one] > 100}
    #     assert {[r zcard two] > 100}
    #     r zunionstore dest 2 one two
    #     set oldscore 0
    #     foreach {ele score} [r zrange dest 0 -1 withscores] {
    #         assert {$score >= $oldscore}
    #         set oldscore $score
    #     }
    # }

    test "ZSET commands don't accept the empty strings as valid score" {
        assert_error "*not*float*" {r zadd myzset "" abc}
    }

    proc stressers {encoding} {
        if {$encoding == "ziplist"} {
            # Little extra to allow proper fuzzing in the sorting stresser
            r config set zset-max-ziplist-entries 256
            r config set zset-max-ziplist-value 64
            set elements 128
        } elseif {$encoding == "skiplist"} {
            r config set zset-max-ziplist-entries 0
            r config set zset-max-ziplist-value 0
            if {$::accurate} {set elements 1000} else {set elements 100}
        } else {
            puts "Unknown sorted set encoding"
            exit
        }

        test "ZSCORE - $encoding" {
            r del zscoretest
            set aux {}
            for {set i 0} {$i < $elements} {incr i} {
                set score [expr rand()]
                lappend aux $score
                r zadd zscoretest $score $i
            }

            assert_encoding $encoding zscoretest
            for {set i 0} {$i < $elements} {incr i} {
                assert_equal [lindex $aux $i] [r zscore zscoretest $i]
            }
        }

        test "ZSCORE after a DEBUG RELOAD - $encoding" {
            r del zscoretest
            set aux {}
            for {set i 0} {$i < $elements} {incr i} {
                set score [expr rand()]
                lappend aux $score
                r zadd zscoretest $score $i
            }

            r debug reload
            assert_encoding $encoding zscoretest
            for {set i 0} {$i < $elements} {incr i} {
                assert_equal [lindex $aux $i] [r zscore zscoretest $i]
            }
        }

        test "ZSET sorting stresser - $encoding" {
            set delta 0
            for {set test 0} {$test < 2} {incr test} {
                unset -nocomplain auxarray
                array set auxarray {}
                set auxlist {}
                r del myzset
                for {set i 0} {$i < $elements} {incr i} {
                    if {$test == 0} {
                        set score [expr rand()]
                    } else {
                        set score [expr int(rand()*10)]
                    }
                    set auxarray($i) $score
                    r zadd myzset $score $i
                    # Random update
                    if {[expr rand()] < .2} {
                        set j [expr int(rand()*1000)]
                        if {$test == 0} {
                            set score [expr rand()]
                        } else {
                            set score [expr int(rand()*10)]
                        }
                        set auxarray($j) $score
                        r zadd myzset $score $j
                    }
                }
                foreach {item score} [array get auxarray] {
                    lappend auxlist [list $score $item]
                }
                set sorted [lsort -command zlistAlikeSort $auxlist]
                set auxlist {}
                foreach x $sorted {
                    lappend auxlist [lindex $x 1]
                }

                assert_encoding $encoding myzset
                set fromredis [r zrange myzset 0 -1]
                set delta 0
                for {set i 0} {$i < [llength $fromredis]} {incr i} {
                    if {[lindex $fromredis $i] != [lindex $auxlist $i]} {
                        incr delta
                    }
                }
            }
            assert_equal 0 $delta
        }

        test "ZRANGEBYSCORE fuzzy test, 100 ranges in $elements element sorted set - $encoding" {
            set err {}
            r del zset
            for {set i 0} {$i < $elements} {incr i} {
                r zadd zset [expr rand()] $i
            }

            assert_encoding $encoding zset
            for {set i 0} {$i < 100} {incr i} {
                set min [expr rand()]
                set max [expr rand()]
                if {$min > $max} {
                    set aux $min
                    set min $max
                    set max $aux
                }
                set low [r zrangebyscore zset -inf $min]
                set ok [r zrangebyscore zset $min $max]
                set high [r zrangebyscore zset $max +inf]
                set lowx [r zrangebyscore zset -inf ($min]
                set okx [r zrangebyscore zset ($min ($max]
                set highx [r zrangebyscore zset ($max +inf]

                if {[r zcount zset -inf $min] != [llength $low]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset $min $max] != [llength $ok]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset $max +inf] != [llength $high]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset -inf ($min] != [llength $lowx]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset ($min ($max] != [llength $okx]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset ($max +inf] != [llength $highx]} {
                    append err "Error, len does not match zcount\n"
                }

                foreach x $low {
                    set score [r zscore zset $x]
                    if {$score > $min} {
                        append err "Error, score for $x is $score > $min\n"
                    }
                }
                foreach x $lowx {
                    set score [r zscore zset $x]
                    if {$score >= $min} {
                        append err "Error, score for $x is $score >= $min\n"
                    }
                }
                foreach x $ok {
                    set score [r zscore zset $x]
                    if {$score < $min || $score > $max} {
                        append err "Error, score for $x is $score outside $min-$max range\n"
                    }
                }
                foreach x $okx {
                    set score [r zscore zset $x]
                    if {$score <= $min || $score >= $max} {
                        append err "Error, score for $x is $score outside $min-$max open range\n"
                    }
                }
                foreach x $high {
                    set score [r zscore zset $x]
                    if {$score < $max} {
                        append err "Error, score for $x is $score < $max\n"
                    }
                }
                foreach x $highx {
                    set score [r zscore zset $x]
                    if {$score <= $max} {
                        append err "Error, score for $x is $score <= $max\n"
                    }
                }
            }
            assert_equal {} $err
        }

        test "ZRANGEBYLEX fuzzy test, 100 ranges in $elements element sorted set - $encoding" {
            set lexset {}
            r del zset
            for {set j 0} {$j < $elements} {incr j} {
                set e [randstring 0 30 alpha]
                lappend lexset $e
                r zadd zset 0 $e
            }
            set lexset [lsort -unique $lexset]
            for {set j 0} {$j < 100} {incr j} {
                set min [randstring 0 30 alpha]
                set max [randstring 0 30 alpha]
                set mininc [randomInt 2]
                set maxinc [randomInt 2]
                if {$mininc} {set cmin "\[$min"} else {set cmin "($min"}
                if {$maxinc} {set cmax "\[$max"} else {set cmax "($max"}
                set rev [randomInt 2]
                if {$rev} {
                    set cmd zrevrangebylex
                } else {
                    set cmd zrangebylex
                }

                # Make sure data is the same in both sides
                assert {[r zrange zset 0 -1] eq $lexset}

                # Get the Redis output
                set output [r $cmd zset $cmin $cmax]
                if {$rev} {
                    set outlen [r zlexcount zset $cmax $cmin]
                } else {
                    set outlen [r zlexcount zset $cmin $cmax]
                }

                # Compute the same output via Tcl
                set o {}
                set copy $lexset
                if {(!$rev && [string compare $min $max] > 0) ||
                    ($rev && [string compare $max $min] > 0)} {
                    # Empty output when ranges are inverted.
                } else {
                    if {$rev} {
                        # Invert the Tcl array using Redis itself.
                        set copy [r zrevrange zset 0 -1]
                        # Invert min / max as well
                        lassign [list $min $max $mininc $maxinc] \
                            max min maxinc mininc
                    }
                    foreach e $copy {
                        set mincmp [string compare $e $min]
                        set maxcmp [string compare $e $max]
                        if {
                             ($mininc && $mincmp >= 0 || !$mininc && $mincmp > 0)
                             &&
                             ($maxinc && $maxcmp <= 0 || !$maxinc && $maxcmp < 0)
                        } {
                            lappend o $e
                        }
                    }
                }
                assert {$o eq $output}
                assert {$outlen eq [llength $output]}
            }
        }

        test "ZREMRANGEBYLEX fuzzy test, 100 ranges in $elements element sorted set - $encoding" {
            set lexset {}
            r del zset zsetcopy
            for {set j 0} {$j < $elements} {incr j} {
                set e [randstring 0 30 alpha]
                lappend lexset $e
                r zadd zset 0 $e
                #Copy...
                r zadd zsetcopy 0 $e
            }
            set lexset [lsort -unique $lexset]
            for {set j 0} {$j < 100} {incr j} {
                # Copy...
                # r zunionstore zsetcopy 1 zset
                set lexsetcopy $lexset

                set min [randstring 0 30 alpha]
                set max [randstring 0 30 alpha]
                set mininc [randomInt 2]
                set maxinc [randomInt 2]
                if {$mininc} {set cmin "\[$min"} else {set cmin "($min"}
                if {$maxinc} {set cmax "\[$max"} else {set cmax "($max"}

                # Make sure data is the same in both sides
                assert {[r zrange zset 0 -1] eq $lexset}

                # Get the range we are going to remove
                set torem [r zrangebylex zset $cmin $cmax]
                set toremlen [r zlexcount zset $cmin $cmax]
                r zremrangebylex zsetcopy $cmin $cmax
                set output [r zrange zsetcopy 0 -1]

                # Remove the range with Tcl from the original list
                if {$toremlen} {
                    set first [lsearch -exact $lexsetcopy [lindex $torem 0]]
                    set last [expr {$first+$toremlen-1}]
                    set lexsetcopy [lreplace $lexsetcopy $first $last]
                }
                assert {$lexsetcopy eq $output}
            }
        }

        test "ZSETs skiplist implementation backlink consistency test - $encoding" {
            set diff 0
            for {set j 0} {$j < $elements} {incr j} {
                r zadd myzset [expr rand()] "Element-$j"
                r zrem myzset "Element-[expr int(rand()*$elements)]"
            }

            assert_encoding $encoding myzset
            set l1 [r zrange myzset 0 -1]
            set l2 [r zrevrange myzset 0 -1]
            for {set j 0} {$j < [llength $l1]} {incr j} {
                if {[lindex $l1 $j] ne [lindex $l2 end-$j]} {
                    incr diff
                }
            }
            assert_equal 0 $diff
        }

        test "ZSETs ZRANK augmented skip list stress testing - $encoding" {
            set err {}
            r del myzset
            for {set k 0} {$k < 2000} {incr k} {
                set i [expr {$k % $elements}]
                if {[expr rand()] < .2} {
                    r zrem myzset $i
                } else {
                    set score [expr rand()]
                    r zadd myzset $score $i
                    assert_encoding $encoding myzset
                }

                set card [r zcard myzset]
                if {$card > 0} {
                    set index [randomInt $card]
                    set ele [lindex [r zrange myzset $index $index] 0]
                    set rank [r zrank myzset $ele]
                    if {$rank != $index} {
                        set err "$ele RANK is wrong! ($rank != $index)"
                        break
                    }
                }
            }
            assert_equal {} $err
        }
    }

    tags {"slow"} {
        # stressers ziplist
        # stressers skiplist
    }
}







start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer peerof $master_gid $master_host $master_port
        wait_for_peer_sync $peer
        test "command" {
            test "before" {
                test "zadd" {
                    test "zadd " {
                        $master zadd zset1000 1.0 a 2.0 b 
                    }
                    test "zadd + zadd" {
                        $master zadd zset1010 1.0 a  
                        $master zadd zset1010 3.0 a 2.0 b 
                    }
                    test "zincrby + zadd" {
                        $master zincrby zset1020 1.0 a  
                        # puts [$master crdt.datainfo zset1020]
                        $master zadd zset1020 3.0 a 2.0 b 
                        # puts [$master crdt.datainfo zset1020]
                    }
                    test "zrem + zadd" {
                        test "zrem(zadd) + zadd" {
                            $master zadd zset1030 1.0 a  
                            $master zrem zset1030 a 
                            $master zadd zset1030 2.0 a
                        }
                        test "zrem(zincrby) + zadd" {
                            $master zincrby zset1031 1.0 a  
                            $master zrem zset1031 a 
                            $master zadd zset1031 2.0 a
                        }
                        test "zrem(zadd + zincrby) + zadd" {
                            $master zadd zset1032 1.0 a 
                            $master zincrby zset1032 1.0 a  
                            $master zrem zset1032 a 
                            $master zadd zset1032 2.0 a
                        }
                        
                    }
                    
                    test "del + zadd" {
                        test "del(zadd) + zadd" {
                            $master zadd zset1040 1.0 a  2.0 b
                            $master del zset1040  
                            $master zadd zset1040 2.0 a  3.0 b
                        }
                        test "del(zincrby) + zadd" {
                            $master zincrby zset1041 1.0 a  
                            $master zrem zset1041 a 
                            $master zadd zset1041 2.0 a 3.0 b
                        }
                        test "del(zadd + zincrby) + zadd" {
                            $master zadd zset1042 1.0 a 2.0 b
                            $master zincrby zset1042 1.0 a  
                            $master zrem zset1042 a 
                            $master zadd zset1042 2.0 a 3.0 b
                        }
                    }
                }
                test "zincrby" {
                    test "zincrby " {
                        $master zincrby zset1100 1.0 a 
                    }
                    test "zincrby + zincrby" {
                        $master zincrby zset1110 1.0 a
                        $master zincrby zset1110 2.0 a
                    }
                    test "zadd + zincrby" {
                        $master zincrby zset1120 1.0 a
                        $master zadd zset1120 3.0 a  
                    }
                    test "zrem + zincrby" {
                        test "zrem(zadd) + zincrby" {
                            $master zadd zset1130 1.0 a  
                            $master zrem zset1130 a 
                            $master zincrby zset1130 2.0 a
                        }
                        test "zrem(zincrby) + zincrby" {
                            $master zincrby zset1131 1.0 a  
                            $master zrem zset1131 a 
                            $master zincrby zset1131 2.0 a
                        }
                        test "zrem(zadd + zincrby) + zincrby" {
                            $master zadd zset1132 1.0 a 
                            $master zincrby zset1132 1.0 a  
                            $master zrem zset1132 a 
                            $master zincrby zset1132 2.0 a
                        }
                    }
                    test "del + zincrby" {
                        test "del(zadd) + zincrby" {
                            $master zadd zset1140 1.0 a  2.0 b
                            $master del zset1140  
                            $master zincrby zset1140 2.0 a  
                        }
                        test "del(zincrby) + zincrby" {
                            $master zincrby zset1141 1.0 a  
                            $master zrem zset1141 a 
                            $master zincrby zset1141 2.0 a 
                        }
                        test "del(zadd + zincrby) + zincrby" {
                            $master zadd zset1142 1.0 a 2.0 b
                            $master zincrby zset1142 1.0 a  
                            $master zrem zset1142 a 
                            $master zincrby zset1142 2.0 a 
                        }
                    }
                }
                test "zrem" {
                    test "zrem (zadd)" {
                        $master zadd zset1200 1.0 a
                        $master zrem zset1200 a
                    }
                    test "zrem (zincrby)" {
                        $master zincrby zset1201 1.0 a
                        $master zrem zset1200 a
                    }
                    test "zrem (zadd + zincby)" {
                        $master zincrby zset1201 1.0 a
                        $master zrem zset1200 a
                    }
                }
               test "del" {
                    test "del (zadd)" {
                        $master zadd zset1300 1.0 a
                        $master del zset1300 
                    }
                    test "del (zincrby)" {
                        $master zincrby zset1301 1.0 a
                        $master del zset1300 
                    }
                    test "del (zadd + zincby)" {
                        $master zincrby zset1301 1.0 a
                        $master del zset1300 
                    }
                }
            }
            
            after 5000
            test "after" {
                test "zadd" {
                    test "zadd " {
                        assert_equal [$master crdt.datainfo  zset1000] [$peer crdt.datainfo zset1000]
                    }
                    test "zadd + zadd" {
                        assert_equal [$master crdt.datainfo  zset1010] [$peer crdt.datainfo zset1010]
                    }
                    test "zincrby + zadd" {
                        assert_equal [$master crdt.datainfo  zset1020] [$peer crdt.datainfo zset1020]
                    }
                    test "zrem + zadd" {
                        assert_equal [$master crdt.datainfo  zset1030] [$peer crdt.datainfo zset1030]
                        assert_equal [$master crdt.datainfo  zset1031] [$peer crdt.datainfo zset1031]
                        assert_equal [$master crdt.datainfo  zset1032] [$peer crdt.datainfo zset1032]
                    }
                    test "del + zadd" {
                        assert_equal [$master crdt.datainfo  zset1040] [$peer crdt.datainfo zset1040]
                        assert_equal [$master crdt.datainfo  zset1041] [$peer crdt.datainfo zset1041]
                        assert_equal [$master crdt.datainfo  zset1042] [$peer crdt.datainfo zset1042]
                    }
                }
                test "zincrby" {
                    test "zincrby " {
                        assert_equal [$master crdt.datainfo  zset1100] [$peer crdt.datainfo zset1100]
                    }
                    test "zincrby + zincrby" {
                        assert_equal [$master crdt.datainfo  zset1110] [$peer crdt.datainfo zset1110]
                    }
                    test "zadd + zincrby" {
                        assert_equal [$master crdt.datainfo  zset1120] [$peer crdt.datainfo zset1120]
                    }
                    test "zrem + zincrby" {
                        assert_equal [$master crdt.datainfo  zset1130] [$peer crdt.datainfo zset1130]
                        assert_equal [$master crdt.datainfo  zset1131] [$peer crdt.datainfo zset1131]
                        assert_equal [$master crdt.datainfo  zset1132] [$peer crdt.datainfo zset1132]
                    }
                    test "del + zincrby" {
                        assert_equal [$master crdt.datainfo  zset1140] [$peer crdt.datainfo zset1140]
                        assert_equal [$master crdt.datainfo  zset1141] [$peer crdt.datainfo zset1141]
                        assert_equal [$master crdt.datainfo  zset1142] [$peer crdt.datainfo zset1142]
                    }
                }
                test "zrem" {
                    test "zrem (zadd)" {
                        assert_equal [$master crdt.datainfo  zser1200] [$peer crdt.datainfo zser1200]
                    }
                    test "zrem (zincrby)" {
                        assert_equal [$master crdt.datainfo  zser1210] [$peer crdt.datainfo zser1210]
                    }
                    test "zrem (zadd + zincby)" {
                        assert_equal [$master crdt.datainfo  zser1220] [$peer crdt.datainfo zser1220]
                    }
                }
                 test "del" {
                    test "del (zadd)" {
                        assert_equal [$master crdt.datainfo  zser1300] [$peer crdt.datainfo zser1300]
                    }
                    test "del (zincrby)" {
                        assert_equal [$master crdt.datainfo  zser1310] [$peer crdt.datainfo zser1310]
                    }
                    test "del (zadd + zincby)" {
                        assert_equal [$master crdt.datainfo  zser1320] [$peer crdt.datainfo zser1320]
                    }
                }
               
            }
        }
        
        

    }
}

test "params" {
    start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
  
        proc params_error {script} {
            catch {[uplevel 1 $script ]} result opts
            # puts $result
            assert_match "*ERR wrong number of arguments for '*' command*" $result
        }
        test "params" {
            params_error {
                r zadd
            }
            params_error {
                r ZSCORE 
            }
            params_error {
                r ZCARD 
            }
            params_error {
                r zincrby
            }
            params_error {
                r zcount
            }
            params_error {
                r ZRANGE
            }
            params_error {
                r zremrangebylex
            }
            params_error {
                r zrevrange
            }
            params_error {
                r zrangebyscore
            }
            params_error {
                r zrevrangebyscore
            }
            params_error {
                r zrank
            }
            params_error {
                r zrevrank
            }
            params_error {
                r zrem
            }
            params_error {
                r zremrangebyrank
            }
            params_error {
                r zremrangebyscore
            }
            params_error {
                r zrangebylex
            }
            params_error {
                r zlexcount
            }
            params_error {
                r zrevrangebylex
            }
            params_error {
                r zscan
            }
        }
        proc type_error {script} {
            catch {[uplevel 1 $script ]} result opts
            assert_match "*WRONGTYPE Operation against a key holding the wrong kind of value*" $result
        }
        test "type_error" {
            r set zset a 
            type_error {
                r zadd zset 1.0 a
            }
            type_error {
                r ZSCORE zset a
            }
            type_error {
                r ZCARD zset
            }
            type_error {
                r zincrby zset 1.0 a
            }
            type_error {
                r zcount zset 0 -1
            }
            type_error {
                r ZRANGE zset 0 1
            }
            type_error {
                r zremrangebylex zset {[alpha} {[omega}
            }
            type_error {
                r zrevrange zset 0 -1
            }
            type_error {
                r zrangebyscore zset 0 -1
            }
            type_error {
                r zrevrangebyscore zset 0 -1
            }
            type_error {
                r zrank zset a 
            }
            type_error {
                r zrevrank zset a
            }
            type_error {
                r zrem zset a
            }
            type_error {
                r zremrangebyrank zset 0 -1
            }
            type_error {
                r zremrangebyscore zset 0 2
            }
            type_error {
                r zrangebylex zset  {[aaa} {(g}
            }
            type_error {
                r zlexcount zset {[aaa} {(g}
            }
            type_error {
                r zrevrangebylex zset {(g} {[aaa}
            }
            type_error {
                r zscan zset 0
            }
            assert_equal [r get zset] a
        }
    }
}

