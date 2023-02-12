

proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    return $content
}

proc read_from_all_stream {s} {
    fconfigure $s -blocking 0
    set attempt 0
    while {[gets $s count] == -1} {
        if {[incr attempt] == 10} return ""
        after 100
    }
    fconfigure $s -blocking 1
    set count [string range $count 1 end]

    # Return a list of arguments for the command.
    set res {}
    for {set j 0} {$j < $count} {incr j} {
        read $s 1
        set arg [::redis::redis_bulk_read $s]
        if {$j == 0} {set arg [string tolower $arg]}
        puts $arg
        lappend res $arg
    }
    return $res
}
proc attach_to_replication_stream {host port} {
    set s [socket $host $port]
    fconfigure $s -translation binary
    puts -nonewline $s "SYNC\r\n"
    flush $s

    # Get the count
    while 1 {
        set count [gets $s]
        set prefix [string range $count 0 0]
        if {$prefix ne {}} break; # Newlines are allowed as PINGs.
    }
    if {$prefix ne {$}} {
        error "attach_to_replication_stream error. Received '$count' as count."
    }
    set count [string range $count 1 end]

    # Consume the bulk payload
    while {$count} {
        set buf [read $s $count]
        set count [expr {$count-[string length $buf]}]
    }
    return $s
}



