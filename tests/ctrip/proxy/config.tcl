proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
proc wait_backstream {r} {
    while 1 {
        if {[crdt_status $r backstreaming] eq 1} {
            after 100
        } else {
            break;
        }
    }
}

start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        start_proxy {tags "xpipe-proxy"} {
            set proxy_host [srv 0 "host"]
            set proxy_port [srv 0 "tcp_port"]
            set proxy [srv 0 "client"]
            start_proxy {tags "xpipe-proxy2"} {
                set proxy2_host [srv 0 "host"]
                set proxy2_port [srv 0 "tcp_port"]
                set proxy2_tls_port [srv 0 "tls_port"]
                set proxy2 [srv 0 "client"]
                # puts $proxy_port 
                # puts $proxy2_port
                test "master-peer1" {
                    $peer set test v
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
                    wait_for_peer_sync $master
                    assert_equal [crdt_status $master peer0_proxy_params] PROXYTLS://$proxy2_host:$proxy2_tls_port
                    test "v" {
                        $peer set k v 
                        after 1000
                        assert_equal [$master get k] v
                        assert_equal [$master get test] v
                    }

                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
                    set sync_partial_ok_num [crdt_stats $peer sync_partial_ok]
                    wait_for_peer_sync $master
                    assert_equal [crdt_status $master peer0_proxy_params] PROXYTLS://$proxy2_host:$proxy2_tls_port
                    assert_equal $sync_partial_ok_num [crdt_stats $peer sync_partial_ok]
                    assert_equal [crdt_status $master peer0_proxy_server] PROXYTCP://$proxy_host:$proxy_port

                    #reset peerof
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
                    wait_for_peer_sync $master
                   
                    catch {$master shutdown} error
                    set master_config_file [srv -3 config_file]
                    set master_config [srv -3 config]
                    # puts [read_file $master_config_file]
                    start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                        set master [redis $master_host $master_port]
                        $master select 9
                        
                        wait_for_peers_sync 1 $master 
                        wait_backstream $master 
                        assert_equal [$master get k] [$peer get k]
                        

                    }
                }
                
            }
            
        }
    }
}

# start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
#     set master [srv 0 client]
#     set master_gid 1
#     set master_host [srv 0 host]
#     set master_port [srv 0 port]
#     set master_stdout [srv 0 stdout]
#     set master_stderr [srv 0 stderr]
#     start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
#         set peer [srv 0 client]
#         set peer_gid 2
#         set peer_host [srv 0 host]
#         set peer_port [srv 0 port]
#         set peer_log [srv 0 stdout]
#         start_proxy {tags "xpipe-proxy"} {
#             set proxy_host [srv 0 "host"]
#             set proxy_port [srv 0 "tcp_port"]
#             set proxy [srv 0 "client"]
#             start_proxy {tags "xpipe-proxy2"} {
#                 set proxy2_host [srv 0 "host"]
#                 set proxy2_port [srv 0 "tcp_port"]
#                 set proxy2_tls_port [srv 0 "tls_port"]
#                 set proxy2 [srv 0 "client"]
#                 # puts $proxy_port 
#                 # puts $proxy2_port
#                 test "master-peer2" {
#                     $peer set test v
#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://[format "127.0.0.1:0,%s:%d" $proxy_host $proxy_port] proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
#                     $master config rewrite

#                     catch {$master shutdown} error
#                     set master_config_file [srv -3 config_file]
#                     set master_config [srv -3 config]
#                     start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
#                         set master [redis $master_host $master_port]
#                         $master select 9
#                         after 2000
#                         wait_for_peers_sync 1 $master 
#                         wait_backstream $master 
#                         assert_equal [$master get k] [$peer get k]

#                     }
#                 }
                
#             }
            
#         }
#     }
# }



