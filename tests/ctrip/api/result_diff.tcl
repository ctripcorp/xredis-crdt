

set server_path [tmpdir "result_diff"]
start_server {tags {"repl"} overrides {crdt-gid 3} module {crdt.so} } {
    set crdt [srv 0 client]
    set crdt_host [srv 0 host]
    set crdt_port [srv 0 port]
    set crdt_log [srv 0 stdout]
    start_redis [list overrides [list repl-diskless-sync-delay 1 "dir"  $server_path ]] {
        set redis [srv 0 client]
        set redis_host [srv 0 host]
        set redis_port [srv 0 port]
        set redis_log [srv 0 stdout]
        test "@string" {
            test "get" {
                assert_equal [$crdt get string_test]    [$redis get string_test]
            }

            test "set" {
                assert_equal [$crdt set string_test v]  [$redis set string_test v]
                assert_equal [$crdt get string_test]    [$redis get string_test]
                assert_equal [$crdt set string_test1 1] [$redis set string_test1 1] 
                assert_equal [$crdt get string_test1]   [$redis get string_test1]
            }

            test "del" {
                assert_equal [$crdt del string_test] [$redis del string_test]
                assert_equal [$crdt del string_test] [$redis del string_test]
            }

            test "setex" {
                assert_equal [$crdt setex string_test2 60 v] [$redis setex string_test2 60 v]
            }

            test "setnx" {
                assert_equal [$crdt setnx string_test3 v] [$redis setnx string_test3 v]
                assert_equal [$crdt setnx string_test3 v] [$redis setnx string_test3 v]
            }

            test "psetex" {
                assert_equal [$crdt psetex string_test4 60 v] [$redis psetex string_test4 60 v]
            }

            test "incrby" {
                assert_equal [$crdt incrby string_test5 1] [$redis incrby string_test5 1]
            }

            test "incrbyfloat" {
                assert_equal [$crdt incrbyfloat string_test6 1] [$redis incrbyfloat string_test6 1]
            }

            test "incr" {
                assert_equal [$crdt incr string_test7] [$redis incr string_test7]
            }

            test "decr" {
                assert_equal [$crdt decr string_test8] [$redis decr string_test8]
            }

            test "decrby" {
                assert_equal [$crdt decrby string_test9 1] [$redis decrby string_test9 1]
            }

            test "mset" {
                assert_equal [$crdt mset string_test10 v string_test11 v] [$redis mset string_test10 v string_test11 v]
                assert_equal [$crdt mget string_test10 string_test11] [$redis mget string_test10 string_test11]
            }

            test "msetnx" {
                assert_equal [$crdt msetnx string_test12 v string_test13 v] [$redis msetnx string_test12 v string_test13 v]
                assert_equal [$crdt msetnx string_test12 v string_test13 v] [$redis msetnx string_test12 v string_test13 v]
                assert_equal [$crdt mget string_test12 string_test13] [$redis mget string_test12 string_test13]
            }

        }

        test "@hash" {
            test "hget" {
                assert_equal [$crdt hget hash_test test] [$redis hget hash_test test]
            }

            test "hmget" {
                assert_equal [$crdt hmget hash_test test] [$redis hmget hash_test test]
                assert_equal [$crdt hmget hash_test test test2] [$redis hmget hash_test test test2]
            }

            test "hset" {
                assert_equal [$crdt hset hash_test k1 v] [$redis hset hash_test k1 v]
                assert_equal [$crdt hget hash_test k1]   [$redis hget hash_test k1]
                assert_equal [$crdt hget hash_test test] [$redis hget hash_test test]
            }

            test "hdel" {
                assert_equal [$crdt hdel hash_test k1 k2] [$redis hdel hash_test k1 k2]
                assert_equal [$crdt hdel hash_test k1 k2] [$redis hdel hash_test k1 k2]
            }

            test "del" {
                assert_equal [$crdt hset hash_test k1 v] [$redis hset hash_test k1 v]
                assert_equal [$crdt del hash_test] [$redis del hash_test]
                assert_equal [$crdt del hash_test] [$redis del hash_test]
            }

            test "hmset" {
                assert_equal [$crdt hmset hash_test1 k1 v k2 v2] [$redis hmset hash_test1 k1 v k2 v2]
                assert_equal [$crdt hmget hash_test1 k1 k2]   [$redis hmget hash_test1 k1 k2]
            }

            test "hsetnx" {
                assert_equal [$crdt hsetnx hash_test2 k1 v] [$redis hsetnx hash_test2 k1 v]
                assert_equal [$crdt hsetnx hash_test2 k1 v] [$redis hsetnx hash_test2 k1 v]
            }

            test "hkeys" {
                assert_equal [$crdt hkeys hash_test3] [$redis hkeys hash_test3]
                assert_equal [$crdt hset hash_test3 k v] [$redis hset hash_test3 k v]
                assert_equal [$crdt hkeys hash_test3] [$redis hkeys hash_test3]
                assert_equal [$crdt hset hash_test3 k1 v k2 v] [$redis hset hash_test3 k1 v k2 v]
                assert_equal [llength [$crdt hkeys hash_test3]]   [llength [$redis hkeys hash_test3]]
                
            }

            test "hvals" {
                 assert_equal [$crdt hvals hash_test4] [$redis hvals hash_test4]
                 assert_equal [$crdt hset hash_test4 k v] [$redis hset hash_test4 k v]
                 assert_equal [$crdt hvals hash_test4] [$redis hvals hash_test4]
            }

            test "hgetall" {
                assert_equal [$crdt hgetall hash_test5] [$redis hgetall hash_test5]
                assert_equal [$crdt hset hash_test5 k v k1 v] [$redis hset hash_test5 k v k1 v]
                assert_equal [llength [$crdt hgetall hash_test5]] [llength [$redis hgetall hash_test5]]
            }

            test "hlen" {
                assert_equal [$crdt hlen hash_test6] [$redis hlen hash_test6]
                assert_equal [$crdt hset hash_test6 k v k1 v] [$redis hset hash_test6 k v k1 v]
                assert_equal [$crdt hlen hash_test6] [$redis hlen hash_test6]
            }

            test "hscan" {
                assert_equal [$crdt hscan hash_test7 0] [$redis hscan hash_test7 0]
                assert_equal [$crdt hset hash_test7 k v k1 v] [$redis hset hash_test7 k v k1 v]
                assert_equal [llength [$crdt hscan hash_test7 0]] [llength [$redis hscan hash_test7 0]]
                assert_equal [llength [lindex [$crdt hscan hash_test7 0] 1]] [llength [lindex [$redis hscan hash_test7 0] 1]]
            }

            test "hexists" {
                assert_equal [$crdt hexists hash_test8 k] [$redis hexists hash_test8 k]
                assert_equal [$crdt hset hash_test8 k v k1 v] [$redis hset hash_test8 k v k1 v]
                assert_equal [$crdt hexists hash_test8 k] [$redis hexists hash_test8 k]
            }
            
        }

        test "@set" {
            test "sismember" {
                assert_equal [$crdt sismember set_test k] [$redis sismember set_test k] 
            }

            test "sadd" {
               assert_equal [$crdt sadd set_test k k1] [$redis sadd set_test k k1] 
               assert_equal [$crdt sismember set_test k] [$redis sismember set_test k] 
            }

            test "srem" {
                assert_equal [$crdt srem set_test k] [$redis srem set_test k] 
                assert_equal [$crdt srem set_test k] [$redis srem set_test k] 
            }

            test "del" {
                assert_equal [$crdt del set_test] [$redis del set_test]
                assert_equal [$crdt sadd set_test k k1] [$redis sadd set_test k k1] 
                assert_equal [$crdt del set_test] [$redis del set_test]
                assert_equal [$crdt del set_test] [$redis del set_test]
            }

            test "scard" {
                assert_equal [$crdt scard set_test1] [$redis scard set_test1]
                assert_equal [$crdt sadd set_test1 k k1] [$redis sadd set_test1 k k1] 
                assert_equal [$crdt scard set_test1] [$redis scard set_test1]
            }

            test "smembers" {
                assert_equal [$crdt smembers set_test3] [$redis smembers set_test3]
                assert_equal [$crdt sadd set_test3 k k1] [$redis sadd set_test3 k k1]
                assert_equal [llength [$crdt smembers set_test3]] [llength [$redis smembers set_test3]]
            }

            test "sunion" {
                assert_equal [$crdt sunion set_test4 set_test5] [$redis sunion set_test4 set_test5]
                assert_equal [$crdt sunion set_test5 set_test4] [$redis sunion set_test5 set_test4]
                assert_equal [$crdt sadd set_test4 k k1] [$redis sadd set_test4 k k1]
                assert_equal [llength [$crdt sunion set_test4 set_test5]] [llength [$redis sunion set_test4 set_test5]]
                assert_equal [llength [$crdt sunion set_test5 set_test4]] [llength [$redis sunion set_test5 set_test4]]
                assert_equal [$crdt sadd set_test5 k k1] [$redis sadd set_test5 k k1]
                assert_equal [llength [$crdt sunion set_test4 set_test5]] [llength [$redis sunion set_test4 set_test5]]
                assert_equal [llength [$crdt sunion set_test5 set_test4]] [llength [$redis sunion set_test5 set_test4]]
                assert_equal [$crdt sadd set_test5 k2 k3] [$redis sadd set_test5 k2 k3]
                assert_equal [llength [$crdt sunion set_test4 set_test5]] [llength [$redis sunion set_test4 set_test5]]
                assert_equal [llength [$crdt sunion set_test5 set_test4]] [llength [$redis sunion set_test5 set_test4]]
            }

            test "sscan" {
                assert_equal [$crdt sscan set_test6 0] [$redis sscan set_test6 0]
                assert_equal [$crdt sadd set_test6 k k1] [$redis sadd set_test6 k k1]
                assert_equal [llength [$crdt sscan set_test6 0]] [llength [$redis sscan set_test6 0]]
                assert_equal [llength [lindex [$crdt sscan set_test6 0] 1]] [llength [lindex [$redis sscan set_test6 0] 1]]
            }

            test "spop" {
                assert_equal [$crdt spop set_test7] [$redis spop set_test7]
                assert_equal [$crdt sadd set_test7 k] [$redis sadd set_test7 k]
                assert_equal [$crdt spop set_test7] [$redis spop set_test7]
                assert_equal [$crdt spop set_test7] [$redis spop set_test7]
            }
        }

        test "@zset" {
        
            test  "zadd" {
                assert_equal [$crdt zadd zadd_test 1 k] [$redis zadd zadd_test 1 k]  
            }

            test "zrem" {
                assert_equal [$crdt zrem zrem_test k] [$redis zrem zrem_test k]
                assert_equal [$crdt zadd zrem_test 1 k] [$redis zadd zrem_test 1 k]
                assert_equal [$crdt zrem zrem_test k] [$redis zrem zrem_test k]
                assert_equal [$crdt zrem zrem_test k] [$redis zrem zrem_test k]
            }

            test "zcard" {
                assert_equal [$crdt zcard zcard_test] [$redis zcard zcard_test]  
                assert_equal [$crdt zadd zcard_test 1 k] [$redis zadd zcard_test 1 k]  
                assert_equal [$crdt zcard zcard_test] [$redis zcard zcard_test] 
            }
            
            test "zscore" {
                assert_equal [$crdt zscore zscore_test k] [$redis zscore zscore_test k]  
                assert_equal [$crdt zadd zscore_test 1 k] [$redis zadd zscore_test 1 k] 
                assert_equal [$crdt zscore zscore_test k] [$redis zscore zscore_test k]   
            }

            test "zcount" {
                assert_equal [$crdt zcount zcount_test 0 -1] [$redis zcount zcount_test 0 -1]
                assert_equal [$crdt zadd zcount_test 1 k] [$redis zadd zcount_test 1 k]  
                assert_equal [$crdt zcount zcount_test 0 -1] [$redis zcount zcount_test 0 -1]
            }

            test "zrange" {
                assert_equal [$crdt zrange zrange_test 0 -1] [$redis zrange zrange_test 0 -1]
                assert_equal [$crdt zadd zrange_test 1 k] [$redis zadd zrange_test 1 k]  
                assert_equal [$crdt zrange zrange_test 0 -1] [$redis zrange zrange_test 0 -1]
            }

            test "zremrangebylex" {
                assert_equal [$crdt zremrangebylex zremrangebylex_test "\[a" "\[z"] [$redis zremrangebylex zremrangebylex_test "\[a" "\[z"]
                assert_equal [$crdt zadd zremrangebylex_test 1 k] [$redis zadd zremrangebylex_test 1 k]  
                assert_equal [$crdt zremrangebylex zremrangebylex_test "\[a" "\[z"] [$redis zremrangebylex zremrangebylex_test "\[a" "\[z"]
                assert_equal [$crdt zrange zremrangebylex_test 0 -1] [$redis zrange zremrangebylex_test 0 -1]
            }

            test "zrevrange" {
                assert_equal [$crdt zrevrange zrevrange_test 0 -1] [$redis zrevrange zrevrange_test 0 -1]
                assert_equal [$crdt zadd zrevrange_test 1 k] [$redis zadd zrevrange_test 1 k]  
                assert_equal [$crdt zrevrange zrevrange_test 0 -1] [$redis zrevrange zrevrange_test 0 -1]
            }

            test "zrangebyscore" {
                assert_equal [$crdt zrangebyscore zrangebyscore_test 0 10] [$redis zrangebyscore zrangebyscore_test 0 10]
                assert_equal [$crdt zadd zrangebyscore_test 1 k] [$redis zadd zrangebyscore_test 1 k]  
                assert_equal [$crdt zrangebyscore zrangebyscore_test 0 10] [$redis zrangebyscore zrangebyscore_test 0 10]
            }

            test "zrevrangebyscore" {
                assert_equal [$crdt zrevrangebyscore zrevrangebyscore_test 0 -1] [$redis zrevrangebyscore zrevrangebyscore_test 0 -1]
                assert_equal [$crdt zadd zrevrangebyscore_test 1 k] [$redis zadd zrevrangebyscore_test 1 k]  
                assert_equal [$crdt zrevrangebyscore zrevrangebyscore_test 0 -1] [$redis zrevrangebyscore zrevrangebyscore_test 0 -1]
            }

            test "zrank" {
                assert_equal [$crdt zrank zrank_test k] [$redis zrank zrank_test k]
                assert_equal [$crdt zadd zrank_test 1 k] [$redis zadd zrank_test 1 k]  
                assert_equal [$crdt zrank zrank_test k] [$redis zrank zrank_test k] 
            }

            test "zrevrank" {
                assert_equal [$crdt zrevrank zrevrank_test k] [$redis zrevrank zrevrank_test k]
                assert_equal [$crdt zadd zrevrank_test 1 k] [$redis zadd zrevrank_test 1 k]  
                assert_equal [$crdt zrevrank zrevrank_test k] [$redis zrevrank zrevrank_test k] 
            }

            test "zremrangebyrank" {
                assert_equal [$crdt zremrangebyrank zremrangebyrank_test 0 -1] [$redis zremrangebyrank zremrangebyrank_test 0 -1]
                assert_equal [$crdt zadd zremrangebyrank_test 1 k] [$redis zadd zremrangebyrank_test 1 k]  
                assert_equal [$crdt zremrangebyrank zremrangebyrank_test 0 -1] [$redis zremrangebyrank zremrangebyrank_test 0 -1]
            }

            test "zremrangebyscore" {
                assert_equal [$crdt zremrangebyscore zremrangebyscore_test 0 -1] [$redis zremrangebyscore zremrangebyscore_test 0 -1]
                assert_equal [$crdt zadd zremrangebyscore_test 1 k] [$redis zadd zremrangebyrank_test 1 k]  
                assert_equal [$crdt zremrangebyscore zremrangebyscore_test 0 -1] [$redis zremrangebyscore zremrangebyscore_test 0 -1]
            }

            test "zrangebylex" {
                assert_equal [$crdt zrangebylex zrangebylex_test "\[a" "\[z"] [$redis zrangebylex zrangebylex_test "\[a" "\[z"]
                assert_equal [$crdt zadd zrangebylex_test 1 k] [$redis zadd zrangebylex_test 1 k] 
                assert_equal [$crdt zrangebylex zrangebylex_test "\[a" "\[z"] [$redis zrangebylex zrangebylex_test "\[a" "\[z"]
            }

            test "zlexcount" {
                assert_equal [$crdt zlexcount zlexcount_test "\[a" "\[z"] [$redis zlexcount zlexcount_test "\[a" "\[z"]
                assert_equal [$crdt zadd zrangebylex_test 1 k] [$redis zadd zrangebylex_test 1 k] 
                assert_equal [$crdt zlexcount zlexcount_test "\[a" "\[z"] [$redis zlexcount zlexcount_test "\[a" "\[z"]
            }

            test "zrevrangebylex" {
                assert_equal [$crdt zrevrangebylex zrevrangebylex_test "\[a" "\[z"] [$redis zrevrangebylex zrevrangebylex_test "\[a" "\[z"]
                assert_equal [$crdt zadd zrevrangebylex_test 1 k] [$redis zadd zrevrangebylex_test 1 k] 
                assert_equal [$crdt zrevrangebylex zrevrangebylex_test "\[a" "\[z"] [$redis zrevrangebylex zrevrangebylex_test "\[a" "\[z"]
            }
            
            test "zscan" {
                assert_equal [$crdt zscan zscan_test 0] [$redis zscan zscan_test 0]
                assert_equal [$crdt zadd zscan_test 1 k] [$redis zadd zscan_test 1 k] 
                assert_equal [$crdt zscan zscan_test 0] [$redis zscan zscan_test 0]
            }
        }
    }
}

