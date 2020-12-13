proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

proc wait { client index type log}  {
    set retry 50
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
        print_log_file $log
        error "assertion: Master-Slave not correctly synchronized"
    }
}

#create six redis  
proc create_crdts {type arrange} {
    start_server {tags {"repl"} overrides {crdt-gid 3} module {crdt.so} } {
        set peer2 [srv 0 client]
        set peer2_host [srv 0 host]
        set peer2_port [srv 0 port]
        set peer2_log [srv 0 stdout]
        set peer2_gid 3
        $peer2 config set repl-diskless-sync yes
        $peer2 config set repl-diskless-sync-delay 1
        $peer2 config crdt.set repl-diskless-sync-delay 1
        start_server {overrides {crdt-gid 3} module {crdt.so}} {
            set peer2_slave [srv 0 client]
            set peer2_slave_host [srv 0 host]
            set peer2_slave_port [srv 0 port]
            set peer2_slave_log [srv 0 stdout]
            set peer2_slave_gid 3
            $peer2_slave config set repl-diskless-sync yes
            $peer2_slave config set repl-diskless-sync-delay 1
            $peer2_slave config crdt.set repl-diskless-sync-delay 1
            start_server {overrides {crdt-gid 2} module {crdt.so}} {
                set peer [srv 0 client]
                set peer_host [srv 0 host]
                set peer_port [srv 0 port]
                set peer_log [srv 0 stdout]
                set peer_gid 2
                $peer config set repl-diskless-sync yes
                $peer config set repl-diskless-sync-delay 1
                $peer config crdt.set repl-diskless-sync-delay 1

                start_server {overrides {crdt-gid 2} module {crdt.so}} {
                    set peer_slave [srv 0 client]
                    set peer_slave_host [srv 0 host]
                    set peer_slave_port [srv 0 port]
                    set peer_slave_log [srv 0 stdout]
                    set peer_slave_gid 2
                    $peer_slave config set repl-diskless-sync yes
                    $peer_slave config set repl-diskless-sync-delay 1
                    $peer_slave config crdt.set repl-diskless-sync-delay 1
    
                    start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {
                        set master [srv 0 client]
                        set master_host [srv 0 host]
                        set master_port [srv 0 port]
                        set master_log [srv 0 stdout]
                        set master_gid 1
                        $master config set repl-diskless-sync yes
                        $master config set repl-diskless-sync-delay 1
                        $master config crdt.set repl-diskless-sync-delay 1
                        start_server {overrides {crdt-gid 1} module {crdt.so}} {
                            set slave [srv 0 client]
                            set slave_host [srv 0 host]
                            set slave_port [srv 0 port]
                            set slave_log [srv 0 stdout]
                            set slave_gid 1
                            $slave config set repl-diskless-sync yes
                            $slave config set repl-diskless-sync-delay 1
                            $slave config crdt.set repl-diskless-sync-delay 1
                            

                            # $peer_slave slaveof $peer_host $peer_port
                            # $peer2_slave slaveof $peer_host $peer_port
                            # $slave slaveof $master_host $master_port 
                            $master peerof $peer_gid $peer_host $peer_port 
                            $master peerof $peer2_gid $peer2_host $peer2_port 
                            $peer  peerof $peer2_gid $peer2_host $peer2_port 
                            $peer  peerof $master_gid $master_host $master_port
                            $peer2 peerof $master_gid $master_host $master_port
                            $peer2 peerof $peer_gid $peer_host $peer_port
                            wait $master 0 crdt.info $master_log
                            wait $master 1 crdt.info $master_log
                            wait $peer 0 crdt.info $peer_log
                            wait $peer 1 crdt.info $peer_log
                            wait $peer2 0 crdt.info $peer2_log
                            wait $peer2 1 crdt.info $peer2_log
                            after 5000
                            test $type {
                                if {[catch [uplevel 0 $arrange ] result]} {
                                    puts $result
                                }
                                exec cp $master_log ./m.log
                                exec cp $peer_log ./p.log
                                exec cp $peer2_log ./p2.log
                            }
                        }
                    }
                }
            } 
        }
    }
}

 
proc start_local {port dir gid} {
    if { [file exists $dir] != 1} {  
       puts [file mkdir $dir]
    }
    exec "./src/redis-server" "--crdt-gid" "default" $gid "--loadmodule" "../../crdt-module/crdt.so" "--port" $port "--logfile" "redis.log" "--daemonize" "yes" "--dir" $dir 
}

proc stop_local {host port} {
    catch {exec "./src/redis-cli" "-p" $port "-h" $host "shutdown"} error
}

proc set_crdt_config {client} {
    $client config set repl-diskless-sync yes
    $client config set repl-diskless-sync-delay 1
    $client config crdt.set repl-diskless-sync-delay 1
                        
}

proc test_local_redis {type arrange} {
    set log_file "/redis.log"
    set local_host "127.0.0.1"

    set master_dir "./local_crdt/master"
    set master_port 7000
    set master_host "127.0.0.1"
    set master_gid 1
    set master_log "$master_dir/$log_file"

    set peer_dir "./local_crdt/peer"
    set peer_host "127.0.0.1"
    set peer_port 7001 
    
    set peer_gid 2
    set peer_log "$peer_dir/$log_file"; 

    set peer2_dir "./local_crdt/peer2"
    set peer2_host "127.0.0.1"
    set peer2_port 7002 
    
    set peer2_gid 3
    set peer2_log "$peer2_dir/$log_file"

    stop_local $master_host $master_port
    stop_local $peer_host $peer_port
    stop_local $peer2_host $peer2_port
    start_local  $master_port $master_dir $master_gid
    start_local  $peer_port $peer_dir $peer_gid 
    start_local  $peer2_port $peer2_dir $peer2_gid
    after 1000

    set master [redis $master_host $master_port]
    set peer [redis $peer_host $peer_port]
    set peer2 [redis $peer2_host $peer2_port]

    set_crdt_config $master 
    set_crdt_config $peer
    set_crdt_config $peer2
   
    $master peerof $peer_gid $peer_host $peer_port 
    $master peerof $peer2_gid $peer2_host $peer2_port 
    $peer  peerof $peer2_gid $peer2_host $peer2_port 
    $peer  peerof $master_gid $master_host $master_port
    $peer2 peerof $master_gid $master_host $master_port
    $peer2 peerof $peer_gid $peer_host $peer_port
    wait $master 0 crdt.info $master_log
    wait $master 1 crdt.info $master_log
    wait $peer 0 crdt.info $peer_log
    wait $peer 1 crdt.info $peer_log
    wait $peer2 0 crdt.info $peer2_log
    wait $peer2 1 crdt.info $peer2_log
    test $type {
        if {[catch [uplevel 0 $arrange ] result]} {
            puts $result
        }
        stop_local $master_host $master_port
        stop_local $peer_host $peer_port
        stop_local $peer2_host $peer2_port
    }
}