# start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
#     set master [srv 0 client]
#     set master_gid 1
#     set master_host [srv 0 host]
#     set master_port [srv 0 port]
#     set master_stdout [srv 0 stdout]
#     set master_stderr [srv 0 stderr]
#     start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
#         set peer [srv 0 client]
#         set peer_gid 2
#         set peer_host [srv 0 host]
#         set peer_port [srv 0 port]
#         set peer_log [srv 0 stdout]
#         start_proxy {tags "xpipe-proxy"} {
#             set proxy_host [srv 0 "host"]
#             set proxy_port [srv 0 "tcp_port"]
#             set proxy [srv 0 "client"]
#             start_proxy {tags "xpipe-proxy2"} {
#                 set proxy2_host [srv 0 "host"]
#                 set proxy2_port [srv 0 "tcp_port"]
#                 set proxy2_tls_port [srv 0 "tls_port"]
#                 set proxy2 [srv 0 "client"]
#                 # puts $proxy_port 
#                 # puts $proxy2_port
#                 test "master-peer3" {
#                     $peer set test v
#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0 proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
#                     $master config rewrite

#                     catch {$master shutdown} error
#                     set master_config_file [srv -3 config_file]
#                     set master_config [srv -3 config]
#                     start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
#                         set master [redis $master_host $master_port]
#                         $master select 9
#                         after 2000
#                         catch {$master get test} error
#                         assert_equal $error "LOADING Redis is loading the dataset in memory"
                        

#                     }
#                 }
                
#             }
            
#         }
#     }
# }

# start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
#     set master [srv 0 client]
#     set master_gid 1
#     set master_host [srv 0 host]
#     set master_port [srv 0 port]
#     set master_stdout [srv 0 stdout]
#     set master_stderr [srv 0 stderr]
#     start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
#         set peer [srv 0 client]
#         set peer_gid 2
#         set peer_host [srv 0 host]
#         set peer_port [srv 0 port]
#         set peer_log [srv 0 stdout]
#         start_proxy {tags "xpipe-proxy"} {
#             set proxy_host [srv 0 "host"]
#             set proxy_port [srv 0 "tcp_port"]
#             set proxy [srv 0 "client"]
#             start_proxy {tags "xpipe-proxy2"} {
#                 set proxy2_host [srv 0 "host"]
#                 set proxy2_port [srv 0 "tcp_port"]
#                 set proxy2_tls_port [srv 0 "tls_port"]
#                 set proxy2 [srv 0 "client"]
#                 # puts $proxy_port 
#                 # puts $proxy2_port
#                 test "master-peer4" {
#                     $peer set test v
#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:0
#                     $master config rewrite

#                     catch {$master shutdown} error
#                     set master_config_file [srv -3 config_file]
#                     set master_config [srv -3 config]
#                     start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
#                         set master [redis $master_host $master_port]
#                         $master select 9
#                         after 2000
#                         catch {$master get test} error
#                         assert_equal $error "LOADING Redis is loading the dataset in memory"
                        

#                     }
#                 }
                
#             }
            
#         }
#     }
# }

# start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
#     set master [srv 0 client]
#     set master_gid 1
#     set master_host [srv 0 host]
#     set master_port [srv 0 port]
#     set master_stdout [srv 0 stdout]
#     set master_stderr [srv 0 stderr]
#     start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
#         set peer [srv 0 client]
#         set peer_gid 2
#         set peer_host [srv 0 host]
#         set peer_port [srv 0 port]
#         set peer_log [srv 0 stdout]
#         start_proxy {tags "xpipe-proxy"} {
#             set proxy_host [srv 0 "host"]
#             set proxy_port [srv 0 "tcp_port"]
#             set proxy [srv 0 "client"]
#             set proxy1c [xpipe_proxy $proxy_host $proxy_port]
#             start_proxy {tags "xpipe-proxy2"} {
#                 set proxy2_host [srv 0 "host"]
#                 set proxy2_port [srv 0 "tcp_port"]
#                 set proxy2_tls_port [srv 0 "tls_port"]
#                 set proxy2 [srv 0 "client"]
#                 set proxy2c [xpipe_proxy $proxy2_host $proxy2_port]
#                 # puts $proxy_port 
#                 # puts $proxy2_port
#                 test "master-peer5" {
#                     $peer set test v
#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
#                     wait_for_peer_sync $master
#                     test "v" {
#                         $peer set k v 
#                         after 1000
#                         assert_equal [$master get k] v
#                         assert_equal [$master get test] v
#                     }
                    

