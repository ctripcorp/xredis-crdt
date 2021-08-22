
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
            test "mater-peer error" {
                catch { $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://{127.0.0.1:11.11} } error 
                assert_equal $error "ERR proxy params error"
            }
            test "master-peer" {
                $peer set bk v1
                $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port
                wait_for_peer_sync $master
                $peer set k v 
                after 1000
                assert_equal [$master get k] v
                assert_equal [$peer get k] v
            }
            test "master-peer2" {
                $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://[format "%s:%d,%s:%d" {127.0.0.1} 0 $proxy_host $proxy_port]
                wait_for_peer_sync $master
                $peer set k v1 
                after 1000
                assert_equal [$master get k] v1
            }
        }
    }
}