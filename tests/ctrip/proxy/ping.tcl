

# start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
#     set master [srv 0 client]
#     set master_gid 1
#     set master_host [srv 0 host]
#     set master_port [srv 0 port]
#     set master_log [srv 0 stdout]
#     start_proxy {tags "xpipe-proxy"} {
#         set proxy_host [srv 0 "host"]
#         set proxy_port [srv 0 "tcp_port"]
#         set proxy [srv 0 "client"]
#         test "proxy ping" {
#             assert_equal [$proxy ping] "PONG $proxy_host:$proxy_port"
#         }
#         test "proxy redis" {
#             $proxy route "TCP://$master_host:$master_port"
#             $proxy select 9
#             $proxy set k v
#             assert_equal [$master get k] v
#         }
#         test "proxy close" {
#             set p [xpipe_proxy $proxy_host $proxy_port]
#             set stats [$p monitor SocketStats]
#             $p closeChannel [lstats [lindex $stats 0]] 
#             puts [$p monitor SocketStats]
#             catch {$proxy get k} error
#             assert_equal $error "I/O error reading reply"
#         }
#     }
# }


start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    start_proxy {tags "xpipe-proxy"} {
        set proxy1_host [srv 0 "host"]
        set proxy1_port [srv 0 "tcp_port"]
        set proxy1 [srv 0 "client"]
        start_proxy {tags "xpipe-proxy2"} {
            set proxy2_host [srv 0 "host"]
            set proxy2_port [srv 0 "tcp_port"]
            set proxy2_tls_port [srv 0 "tls_port"]
            set proxy2 [srv 0 "client"]
            start_proxy {tags "xpipe-proxy3"} {
                set proxy3_host [srv 0 "host"]
                set proxy3_port [srv 0 "tcp_port"]
                set proxy3_tls_port [srv 0 "tls_port"]
                set proxy3 [srv 0 "client"]
                test "3 proxy" {
                    $proxy1 route "PROXYTLS://$proxy2_host:$proxy2_tls_port PROXYTLS://$proxy3_host:$proxy3_tls_port TCP://$master_host:$master_port"
                    $proxy1 select 9
                    $proxy1 set k v3
                    assert_equal [$master get k] v3
                    
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
    set master_log [srv 0 stdout]
    start_proxy {tags "xpipe-proxy"} {
        set proxy1_host [srv 0 "host"]
        set proxy1_port [srv 0 "tcp_port"]
        set proxy1 [srv 0 "client"]
        start_proxy {tags "xpipe-proxy2"} {
            set proxy2_host [srv 0 "host"]
            set proxy2_port [srv 0 "tcp_port"]
            set proxy2_tls_port [srv 0 "tls_port"]
            set proxy2 [srv 0 "client"]
            test "2 proxy" {
                $proxy1 route "TCP://$master_host:$master_port PROXYTLS://$proxy2_host:$proxy2_tls_port;FORWARD_FOR 127.0.0.1:8888;"
                $proxy1 select 9
                $proxy1 set k v3
                assert_equal [$master get k] v3
                set proxy1c [xpipe_proxy $proxy1_host $proxy1_port]
                assert_match "\{127.0.0.1:8888-*" [$proxy1c monitor SocketStats]
            }
        }
    }
}
