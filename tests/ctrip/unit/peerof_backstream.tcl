proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}
proc run_test_all_api {c} {
    test "kv" {
        $c set mykv1 a 
        $c set mykv2 b 
        $c del mykv2 
    }
    test "counter" {
        $c set mycounter1 1 
        $c set mycounter2 1
        $c incrby mycounter2 1 
        $c set mycounter3 1
        $c incrbyfloat mycounter3 1.1
        $c incrby mycounter4 1
        $c incrbyfloat mycounter5 1.1
        $c set mycounter6 1
        $c del mycounter6 
        $c incrby mycounter7 1
        $c del mycounter7
        $c incrbyfloat mycounter8 1.1
        $c del mycounter8
    }
    test "hash" {
        $c hset myhash1 k v 
        $c hset myhash2 k v k2 v2 
        $c hdel myhash2 k 
        $c hset myhash3 k v
        $c del  myhash3 
    }
    test "set" {
        $c sadd myset1 a 
        $c sadd myset2 a b 
        $c srem myset2 a 
        $c sadd myset3 a
        $c del myset3
    }
    test "zset" {
        $c zadd myzset1 1.1 a 
        $c zincrby myzset2 1.1 a 
        $c zadd myzset3 1.1 a 
        $c zincrby myzset3 1.1 a 
        $c zadd myzset4 1.1 a 2.2 b 
        $c zrem myzset4 a 
        $c zincrby myzset5 1.1 a 
        $c zrem myzset5 a 
        $c zadd myzset6 1.1 a
        $c del myzset6
        $c zincrby myzset7 1.1 a
        $c del myzset7
    }
}
proc close_all_gc {c} {
    $c crdt.debug_gc register 0
    $c crdt.debug_gc counter 0
    $c crdt.debug_gc hash 0
    $c crdt.debug_gc set 0
    $c crdt.debug_gc zset 0
}
proc run_check_all_api {c1 c2} {
    test "register" {
        assert_equal [$c1 crdt.datainfo mykv1] [$c2 crdt.datainfo mykv1]
        assert_equal [$c1 crdt.datainfo mykv2] [$c2 crdt.datainfo mykv2]
    }
    
    test "counter" {
        assert_equal [$c1 crdt.datainfo mycounter1] [$c2 crdt.datainfo mycounter1] 
        assert_equal [$c1 crdt.datainfo mycounter2] [$c2 crdt.datainfo mycounter2] 
        assert_equal [$c1 crdt.datainfo mycounter3] [$c2 crdt.datainfo mycounter3] 
        assert_equal [$c1 crdt.datainfo mycounter4] [$c2 crdt.datainfo mycounter4] 
        assert_equal [$c1 crdt.datainfo mycounter5] [$c2 crdt.datainfo mycounter5] 
        assert_equal [$c1 crdt.datainfo mycounter6] [$c2 crdt.datainfo mycounter6] 
        assert_equal [$c1 crdt.datainfo mycounter7] [$c2 crdt.datainfo mycounter7] 
        assert_equal [$c1 crdt.datainfo mycounter8] [$c2 crdt.datainfo mycounter8] 
    }
    test "hash" {
        # assert_equal [$c1 crdt.datainfo myhash1] [$c2 crdt.datainfo myhash1]
        assert_equal [$c1 crdt.datainfo myhash2] [$c2 crdt.datainfo myhash2]
        # assert_equal [$c1 crdt.datainfo myhash3] [$c2 crdt.datainfo myhash3]
    }
    test "set" {
        assert_equal [$c1 crdt.datainfo myset1]  [$c2 crdt.datainfo myset1]
        assert_equal [$c1 crdt.datainfo myset2]  [$c2 crdt.datainfo myset2]
        assert_equal [$c1 crdt.datainfo myset3]  [$c2 crdt.datainfo myset3]
    }
    test "zset" {
        assert_equal [$c1 crdt.datainfo myzset1] [$c2 crdt.datainfo myzset1]
        assert_equal [$c1 crdt.datainfo myzset2] [$c2 crdt.datainfo myzset2]
        assert_equal [$c1 crdt.datainfo myzset3] [$c2 crdt.datainfo myzset3]
        assert_equal [$c1 crdt.datainfo myzset4] [$c2 crdt.datainfo myzset4]
        assert_equal [$c1 crdt.datainfo myzset5] [$c2 crdt.datainfo myzset5]
        assert_equal [$c1 crdt.datainfo myzset6] [$c2 crdt.datainfo myzset6]
        assert_equal [$c1 crdt.datainfo myzset7] [$c2 crdt.datainfo myzset7]
    }
}

