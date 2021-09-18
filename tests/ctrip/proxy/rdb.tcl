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
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 2
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            start_proxy {tags "xpipe-proxy"} {
                set proxy_host [srv 0 "host"]
                set proxy_port [srv 0 "tcp_port"]
                set proxy [srv 0 "client"]
                start_proxy {tags "xpipe-proxy2"} {
                    set proxy2_host [srv 0 "host"]
                    set proxy2_port [srv 0 "tcp_port"]
                    set proxy2_tls_port [srv 0 "tls_port"]
                    set proxy2 [srv 0 "client"]
                    test "full sync" {
                        $slave slaveof $master_host $master_port
                        wait_for_sync $slave 
                        $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
                        wait_for_peer_sync $master 
                        $peer set k v
                        after 2000
                        assert_equal [$slave get k] v
                        $slave slaveof no one 
                        wait_for_peer_sync $slave 
                        $peer set k1 v1 
                        after 2000
                        assert_equal [$slave get k1] v1
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
        start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 2
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            start_proxy {tags "xpipe-proxy"} {
                set proxy_host [srv 0 "host"]
                set proxy_port [srv 0 "tcp_port"]
                set proxy [srv 0 "client"]
                start_proxy {tags "xpipe-proxy2"} {
                    set proxy2_host [srv 0 "host"]
                    set proxy2_port [srv 0 "tcp_port"]
                    set proxy2_tls_port [srv 0 "tls_port"]
                    set proxy2 [srv 0 "client"]
                    test "full sync" {
                        $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port proxy-params PROXYTLS://$proxy2_host:$proxy2_tls_port
                        wait_for_peer_sync $master 
                        $peer set k v
                        $slave slaveof $master_host $master_port
                        wait_for_sync $slave 
                        assert_equal [$slave get k] v
                        $slave slaveof no one 
                        wait_for_peer_sync $slave 
                        $peer set k1 v1 
                        after 2000
                        assert_equal [$slave get k1] v1
                    }
                }
            }
            #wait close 
            after 2000
            $peer set k2 v2 
            after 2000
            assert_equal [$slave get k2] ""
            assert_equal [$master get k2] [$slave get k2] 
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
        start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 2
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            start_proxy {tags "xpipe-proxy"} {
                set proxy_host [srv 0 "host"]
                set proxy_port [srv 0 "tcp_port"]
                set proxy [srv 0 "client"]
                start_proxy {tags "xpipe-proxy2"} {
                    set proxy2_host [srv 0 "host"]
                    set proxy2_port [srv 0 "tcp_port"]
                    set proxy2_tls_port [srv 0 "tls_port"]
                    set proxy2 [srv 0 "client"]
                    test "full sync" {
                        $slave slaveof $master_host $master_port
                        wait_for_sync $slave 
                        $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port 
                        wait_for_peer_sync $master 
                        $peer set k v
                        after 2000
                        assert_equal [$slave get k] v
                        $slave slaveof no one 
                        wait_for_peer_sync $slave 
                        $peer set k1 v1 
                        after 2000
                        assert_equal [$slave get k1] v1
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
        start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
            set slave [srv 0 client]
            set slave_gid 2
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]
            set slave_log [srv 0 stdout]
            start_proxy {tags "xpipe-proxy"} {
                set proxy_host [srv 0 "host"]
                set proxy_port [srv 0 "tcp_port"]
                set proxy [srv 0 "client"]
                start_proxy {tags "xpipe-proxy2"} {
                    set proxy2_host [srv 0 "host"]
                    set proxy2_port [srv 0 "tcp_port"]
                    set proxy2_tls_port [srv 0 "tls_port"]
                    set proxy2 [srv 0 "client"]
                    test "full sync" {
                        $master peerof $peer_gid $peer_host $peer_port proxy-type XPIPE-PROXY proxy-servers PROXYTCP://$proxy_host:$proxy_port 
                        wait_for_peer_sync $master 
                        $peer set k v
                        $slave slaveof $master_host $master_port
                        wait_for_sync $slave 
                        assert_equal [$slave get k] v
                        $slave slaveof no one 
                        wait_for_peer_sync $slave 
                        $peer set k1 v1 
                        after 2000
                        assert_equal [$slave get k1] v1
                    }
                }
            }
            #wait close 
            after 2000
            $peer set k2 v2 
            after 2000
            assert_equal [$slave get k2] ""
            assert_equal [$master get k2] [$slave get k2] 
        }

    }
}