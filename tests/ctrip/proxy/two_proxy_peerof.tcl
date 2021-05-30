
proc read_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
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
                }
                test "master-peer2" {
                    $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-server [format "%s:%d;%s:%d" {127.0.0.1} 0 $proxy_host $proxy_port] PROXYTLS://$proxy2_host:$proxy2_tls_port
                    wait_for_peer_sync $master
                    $peer set k v1 
                    after 1000
                    assert_equal [$master get k] v1
                }
            }
            
        }
    }
}