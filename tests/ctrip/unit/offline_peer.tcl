start_server {
    tags {"offline command"}
    overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
} {
    set config_file [srv 0 config_file] 
    test "add offline peer" {
        assert_equal [r crdt.setOfflineGid 2 3 4 5] "OK"
        assert_equal [r crdt.getOfflineGid] "2 3 4 5"

        assert_equal [r crdt.setOfflineGid] "OK"
        assert_equal [r crdt.getOfflineGid] ""
    }

    test "add offline rewrite config file" {
        exec chmod 400 $config_file
        assert_equal [r crdt.setOfflineGid 2 3 4 5] "OK,but save config fail"
        exec chmod 777 $config_file

        assert_equal [r crdt.setOfflineGid] "OK"
        assert_equal [r crdt.getOfflineGid] ""
    }

    test "add offline peer param error - gid is not int" {
        catch {r crdt.setOfflineGid a} retval
        assert_equal $retval "ERR value is not an integer or out of range"
        catch {r crdt.setOfflineGid 1 a} retval
        assert_equal $retval "ERR value is not an integer or out of range"
    }

    test "add offline peer param error - gid > 16" {
        catch {r crdt.setOfflineGid 100} retval
        assert_equal $retval "ERR peer gid invalid"
    }
}

start_server {
    tags {" sync offlinegid (master-> slave)"}
    overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    test "sync offlinegid - partial sync " {
        start_server {
            tags {"slave"}
            overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
        } {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]

            $slave slaveof $master_host $master_port
            wait_for_sync $slave 
            assert_equal [$slave crdt.getOfflineGid] ""
            
            #set
            assert_equal [$master crdt.setOfflineGid 2 3 4] "OK"
            after 200
            assert_equal [$slave crdt.getOfflineGid] "2 3 4"
        
            assert_equal [$master crdt.setOfflineGid] "OK"
            after 200
            assert_equal [$slave crdt.getOfflineGid] ""
        }
    }

    test "sync offlinegid - full sync " {
        $master crdt.setOfflineGid 2 3 4 5
        start_server {
            tags {"slave"}
            overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
        } {
            set slave [srv 0 client]
            set slave_host [srv 0 host]
            set slave_port [srv 0 port]

            $slave slaveof $master_host $master_port
            wait_for_sync $slave 

            assert_equal [$slave crdt.getOfflineGid] "2 3 4 5"

        }
    }
}



# 1<<2 + 1<<4 + 1<<5 == 52
start_server {
    tags {" config offlinegid "}
    overrides {crdt-gid 1 crdt-offline-gid 52} config {crdt.conf} module {crdt.so} 
} {
    set master [srv 0 client]
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_config_file [srv 0 config_file]
    set master_config [srv 0 config]
    set master_stdout [srv 0 stdout]
    set master_stderr [srv 0 stderr]
    test "load config offline gid" {
        assert_equal [$master crdt.getOfflineGid] "2 4 5"
    
        assert_equal [lindex [$master config get crdt-offline-gid] 1] 52
    }

    
    test "rewrite config" {
        $master crdt.setOfflineGid 2 3 4 5
        $master config rewrite
        # restart server
        catch {$master shutdown} error 
        start_server_by_config $master_config_file $master_config $master_host $master_port $master_stdout $master_stderr 1 {
            set master [redis $master_host $master_port]
            $master select 9
            after 2000
            assert_equal [$master crdt.getOfflineGid] "2 3 4 5"
            
        }
    }
}