proc print_file_matches {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
start_server {tags {"multi"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}} {
    set gid 1
    test {MUTLI / EXEC basics} {
        r del h
        r hset h a 1
        r hset h b 1
        r hset h c 1
        r multi
        set v1 [lsort [r hkeys h]]
        set v2 [r ping]
        set v3 [r exec]
        list $v1 $v2 $v3
    } {QUEUED QUEUED {{c b a} PONG}}

    test {DISCARD} {
        r del h
        r hset h a 1
        r hset h b 1
        r hset h c 1
        r multi
        set v1 [r del h]
        set v2 [r discard]
        set v3  [r hkeys h]
        list $v1 $v2 $v3
    } {QUEUED OK {c b a}}

    test {Nested MULTI are not allowed} {
        set err {}
        r multi
        catch {[r multi]} err
        r exec
        set _ $err
    } {*ERR MULTI*}

    test {MULTI where commands alter argc/argv} {
        r hset h1 k v
        r multi
        r hdel h1 k
        list [r exec] [r exists h1]
    } {1 0}

    test {WATCH inside MULTI is not allowed} {
        set err {}
        r multi
        catch {[r watch x]} err
        r exec
        set _ $err
    } {*ERR WATCH*}

    test {EXEC fails if there are errors while queueing commands #1} {
        r del foo1 foo2
        r multi
        r set foo1 bar1
        catch {r non-existing-command}
        r set foo2 bar2
        catch {r exec} e
        assert_match {EXECABORT*} $e
        list [r exists foo1] [r exists foo2]
    } {0 0}

    test {EXEC fails if there are errors while queueing commands #2} {
        set rd [redis_deferring_client]
        r del foo1 foo2
        r multi
        r set foo1 bar1
        $rd config set maxmemory 1
        assert  {[$rd read] eq {OK}}
        catch {r lpush mylist myvalue}
        $rd config set maxmemory 0
        assert  {[$rd read] eq {OK}}
        r set foo2 bar2
        catch {r exec} e
        assert_match {EXECABORT*} $e
        $rd close
        list [r exists foo1] [r exists foo2]
    } {0 0}

    test {If EXEC aborts, the client MULTI state is cleared} {
        r del foo1 foo2
        r multi
        r set foo1 bar1
        catch {r non-existing-command}
        r set foo2 bar2
        catch {r exec} e
        assert_match {EXECABORT*} $e
        r ping
    } {PONG}

    test {EXEC works on WATCHed key not modified} {
        r watch x y z
        r watch k
        r multi
        r ping
        r exec
    } {PONG}

    test {EXEC fail on WATCHed key modified (1 key of 1 watched)} {
        r set x 30
        r watch x
        r set x 40
        r multi
        r ping
        r exec
    } {}

    test {EXEC fail on WATCHed key (mset) modified (1 key of 1 watched)} {
        r set x 30
        r watch x
        r mset x 40
        r multi
        r ping
        r exec
    } {}

    test {EXEC fail on WATCHed key (mset) modified (1 key of 1 watched)} {
        r set x a30
        r watch x
        r mset x a40
        r multi
        r ping
        r exec
    } {}

    test {EXEC fail on WATCHed key modified (1 key of 5 watched)} {
        r set x 30
        r watch a b x k z
        r set x 40
        r multi
        r ping
        r exec
    } {}

    # test {EXEC fail on WATCHed key modified by SORT with STORE even if the result is empty} {
    #     r flushdb
    #     r lpush foo bar
    #     r watch foo
    #     r sort emptylist store foo
    #     r multi
    #     r ping
    #     r exec
    # } {}

    test {After successful EXEC key is no longer watched} {
        r set x 30
        r watch x
        r multi
        r ping
        r exec
        r set x 40
        r multi
        r ping
        r exec
    } {PONG}

    test {After failed EXEC key is no longer watched} {
        r set x 30
        r watch x
        r set x 40
        r multi
        r ping
        r exec
        r set x 40
        r multi
        r ping
        r exec
    } {PONG}

    test {It is possible to UNWATCH} {
        r set x 30
        r watch x
        r set x 40
        r unwatch
        r multi
        r ping
        r exec
    } {PONG}

    test {UNWATCH when there is nothing watched works as expected} {
        r unwatch
    } {OK}

    test {FLUSHALL is able to touch the watched keys} {
        r set x 30
        r watch x
        r flushall
        r multi
        r ping
        r exec
    } {}

    test {FLUSHALL does not touch non affected keys} {
        r del x
        r watch x
        r flushall
        r multi
        r ping
        r exec
    } {PONG}

    test {FLUSHDB is able to touch the watched keys} {
        r set x 30
        r watch x
        r flushdb
        r multi
        r ping
        r exec
    } {}

    test {FLUSHDB does not touch non affected keys} {
        r del x
        r watch x
        r flushdb
        r multi
        r ping
        r exec
    } {PONG}

    test {WATCH is able to remember the DB a key belongs to} {
        r select 5
        r set x 30
        r watch x
        r select 1
        r set x 10
        r select 5
        r multi
        r ping
        set res [r exec]
        # Restore original DB
        r select 9
        set res
    } {PONG}

    test {WATCH will consider touched keys target of EXPIRE} {
        r del x
        r set x foo
        r watch x
        r expire x 10
        r multi
        r ping
        r exec
    } {}

    test {WATCH will not consider touched expired keys} {
        r del x
        r set x foo
        r expire y 1
        r watch y
        after 1100
        assert_equal [r get y] {}
        r multi
        r ping
        r exec
    } {PONG}

    test {DISCARD should clear the WATCH dirty flag on the client} {
        r watch x
        r set x 10
        r multi
        r discard
        r multi
        r set x 11
        r exec
    } {OK}

    test {DISCARD should UNWATCH all the keys} {
        r watch x
        r set x 10
        r multi
        r discard
        r set x 10
        r multi
        r set x 11
        r exec
    } {OK}

    test {MULTI / EXEC is propagated correctly (single write command)} {
        # set repl [attach_to_replication_stream]
        set repl [attach_to_crdt_replication_stream  $gid [srv 0 host] [srv 0 port]]
        r multi
        r set foo bar
        r exec
        assert_replication_stream $repl {
            {crdt.select 1 9}
            {crdt.multi 1}
            {crdt.set foo bar 1 * * -1}
            {crdt.exec 1}
        }
        close_replication_stream $repl
    }

    test {MULTI / EXEC is propagated correctly (empty transaction)} {
        set repl [attach_to_crdt_replication_stream  $gid [srv 0 host] [srv 0 port]]
        r multi
        r exec
        r set foo bar
        assert_replication_stream $repl {
            {crdt.select 1 *}
            {crdt.set foo bar 1 * * -1}
        }
        close_replication_stream $repl
    }

    test {MULTI / EXEC is propagated correctly (read-only commands)} {
        r set foo value1
        set repl [attach_to_crdt_replication_stream  $gid [srv 0 host] [srv 0 port]]
        r multi
        r get foo
        r exec
        r set foo value2
        assert_replication_stream $repl {
            {crdt.select 1 *}
            {crdt.set foo value2 1 * * -1}
        }
        close_replication_stream $repl
    }

    test {MULTI / EXEC is propagated correctly (write command, no effect)} {
        r del bar foo bar
        set repl [attach_to_crdt_replication_stream  $gid [srv 0 host] [srv 0 port]]
        r multi
        r del foo
        r exec
        assert_replication_stream $repl {
            {crdt.select 1 *}
            {crdt.multi 1}
            {crdt.exec 1}
        }
        close_replication_stream $repl
    }
}


proc get_info_replication_attr_value {client type attr} {
    set info [$client $type replication]
    set regstr [format "\r\n%s:(.*?)\r\n" $attr]
    regexp $regstr $info match value 
    set _ $value
}

proc crdt_repl { client property } {
    set info [ $client crdt.info replication]
    if {[regexp "\r\n$property:(.*?)\r\n" $info _ value]} {
        set _ $value
    }
}
proc wait { client index type log}  {
    set retry 500
    set match_str ""
    append match_str "*slave" $index ":*state=online*"
    while {$retry} {
        set info [ $client $type replication ]
        if {[string match $match_str $info]} {
            break
        } else {
            assert_equal [$client ping] PONG
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        # error "assertion: Master-Slave not correctly synchronized"
        assert_equal [$client ping] PONG
        print_file_matches $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}
proc wait_script {script err} {
    set retry 50
    while {$retry} {
        set conditionCmd [list expr $script] 
        if {[uplevel 1 $conditionCmd]} {
            break
        } else {
            incr retry -1
            after 100
        }
    }
    if {$retry == 0} {
        catch [uplevel 1 $err] error
    }
}

proc test_write_data_offset {CheckMasterSlave master slave slave_slave peer peer_slave} {
    set delay_time 2000
    proc check {type CheckMasterSlave m ms mss p ps } {
        $m debug set-crdt-ovc 0
        $p debug set-crdt-ovc 0
        if {$CheckMasterSlave} {
            set mv [get_info_replication_attr_value $m crdt.info master_repl_offset]
            wait_script {$mv == [get_info_replication_attr_value $ms crdt.info master_repl_offset]} {
                puts $mv
                puts [get_info_replication_attr_value $ms crdt.info master_repl_offset]
                fail [format "%s master and slave offset error" $type]
            }
            wait_script  {$mv == [get_info_replication_attr_value $mss crdt.info master_repl_offset]} {
                puts $mv
                puts [get_info_replication_attr_value $mss crdt.info master_repl_offset]
                fail [format "%s master and slave-slave offset error " $type]
            }
        } else {
            set mv [get_info_replication_attr_value $ms crdt.info master_repl_offset]
            wait_script  {$mv == [get_info_replication_attr_value $mss crdt.info master_repl_offset]} {
                puts $mv
                puts [get_info_replication_attr_value $mss crdt.info master_repl_offset]
                fail [format "%s slave and slave-slave offset error " $type]
            }
        }
        
        set pv [get_info_replication_attr_value $p crdt.info master_repl_offset]
        wait_script {$pv == [get_info_replication_attr_value $ps crdt.info master_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $ps crdt.info master_repl_offset]
            fail [format "%s master and peer-slave offset error" $type]
        }
        wait_script  { $pv == [get_info_replication_attr_value $m crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $m crdt.info peer0_repl_offset]
            fail [format "%s master and peer-slave offset error" $type]
        }
        wait_script { $pv == [get_info_replication_attr_value $ms crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $ms crdt.info peer0_repl_offset]
            fail [format "%s peer and peer-slave offset error" $type]
        }
        wait_script { $pv == [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]} {
            puts $pv
            puts [get_info_replication_attr_value $mss crdt.info peer0_repl_offset]
            fail [format "<%s>,slave-slave and peer-slave offset error" $type]
        }
        $m debug set-crdt-ovc 1
        $p debug set-crdt-ovc 1
    }
    
    check "before write" $CheckMasterSlave $master $slave $slave_slave $peer $peer_slave
    $peer set k v
    after $delay_time
    if {[$peer_slave get k] != {v}} {
        puts [$peer_slave get k]
        fail "get k != v"
    }
    
    check "set k v" $CheckMasterSlave $master $slave $slave_slave $peer $peer_slave
    # print_file_matches $peer_slave_log
    $peer del k
    check "del k " $CheckMasterSlave $master $slave $slave_slave $peer $peer_slave
    # print_file_matches $slave_log
    $peer hset h k v k1 v2

    check "hset-1 h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    $peer hdel h k k1 

    check "hdel h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    $peer hset h k v k1 v1

    check "hset-2 h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    $peer del h 
    check "del h" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave

    $peer mset k v2 k1 v1
    check "mset" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave 

    $peer setex k1 2 v0
    check "setex k1" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave

    $peer set k v1 
    $peer expire k 1
    after $delay_time
    assert_equal [$master get k] {}
    check "expire k" $CheckMasterSlave  $master $slave $slave_slave $peer $peer_slave
    
    
}
proc test_slave_peer {slave peer log} {
    set before_full_num [crdt_stats $peer sync_full]
    set before_sync_partial_ok [crdt_stats $peer sync_partial_ok]
    $slave slaveof no one 
    wait $peer 1 crdt.info $log
    assert_equal [crdt_stats $peer sync_full] $before_full_num
    # print_file_matches $log
    assert_equal [crdt_stats $peer sync_partial_ok] [expr $before_sync_partial_ok + 1]
}



proc slave-peer-offset {type arrange} {
    start_server {tags {"repl"} overrides {crdt-gid 3} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_log [srv 0 stdout]
        set peer2_gid 3
        $peer2 config set repl-diskless-sync yes
        $peer2 config set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-backlog-size 1M
        start_server {overrides {crdt-gid 1} module {crdt.so}} {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            set slave_gid 1
            $slave config set repl-diskless-sync yes
            $slave config set repl-diskless-sync-delay 1
            $slave config crdt.set repl-diskless-sync-delay 1
            $slave config crdt.set repl-backlog-size 1M
            start_server {overrides {crdt-gid 1} module {crdt.so}} {
                set slave_slave [srv 0 client]
                set slave_slave_host [srv 0 host]
                set slave_slave_port [srv 0 port]
                set slave_slave_log [srv 0 stdout]
                set slave_slave_gid 1
                $slave_slave config set repl-diskless-sync yes
                $slave_slave config set repl-diskless-sync-delay 1
                $slave_slave config crdt.set repl-diskless-sync-delay 1
                $slave_slave config crdt.set repl-backlog-size 1M
                start_server {overrides {crdt-gid 1} module {crdt.so}} {
                    set master [srv 0 client]
                    set master_host [srv 0 host]
                    set master_port [srv 0 port]
                    set master_log [srv 0 stdout]
                    set master_gid 1
                    $master config set repl-diskless-sync yes
                    $master config set repl-diskless-sync-delay 1
                    $master config crdt.set repl-diskless-sync-delay 1
                    $master config crdt.set repl-backlog-size 1M
                    start_server {tags {"repl"} overrides {crdt-gid 2} module {crdt.so} } {
                        set peer_slave [srv 0 client]
                        set peer_slave_host [srv 0 host]
                        set peer_slave_port [srv 0 port]
                        set peer_slave_log [srv 0 stdout]
                        set peer_slave_gid 2
                        $peer_slave config set repl-diskless-sync yes
                        $peer_slave config set repl-diskless-sync-delay 1
                        $peer_slave config crdt.set repl-diskless-sync-delay 1
                        $peer_slave config crdt.set repl-backlog-size 1M
                        start_server {overrides {crdt-gid 2} module {crdt.so}} {
                            set peer [srv 0 client]
                            set peer_host [srv 0 host]
                            set peer_port [srv 0 port]
                            set peer_log [srv 0 stdout]
                            set peer_gid 2
                            $peer config set repl-diskless-sync yes
                            $peer config set repl-diskless-sync-delay 1
                            $peer config crdt.set repl-diskless-sync-delay 1
                            $peer config crdt.set repl-backlog-size 1M
                            # test $type {
                                if {[catch [uplevel 0 $arrange ] result]} {
                                    puts $result
                                }
                            # }
                        }
                    }
                }
            } 
        }
    }
}


slave-peer-offset "maste-slave" {
    $slave slaveof $master_host $master_port 
    $peer peerof $master_gid $master_host $master_port
    $master peerof $peer_gid $peer_host $peer_port
    $slave_slave slaveof $slave_host $slave_port
    $peer_slave slaveof $peer_host $peer_port
    wait_for_sync $slave
    wait_for_peer_sync $peer
    wait_for_sync $slave_slave
    wait_for_sync $peer_slave
    set master_repl [attach_to_crdt_replication_stream $master_gid $master_host $master_port]
    set slave_repl [attach_to_crdt_replication_stream $slave_gid $slave_host $slave_port]
    set peer_repl [attach_to_crdt_replication_stream $peer_gid $peer_host $peer_port]
    set slave_slave_repl [attach_to_crdt_replication_stream $slave_slave_gid $slave_slave_host $slave_slave_port]
    set peer_slave_repl [attach_to_crdt_replication_stream $peer_slave_gid $peer_slave_host $peer_slave_port]
    
    test "all api" {
        $master multi
        $master set k v 
        $master hset h k v
        $master del k 
        $master hdel h k 
        $master hset h1 k v
        $master del h1
        $master set k1 v 
        $master expire k1 1000
        $master setex k2 1000 v 
        $master mset k3 v1 k4 v2
        $master exec 
        after 2000
        assert_equal [$master get k] [$slave get k] 
        assert_equal [$master get k] [$slave_slave get k]
        assert_equal [$master get k] [$peer get k]
        assert_equal [$master get k] [$peer_slave get k]
        assert_replication_stream $slave_repl {
            {crdt.select 1 *}
            {crdt.multi 1}
            {crdt.set k v 1 * {1:1;2:0} -1}
            {crdt.hset h 1 * {1:2;2:0} 2 k v}
            {crdt.del_reg k 1 * {1:3;2:0}}
            {crdt.rem_hash h 1 * {1:4;2:0} k}
            {crdt.hset h1 1 * {1:5;2:0} 2 k v}
            {crdt.del_hash h1 1 * {1:6;2:0} {1:6;2:0}}
            {crdt.set k1 v 1 * {1:7;2:0} -1}
            {crdt.expire k1 1 * * 0}
            {crdt.set k2 v 1 * {1:8;2:0} *}
            {crdt.mset 1 * k3 v1 {1:9;2:0} k4 v2 {1:9;2:0}}
            {crdt.exec 1}
        }
        assert_replication_stream $slave_slave_repl {
            {crdt.select 1 *}
            {crdt.multi 1}
            {crdt.set k v 1 * {1:1;2:0} -1}
            {crdt.hset h 1 * {1:2;2:0} 2 k v}
            {crdt.del_reg k 1 * {1:3;2:0}}
            {crdt.rem_hash h 1 * {1:4;2:0} k}
            {crdt.hset h1 1 * {1:5;2:0} 2 k v}
            {crdt.del_hash h1 1 * {1:6;2:0} {1:6;2:0}}
            {crdt.set k1 v 1 * {1:7;2:0} -1}
            {crdt.expire k1 1 * * 0}
            {crdt.set k2 v 1 * {1:8;2:0} *}
            {crdt.mset 1 * k3 v1 {1:9;2:0} k4 v2 {1:9;2:0}}
            {crdt.exec 1}
        }
        assert_replication_stream $peer_repl  {
            {select 0}
            {crdt.select 1 *}
            {crdt.multi 1}
            {crdt.set k v 1 * {1:1;2:0} -1}
            {crdt.hset h 1 * {1:2;2:0} 2 k v}
            {crdt.del_reg k 1 * {1:3;2:0}}
            {crdt.rem_hash h 1 * {1:4;2:0} k}
            {crdt.hset h1 1 * {1:5;2:0} 2 k v}
            {crdt.del_hash h1 1 * {1:6;2:0} {1:6;2:0}}
            {crdt.set k1 v 1 * {1:7;2:0} -1}
            {crdt.expire k1 1 * * 0}
            {crdt.set k2 v 1 * {1:8;2:0} *}
            {crdt.mset 1 * k3 v1 {1:9;2:0} k4 v2 {1:9;2:0}}
            {crdt.exec 1}
        }
        assert_replication_stream $peer_slave_repl  {
            {select 0}
            {crdt.select 1 *}
            {crdt.multi 1}
            {crdt.set k v 1 * {1:1;2:0} -1}
            {crdt.hset h 1 * {1:2;2:0} 2 k v}
            {crdt.del_reg k 1 * {1:3;2:0}}
            {crdt.rem_hash h 1 * {1:4;2:0} k}
            {crdt.hset h1 1 * {1:5;2:0} 2 k v}
            {crdt.del_hash h1 1 * {1:6;2:0} {1:6;2:0}}
            {crdt.set k1 v 1 * {1:7;2:0} -1}
            {crdt.expire k1 1 * * 0}
            {crdt.set k2 v 1 * {1:8;2:0} *}
            {crdt.mset 1 * k3 v1 {1:9;2:0} k4 v2 {1:9;2:0}}
            {crdt.exec 1}
        }

        

        check_peer_info $master $peer 0
        check_peer_info $master $peer_slave 0
        assert_equal [crdt_repl $master master_repl_offset] [crdt_repl $slave master_repl_offset]
        assert_equal [crdt_repl $master master_repl_offset] [crdt_repl $slave_slave master_repl_offset]
        assert_equal [crdt_repl $peer master_repl_offset] [crdt_repl $peer_slave master_repl_offset]
    }
    test "master and peer simultaneously exec" {
        
        $master multi
        $peer multi
        $master select 0
        $master set k10 v1 
        $peer select 1
        $peer set k10 v2 
        after 1000
        $peer hset h10 k v2 
        
        $master hset h10 k v1
        while { [read_from_replication_stream $slave_repl] != {} } {
            puts "clean slave_repl"
        }
        while { [read_from_replication_stream $slave_slave_repl] != {} } {
            puts "clean slave_slave_repl"
        }
        while { [read_from_replication_stream $peer_repl] != {} } {
            puts "clean peer_repl"
        }
        while { [read_from_replication_stream $peer_slave_repl] != {} } {
            puts "clean peer_slave_repl"
        }
        $peer exec 
        $master exec
        after 1000
        
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        # puts [read_from_replication_stream $slave_slave_repl]
        print_file_matches $master_log
        assert_replication_stream $slave_repl  {
            {select 9}
            {crdt.multi 2}
            {crdt.select 2 1}
            {crdt.set k10 v2 2 * {1:9;2:1} -1}
            {crdt.hset h10 2 * {1:9;2:2} 2 k v2}
            {crdt.exec 2}
            {crdt.multi 1}
            {crdt.select 1 0}
            {crdt.set k10 v1 1 * {1:10;2:2} -1}
            {crdt.hset h10 1 * {1:11;2:2} 2 k v1}
            {crdt.exec 1}
        }
        
        # assert_replication_stream $slave_slave_repl  {
        #     {select 9}
        #     {crdt.multi 2}
        #     {crdt.select 2 1}
        #     {crdt.set k10 v2 2 * {1:9;2:1} -1}
        #     {crdt.hset h10 2 * {1:9;2:2} 2 k v2}
        #     {crdt.exec 2}
        #     {crdt.multi 1}
        #     {crdt.select 1 0}
        #     {crdt.set k10 v1 1 * {1:10;2:2} -1}
        #     {crdt.hset h10 1 * {1:11;2:2} 2 k v1}
        #     {crdt.exec 1}
        # }
        assert_replication_stream $peer_repl  {
            {crdt.multi 2}
            {crdt.select 2 1}
            {crdt.set k10 v2 2 * {1:9;2:1} -1}
            {crdt.hset h10 2 * {1:9;2:2} 2 k v2}
            {crdt.exec 2}
            {select 9}
            {crdt.multi 1}
            {crdt.select 1 0}
            {crdt.set k10 v1 1 * {1:10;2:2} -1}
            {crdt.hset h10 1 * {1:11;2:2} 2 k v1}
            {crdt.exec 1}
        }
        # assert_replication_stream $peer_slave_repl  {
        #     {crdt.multi 2}
        #     {crdt.select 2 1}
        #     {crdt.set k10 v2 2 * {1:9;2:1} -1}
        #     {crdt.hset h10 2 * {1:9;2:2} 2 k v2}
        #     {crdt.exec 2}
        #     {select 9}
        #     {crdt.multi 1}
        #     {crdt.select 1 0}
        #     {crdt.set k10 v1 1 * {1:10;2:2} -1}
        #     {crdt.hset h10 1 * {1:11;2:2} 2 k v1}
        #     {crdt.exec 1}
        # }
        $master select 0
        $slave select 0
        $slave_slave select 0
        $peer select 0
        $peer_slave select 0
        set kv_value [$master get k10]
        set hash_value [$master hget h10 k]
        assert_equal [$slave get k10] $kv_value
        assert_equal [$peer get k10] $kv_value
        assert_equal [$slave_slave get k10] $kv_value
        assert_equal [$peer_slave get k10] $kv_value                                                                            
        assert_equal [$slave hget h10 k] $hash_value
        assert_equal [$peer hget h10 k] $hash_value
        assert_equal [$slave_slave hget h10 k] $hash_value
        assert_equal [$peer_slave hget h10 k] $hash_value
        $master select 1
        $slave select 1
        $slave_slave select 1
        $peer select 1
        $peer_slave select 1
        set kv_value [$master get k10]
        set hash_value [$master hget h10 k]
        assert_equal [$slave get k10] $kv_value
        assert_equal [$peer get k10] $kv_value
        assert_equal [$slave_slave get k10] $kv_value
        assert_equal [$peer_slave get k10] $kv_value                                                                            
        assert_equal [$slave hget h10 k] $hash_value
        assert_equal [$peer hget h10 k] $hash_value
        assert_equal [$slave_slave hget h10 k] $hash_value
        assert_equal [$peer_slave hget h10 k] $hash_value

        check_peer_info $master $peer 0
        check_peer_info $master $peer_slave 0
        assert_equal [crdt_repl $master master_repl_offset] [crdt_repl $slave master_repl_offset]
        assert_equal [crdt_repl $master master_repl_offset] [crdt_repl $slave_slave master_repl_offset]
        assert_equal [crdt_repl $peer master_repl_offset] [crdt_repl $peer_slave master_repl_offset]
    }
    test "multi slaveof" {
        set master_crdt_sync_full [crdt_stats $master sync_full] 
        set master_sync_full [status $master sync_full] 
        $master multi
        $master set k5 v
        $master slaveof "127.0.0.1" 0
        $master exec 
        $master slaveof no one
        $master set k5 v1 
        wait_for_sync $slave
        wait_for_peer_sync $peer
        wait_for_sync $slave_slave
        wait_for_sync $peer_slave
        assert_equal [$slave get k5] v1
        assert_equal [$peer get k5] v1
        assert_equal [$slave_slave get k5] v1
        assert_equal [$peer_slave get k5] v1
        # assert_equal [$slave get k5] v
        assert_equal  [crdt_stats $master sync_full] $master_crdt_sync_full
        assert_equal  [status $master sync_full] $master_sync_full
        check_peer_info $master $peer 0
        check_peer_info $master $peer_slave 0
        assert_equal [crdt_repl $master master_repl_offset] [crdt_repl $slave master_repl_offset]
        assert_equal [crdt_repl $master master_repl_offset] [crdt_repl $slave_slave master_repl_offset]
        assert_equal [crdt_repl $peer master_repl_offset] [crdt_repl $peer_slave master_repl_offset]
    }
    close_replication_stream $slave_repl
    close_replication_stream $peer_repl
    close_replication_stream $slave_slave_repl
    close_replication_stream $peer_slave_repl
    close_replication_stream $master_repl
    
}

