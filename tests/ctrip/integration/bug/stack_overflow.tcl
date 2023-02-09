start_server {tags {"crdt-basic"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    set master_config_file [srv 0 config_file]
    set master_config [srv 0 config]

    test "set counter big value" {
        $master set k 0 
        $master incr k 
        $master set k [randstring 20000000 30000000]
        assert_equal [$master ping] PONG
    }


}