#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
#                     set sync_partial_ok_num [crdt_stats $peer sync_partial_ok]
#                     wait_for_peer_sync $master
#                     assert_equal $sync_partial_ok_num [crdt_stats $peer sync_partial_ok]

#                     start_proxy {tags "xpipe-proxy3"} {
#                         set proxy3_host [srv 0 "host"]
#                         set proxy3_port [srv 0 "tcp_port"]
#                         set proxy3_tls_port [srv 0 "tls_port"]
#                         set proxy3 [srv 0 "client"]
#                         set proxy3c [xpipe_proxy $proxy2_host $proxy2_port]
#                         $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,PROXYTCP://$proxy_host:$proxy_port proxy-params [format "PROXYTLS://%s:%d PROXYTLS://%s:%d" $proxy2_host $proxy2_tls_port $proxy3_host $proxy3_tls_port]
#                         set sync_partial_ok_num [crdt_stats $peer sync_partial_ok]
#                         wait_for_peer_sync $master
#                         assert_equal [expr $sync_partial_ok_num + 1] [crdt_stats $peer sync_partial_ok]
#                         $peer set k1 v1 
#                         after 1000
#                         assert_equal [$master get k1] v1
#                     }

#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,PROXYTCP://$proxy_host:$proxy_port proxy-params [format "PROXYTLS://%s:%d;FORWARD_FOR 127.0.0.1:8888;" $proxy2_host $proxy2_tls_port ]
#                     wait_for_peer_sync $master
#                     assert_match "\{127.0.0.1:8888-*" [$proxy1c monitor SocketStats]

                    
#                     #reset peerof
#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
#                     wait_for_peer_sync $master
                

#                     catch {$master shutdown} error
#                     set master_config_file [srv -3 config_file]
#                     set master_config [srv -3 config]
#                     start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
#                         set master [redis $master_host $master_port]
#                         $master select 9
                        
#                         wait_for_peers_sync 1 $master 
#                         wait_backstream $master 
#                         assert_equal [$master get k] [$peer get k]
                        

#                     }
#                 }
                
#             }
            
#         }
#     }
# }


# start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
#     set master [srv 0 client]
#     set master_gid 1
#     set master_host [srv 0 host]
#     set master_port [srv 0 port]
#     set master_stdout [srv 0 stdout]
#     set master_stderr [srv 0 stderr]
#     start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
#         set peer [srv 0 client]
#         set peer_gid 2
#         set peer_host [srv 0 host]
#         set peer_port [srv 0 port]
#         set peer_log [srv 0 stdout]
#         start_proxy {tags "xpipe-proxy"} {
#             set proxy_host [srv 0 "host"]
#             set proxy_port [srv 0 "tcp_port"]
#             set proxy [srv 0 "client"]
#             set proxy1c [xpipe_proxy $proxy_host $proxy_port]
#             start_proxy {tags "xpipe-proxy2"} {
#                 set proxy2_host [srv 0 "host"]
#                 set proxy2_port [srv 0 "tcp_port"]
#                 set proxy2_tls_port [srv 0 "tls_port"]
#                 set proxy2 [srv 0 "client"]
#                 set proxy2c [xpipe_proxy $proxy2_host $proxy2_port]
#                 # puts $proxy_port 
#                 # puts $proxy2_port
#                 test "master-peer5" {
                    
#                     $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://127.0.0.1:0,$proxy_host:$proxy_port proxy-params [format "PROXYTLS://%s:%d;FORWARD_FOR 127.0.0.1:8888;" $proxy2_host $proxy2_tls_port ]
#                     wait_for_peer_sync $master
#                     assert_match "\{127.0.0.1:8888-*" [$proxy1c monitor SocketStats]


#                     catch {$master shutdown} error
#                     set master_config_file [srv -3 config_file]
#                     set master_config [srv -3 config]
#                     start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
#                         set master [redis $master_host $master_port]
#                         $master select 9
                        
#                         wait_for_peers_sync 1 $master 
#                         wait_backstream $master 
#                         assert_equal [$master get k] [$peer get k]
                        

#                     }
#                 }
                
#             }
            
#         }
#     }
# }