start_server {tags {"backstreaming, can't  write and read"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
    set peer [srv 0 client]
    set peer_gid 2
    set peer_host [srv 0 host]
    set peer_port [srv 0 port]
    set peer_stdout [srv 0 stdout]
    set peer_stderr [srv 0 stderr]
    start_server {tags {"backstreaming, can't  write and read"} overrides {crdt-gid 3} config {crdt.conf} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_gid 3
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_stdout [srv 0 stdout]
        set peer2_stderr [srv 0 stderr]
        start_server {tags {"backstreaming, can't  write and read"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set master [srv 0 client]
            set master_gid 1
            set master_host [srv 0 host]
            set master_port [srv 0 port]
            set master_stdout [srv 0 stdout]
            set master_stderr [srv 0 stderr]

            $master peerof $peer_gid $peer_host $peer_port
            $master peerof $peer2_gid $peer2_host $peer2_port
            set config_file  [read_file  [srv 0 config_file]]
            # puts $config_file

            assert_match "*peerof 2 127.0.0.1*" $config_file
            assert_match "*peerof 3 127.0.0.1*" $config_file
            # puts $config_file
            # puts [$master config get peerof] 
            # puts [srv 0 stdout]
            shutdown_will_restart_redis $master 
            after 1000
            $peer crdt.set key v1 1 1000 1:1 
            $peer crdt.set key2 v2 1 1002 1:2
            $peer2 crdt.set key v2 1 1001 1:1 
            start_server_by_config [srv 0 config_file] [srv 0 config] $master_host $master_port $master_stdout $master_stderr 1 {
                after 1000
                set master [redis $master_host $master_port]
                $master select 9
                test "0" {
                    catch {$master get key} error 
                    assert_match "*LOADING Redis is loading the dataset in memory*" $error 
                    wait_for_peers_sync 1 $master 
                    assert_equal [$master get key] v1 
                }
                
            }
            # assert_equal [$master get key2] v2
        }
    }
}



start_server {tags {"load rdb master"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    set master_config [srv 0 config]
    start_server {tags {"load rdb master"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        # puts [dict get [srv 0 config] dir]
        # $peer crdt.set key v1 1 1000 1:1 
        $peer peerof $master_gid $master_host $master_port
        wait_for_peer_sync $peer 
        $master peerof $peer_gid $peer_host $peer_port 
        wait_for_peer_sync $master 
        $master set key v1
        # puts [$master info replication]
        # puts [$master crdt.info replication]
        $master bgsave 
        waitForBgsave $master 
        # puts [read_file $master_stdout]
        shutdown_will_restart_redis $master 
        set server_path [tmpdir "server.restart1"]
        set dbfile [dict get $master_config dbfilename]
        set rdb_path [format "%s/%s" [dict get $master_config dir] $dbfile]
        assert_equal [file exists $rdb_path] 1
        exec mv $rdb_path $server_path
        assert_equal [file exists [format "%s/%s" $server_path $dbfile]] 1
        cp_crdt_so $server_path
        start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" $dbfile ]] {
            set master [srv 0 client]
            catch {$master get k} error
            if {$error != {}} {
                assert_match "*LOADING Redis is loading the dataset in memory*" $error 
            }
            test "1" {
                wait_for_peer_sync $master 
                # puts [$master crdt.info replication]
                # puts [read_file [format "%s/stdout" $server_path]]
                assert_equal [$master get key] v1
            }
            
            
        }
    }
}


start_server {tags {"slave load rdb"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    set master_config [srv 0 config]
    start_server {tags {"slave load rdb"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        start_server {tags {"slave load rdb"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_stderr [srv 0 stderr]
            set slave_config [srv 0 config]
            
            $master peerof $peer_gid $peer_host $peer_port 
            $peer peerof $master_gid $master_host $master_port 
            $peer crdt.set key v1 1 1000 1:1 
            #
            $slave slaveof $master_host $master_port
            wait_for_sync $slave 
            $slave bgsave
            waitForBgsave $slave 
            shutdown_will_restart_redis $slave 
            set server_path [tmpdir "server.slave_restart1"]
            set dbfile [dict get $slave_config dbfilename]
            set rdb_path [format "%s/%s" [dict get $slave_config dir] $dbfile]
            assert_equal [file exists $rdb_path] 1
            exec mv $rdb_path $server_path
            assert_equal [file exists [format "%s/%s" $server_path $dbfile]] 1
            cp_crdt_so $server_path
            start_server [list overrides [list crdt-gid 1 loadmodule ./crdt.so  "dir"  $server_path "dbfilename" $dbfile]] {
                set slave [srv 0 client]
                wait_for_peer_sync $slave 
                assert_equal [$slave get key] v1
            }
            # after 1000
            # set config_file  [read_file  [srv 0 config_file]]
            # assert_match [format "*peerof 2 127.0.0.1 %s*" $peer_port] $config_file 
            # assert_match "*slaveof 127.0.0.1*"  $config_file 
            
        }
    }
}

#When the slave is started and the synchronization is not completed, it can continue to return after switching to the master
start_server {tags {"slave load rdb.conf"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
    set peer [srv 0 client]
    set peer_gid 2
    set peer_host [srv 0 host]
    set peer_port [srv 0 port]
    set peer_stdout [srv 0 stdout]
    set peer_stderr [srv 0 stderr]
    $peer config crdt.set repl-diskless-sync-delay 1
    start_server {tags {"master"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set master [srv 0 client]
        set master_gid 1
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_stderr [srv 0 stderr]
        start_server {tags {"slave"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_stderr [srv 0 stderr]
            $slave slaveof $master_host $master_port
            wait_for_sync $slave 
            $master peerof $peer_gid $peer_host $peer_port 
            wait_for_peer_sync $master
            after 2000
            set config_file  [read_file  [srv 0 config_file]]
            # puts $config_file
            assert_match "*peerof 2 127.0.0.1*" $config_file
            assert_match "*slaveof 127.0.0.1*" $config_file
            $peer crdt.set key v1 1 1000 1:1 
            $peer crdt.set key2 v2 1 1002 1:2
            shutdown_will_restart_redis $slave 
            $master set kkkk a
            assert_equal [$peer get kkkk] {}
            $master config set repl-diskless-sync yes
            $master config set repl-diskless-sync-delay 5
            $master config set repl-backlog-size 100b
            for {set i 0} {$i < 100} {incr i} {
                $master set $i $i
            }
            start_server_by_config [srv 0 config_file] [srv 0 config] $slave_host $slave_port $slave_stdout $slave_stderr 0 {
                set slave [redis $slave_host $slave_port]
                $slave select 9
                $slave slaveof no one 
                assert_equal [crdt_status $slave backstreaming] 1
                wait_for_peer_sync $slave 
                # puts [$slave crdt.info replication]
                assert_equal [$slave get key] v1
            }
        }
    }
}
#When the slave is stated and incremental synchronization is completed, it will not backstream when it becomes the master
start_server {tags {"slave load rdb.conf"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
    set peer [srv 0 client]
    set peer_gid 2
    set peer_host [srv 0 host]
    set peer_port [srv 0 port]
    set peer_stdout [srv 0 stdout]
    set peer_stderr [srv 0 stderr]
    $peer config crdt.set repl-diskless-sync-delay 1
    start_server {tags {"master"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set master [srv 0 client]
        set master_gid 1
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_stderr [srv 0 stderr]
        start_server {tags {"slave"} overrides {crdt-gid 1} config {crdt_no_save.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_stderr [srv 0 stderr]
            $peer crdt.set key v1 1 1000 1:1 
            $slave slaveof $master_host $master_port
            wait_for_sync $slave 
            $master peerof $peer_gid 127.0.0.1 0 
            $slave bgsave 
            waitForBgsave $slave 

            $master peerof $peer_gid $peer_host $peer_port 
            wait_for_peer_sync $master
            
            set config_file  [read_file  [srv 0 config_file]]
            assert_match "*peerof 2 127.0.0.1*" $config_file
            assert_match "*slaveof 127.0.0.1*" $config_file
            $peer crdt.set key v1 1 1000 1:1 
            $peer crdt.set key2 v2 1 1002 1:2
            shutdown_will_restart_redis $slave 
            $master set kkkk a
            assert_equal [$peer get kkkk] {}
            $master config set repl-diskless-sync no
            $master config set repl-diskless-sync-delay 5
            
            start_server_by_config [srv 0 config_file] [srv 0 config] $slave_host $slave_port $slave_stdout $slave_stderr 1 {
                set slave [redis $slave_host $slave_port]
                $slave select 9
                wait_for_sync $slave 
                assert_equal [$slave get key] {}
                assert_equal [crdt_stats $peer sync_backstream] 0
                assert_equal [status $master sync_partial_ok] 1
                $slave slaveof no one 
                wait_for_peer_sync $slave 
                assert_equal [$slave get key] {}
                assert_equal [crdt_stats $peer sync_backstream] 0   
            }
        }
    }
}
#When the slave is stated and full-sync is completed, it will not backstream when it becomes the master
start_server {tags {"slave full-sync after to master no backstream"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
    set peer [srv 0 client]
    set peer_gid 2
    set peer_host [srv 0 host]
    set peer_port [srv 0 port]
    set peer_stdout [srv 0 stdout]
    set peer_stderr [srv 0 stderr]
    $peer config crdt.set repl-diskless-sync-delay 1
    start_server {tags {"master"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
        set master [srv 0 client]
        set master_gid 1
        set master_host [srv 0 host]
        set master_port [srv 0 port]
        set master_stdout [srv 0 stdout]
        set master_stderr [srv 0 stderr]
        start_server {tags {"slave"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 1
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_stdout [srv 0 stdout]
            set slave_stderr [srv 0 stderr]
            $slave slaveof $master_host $master_port
            wait_for_sync $slave 
            $master peerof $peer_gid $peer_host $peer_port 
            wait_for_peer_sync $master
            after 2000
            set config_file  [read_file  [srv 0 config_file]]
            # puts $config_file
            assert_match "*peerof 2 127.0.0.1*" $config_file
            assert_match "*slaveof 127.0.0.1*" $config_file
            $peer crdt.set key v1 1 1000 1:1 
            $peer crdt.set key2 v2 1 1002 1:2
            shutdown_will_restart_redis $slave 
            $master set kkkk a
            assert_equal [$peer get kkkk] {}
            $master config set repl-diskless-sync yes
            $master config set repl-diskless-sync-delay 5
            $master config set repl-backlog-size 100b
            for {set i 0} {$i < 100} {incr i} {
                $master set $i $i
            }
            start_server_by_config [srv 0 config_file] [srv 0 config] $slave_host $slave_port $slave_stdout $slave_stderr 0 {
                set slave [redis $slave_host $slave_port]
                $slave select 9
                wait_for_sync $slave
                $slave slaveof no one 
                assert_equal [crdt_stats $peer sync_backstream] 0
                wait_for_peer_sync $slave 
                assert_equal [crdt_stats $peer sync_backstream] 0
                assert_equal [$slave get key] {}
            }
        }
    }
}

#master load config
start_server {tags {"master"} overrides {crdt-gid 1} config {crdt_no_save.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    set master_config_file [srv 0 config_file]
    set master_config [srv 0 config]
    # $master peerof 2 127.0.0.1 0 
    start_server {tags {"peer"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        $peer config crdt.set repl-diskless-sync-delay 1 
        $peer peerof $master_gid $master_host $master_port
        $peer crdt.set key v1 1 1000 1:1
        $master peerof 2 127.0.0.1 0 
        $master bgsave 
        waitForBgrewriteaof $master
        $master peerof $peer_gid $peer_host $peer_port
        #save config
        assert_match "*peerof 2 127.0.0.1*" $config_file
        #rdb is ok
        set dbfile [dict get $master_config dbfilename]
        set rdb_path [format "%s/%s" [dict get $master_config dir] $dbfile]
        assert_equal [file exists $rdb_path] 1
        shutdown_will_restart_redis $master
        start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 0 {
            after 2000
            set master [redis $master_host $master_port]
            $master select 9
            test "2" {
                wait_for_peer_sync $master 
                assert_equal [$master get key] v1
            }
            
        }
    }
}

start_server {tags {"master"} overrides {crdt-gid 1} config {crdt_no_save.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    set master_config_file [srv 0 config_file]
    set master_config [srv 0 config]
    # $master peerof 2 127.0.0.1 0 
    start_server {tags {"peer"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_stdout [srv 0 stdout]
        set peer_stderr [srv 0 stderr]
        $peer config crdt.set repl-diskless-sync-delay 1 
        $master config crdt.set repl-diskless-sync-delay 1
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port
        wait_for_peer_sync $peer 
        wait_for_peer_sync $master
        $peer set peer_key a 
        $master set master_key a 
        $master set k a 
        $peer set k b 
        shutdown_will_restart_redis $master 
        start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 0 {
            after 2000
            set master [redis $master_host $master_port]
            wait_for_peer_sync $master
            # puts [$master crdt.info replication]
            $master select 9
            assert_equal [$master crdt.datainfo peer_key] [$peer crdt.datainfo peer_key] 
            assert_equal [$master crdt.datainfo master_key] [$peer crdt.datainfo master_key] 
            assert_equal [$master crdt.datainfo k] [$peer crdt.datainfo k] 
            
            $master peerof $peer_gid no one 
            $master flushall 
            $master peerof $peer_gid $peer_host $peer_port backstream 0
            wait_for_peer_sync $master
            # puts [read_file $master_stdout]

            assert_equal [$master crdt.datainfo peer_key] [$peer crdt.datainfo peer_key] 
            assert_equal [$master crdt.datainfo master_key] [$peer crdt.datainfo master_key] 
            assert_equal [$master crdt.datainfo k] [$peer crdt.datainfo k] 
        }
    }
}