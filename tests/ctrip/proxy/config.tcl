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
                test "master-peer" {
                    $peer set test v
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-server $proxy_host:$proxy_port proxy-proxytls PROXYTLS://$proxy2_host:$proxy2_tls_port
                    wait_for_peer_sync $master
                    $peer set k v 
                    after 1000
                    assert_equal [$master get k] v
                    assert_equal [$master get test] v
                    $master config rewrite

                    catch {$master shutdown} error
                    set master_config_file [srv -3 config_file]
                    set master_config [srv -3 config]
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
                test "master-peer" {
                    $peer set test v
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-server [format "127.0.0.1:0;%s:%d" $proxy_host $proxy_port] proxy-proxytls PROXYTLS://$proxy2_host:$proxy2_tls_port
                    $master config rewrite

                    catch {$master shutdown} error
                    set master_config_file [srv -3 config_file]
                    set master_config [srv -3 config]
                    start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                        set master [redis $master_host $master_port]
                        $master select 9
                        after 2000
                        wait_for_peers_sync 1 $master 
                        wait_backstream $master 
                        assert_equal [$master get k] [$peer get k]

                    }
                }
                
            }
            
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
                test "master-peer" {
                    $peer set test v
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-server 127.0.0.1:0 proxy-proxytls PROXYTLS://$proxy2_host:$proxy2_tls_port
                    $master config rewrite

                    catch {$master shutdown} error
                    set master_config_file [srv -3 config_file]
                    set master_config [srv -3 config]
                    start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                        set master [redis $master_host $master_port]
                        $master select 9
                        after 2000
                        catch {$master get test} error
                        assert_equal $error "LOADING Redis is loading the dataset in memory"
                        

                    }
                }
                
            }
            
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
                test "master-peer" {
                    $peer set test v
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-server $proxy_host:$proxy_port proxy-proxytls PROXYTLS://$proxy2_host:0
                    $master config rewrite

                    catch {$master shutdown} error
                    set master_config_file [srv -3 config_file]
                    set master_config [srv -3 config]
                    start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
                        set master [redis $master_host $master_port]
                        $master select 9
                        after 2000
                        catch {$master get test} error
                        assert_equal $error "LOADING Redis is loading the dataset in memory"
                        

                    }
                }
                
            }
            
        }
    }
}