start_server {tags {"backstreaming, can't  write and read"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    set master_config [srv 0 config_file]
    start_server {tags {"backstreaming, can't  write and read"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        test "backstreaming, can't  write and read" {
            $master peerof $peer_gid $peer_host $peer_port backstream 0 
            assert_match "*peerof 2 127.0.0.1*" [read_file $master_config]
            catch {$master set k v} error 
            assert_match "*LOADING Redis is loading the dataset in memory*" $error 
            catch {$master get k} error
            assert_match "*LOADING Redis is loading the dataset in memory*" $error
            wait_for_peer_sync $master
            after 1000
            $master set k v 
            assert_equal [$master get k] v
        }
        

        
    }
}


start_server {tags {"backstream status, peer no one"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"backstream status, peer no one"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        test "backstreaming, peer no one" {
            $master peerof $peer_gid $peer_host $peer_port backstream 0 
            catch {$master set k v} error 
            assert_match "*LOADING Redis is loading the dataset in memory*" $error 
            catch {$master get k} error
            assert_match "*LOADING Redis is loading the dataset in memory*" $error
            $master peerof $peer_gid no one 
            $master set k v 
            assert_equal [$master get k] v
            
        }
        test "again peerof is ok" {
            after 1000
            $peer set k v1
            $master peerof $peer_gid $peer_host $peer_port
            wait_for_peer_sync $master 
            assert_equal [$master get k] v1
        }
    }
}

start_server {tags {"backstream, can't  write and read"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"backstream, can't  write and read"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        test "when peerof backstream after  peerof " {
            $peer crdt.set key v1 1 1000 1:1 
            $master peerof 2 127.0.0.1 0 backstream 0
            $master peerof $peer_gid $peer_host $peer_port
            wait_for_peer_sync $master 
            assert_equal [$master get key] v1
        }
    }
}

start_server {tags {"peerof backstream 1 + peerof backstream 2"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"peerof backstream 1 + peerof backstream 2"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        test "peerof backstream 1 + peerof backstream 2" {
            $peer crdt.set key v1 1 1000 1:1 
            $peer crdt.set key2 v2 1 1000 1:2
            $peer crdt.set key3 v3 1 1000 1:3
            $master peerof $peer_gid $peer_host $peer_port backstream 0
            $master peerof $peer_gid $peer_host $peer_port backstream 1
            catch {$master set test1 a} error 
            assert_match "*LOADING Redis is loading the dataset in memory*" $error 
            wait_for_peer_sync $master 
            # puts [print_log_file $peer_stdout]
            assert_equal [$master get key] {}
            assert_equal [$master get key2] v2
            assert_equal [$master get key3] v3
        }
    }
}


start_server {tags {"peerof + peerof backstream"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"peerof + peerof backstream"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        test "when peerof after  peerof backstream" {
            $peer crdt.set key v1 1 1000 1:1 
            $master peerof $peer_gid $peer_host $peer_port
            wait_for_peer_sync $master 
            assert_equal [$master get key] {}
            $master peerof $peer_gid $peer_host $peer_port backstream 0
            catch {$master set test1 a} error 
            assert_match "*LOADING Redis is loading the dataset in memory*" $error 
            wait_for_peer_sync $master 
            # puts [print_log_file $master_stdout]
            assert_equal [$master get key] v1
            
        }
    }
}

start_server {tags {"peerof + peerof backstream"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"peerof + peerof backstream"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        test "when peerof after  peerof backstream" {
            $peer crdt.set key v1 1 1000 1:1 
            $master peerof $peer_gid $peer_host $peer_port
            wait_for_peer_sync $master 
            assert_equal [$master get key] {}
            $master peerof $peer_gid $peer_host $peer_port backstream 0
            catch {$master set test1 a} error 
            assert_match "*LOADING Redis is loading the dataset in memory*" $error 
            wait_for_peer_sync $master 
            # puts [print_log_file $master_stdout]
            assert_equal [$master get key] v1
            
        }
    }
}

start_server {tags {"peerof backstream + slave can't read"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    $master config set repl-diskless-sync-delay 1
    
    start_server {tags {"peerof + peerof backstream"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        $peer crdt.set key v1 1 1000 1:1 
        start_server {tags {"slave"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_stderr [srv 0 stderr]
            set slave_config [srv 0 config_file]
            $slave config set repl-diskless-sync-delay 1
            test "when peerof after  peerof backstream" {
                $slave slaveof $master_host $master_port
                wait_for_sync $slave 
                $master peerof $peer_gid $peer_host $peer_port backstream 0
                after 1000
                catch {$slave get k} error
                assert_match "*LOADING Redis is loading the dataset in memory*" $error 
                assert_match "*peerof 2 127.0.0.1*" [read_file $slave_config]
                $slave slaveof no one 
                $master slaveof $slave_host $slave_port 
                wait_for_peer_sync $slave 
                # puts [print_log_file $peer_stdout]
                assert_equal [$slave get key] v1
                wait_for_sync $master 
                assert_equal [$master get key] v1
                $master slaveof no one 
                assert_equal [$master get key] v1
                
            }
        }
    }
}


start_server {tags {"peerof backstream + slave can't read"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    $master config set repl-diskless-sync-delay 1
    
    start_server {tags {"peerof + peerof backstream"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        $peer crdt.set key v1 1 1000 1:1 
        start_server {tags {"slave"} overrides {crdt-gid 3} config {crdt.conf} module {crdt.so} } {
            set peer2 [srv 0 client]
            set peer2_gid 3
            set peer2_host [srv 0 host]
            set peer2_port [srv 0 port]
            set peer2_stdout [srv 0 stdout]
            set peer2_stderr [srv 0 stderr]
            set peer2_config [srv 0 config_file]
            test "when peerof A after , peerof backstream B , A set k v" {
                $master peerof $peer_gid $peer_host $peer_port
                for {set i 0} {$i < 100000} {incr i} {
                    $peer2 set $i $i 
                }
                wait_for_peer_sync $master 
                close_all_gc $master 
                $master peerof $peer2_gid $peer2_host $peer2_port backstream 0
                close_all_gc $peer 
                run_test_all_api $peer 
                wait_for_peers_sync 1 $master 
                run_check_all_api $peer $master
            }
        }
    }
}