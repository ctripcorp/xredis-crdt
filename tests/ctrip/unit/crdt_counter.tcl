proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}
start_server {tags {"master"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    set master_gid  1
    start_server {tags {"peer"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        set peer_log [srv 0 stdout]
        set peer_gid 2
        
        $peer peerof $master_gid $master_host $master_port
        wait_for_peer_sync $peer
        test "set -> incr -> set" {
            test "set -> peer" {
                $master set k 10
                after 1000
                assert_equal [ $master get k ] 10
                # catch {[$peer get k]} error
                # print_log_file $peer_log
                assert_equal [$peer get k] 10
            }
            test "incr" {
                $master incrby k 1
                after 1000
                catch {[$peer get k]} error
                assert_equal [ $master get k ] 11
                assert_equal [$peer get k] 11
            }
            test "incr after set" {
                $master set k 20
                
                after 1000
                assert_equal [ $master get k ] 20
                print_log_file $peer_log
                puts [$master crdt.get k]
                puts [$peer crdt.get k]
                assert_equal [$peer get k] 20
            }
        }
        
        test "type error" {
            test "set int -> set sds" {
                $master set err1 100
                set _ [catch {
                    $master set err1 a
                } retval]
                assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
            }
            test "set float -> set sds" {
                $master set err2 1.1
                set _ [catch {
                    $master set err1 a
                } retval]
                assert_equal $retval "WRONGTYPE Operation against a key holding the wrong kind of value"
            }
            test "set float -> set sds" {
                $master set err3 a
                set _ [catch {
                    $master incrby err3 1
                } retval]
                assert_equal $retval "ERR value is not an integer or out of range"
            }
            test "set float -> incrby" {
                $master set err4 1.1
                set _ [catch {
                    $master incrby err4 1
                } retval]
                assert_equal $retval "ERR value is not an integer or out of range"
            }
        }
        test  "type is register" {
            test "set register , set int, incrby" {
                $master set register1 a
                $master set register1 1
                assert_equal [$master get register1] 1
                after 1000
                assert_equal [$peer get register1] 1
                set _ [catch {
                    $master incrby register1 1
                } retval]
                assert_equal $retval "ERR value is not an integer or out of range"
            }
        }
        
        test "del" {
            $master set del1 1
            $master incrby del1 2
            assert_equal [$master get del1] 3
            $master del del1
            assert_equal [$master get del1] {}
            after 1000
            print_log_file $peer_log
            assert_equal [$peer get del1] {}
        }
    }
}