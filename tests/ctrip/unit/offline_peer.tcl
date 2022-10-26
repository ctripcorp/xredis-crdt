start_server {
    tags {"offline command"}
    overrides {crdt-gid 1} config {crdt.conf} module {crdt.so}
} {
    test "add offline peer" {
        assert_equal [r crdt.setOfflineGid 2 3 4 5] "OK"
        assert_equal [r crdt.getOfflineGid] "2 3 4 5"

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