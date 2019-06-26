start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so}} {
    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        test {First server should have role slave after SLAVEOF} {
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 master_link_status] eq {up}
            } else {
                fail "Replication not started."
            }
        }

        if {$::accurate} {set numops 50000} else {set numops 5000}

        #todo: active this test case, when set allow expire
        #test {Slave is able to evict keys created in writable slaves} {
         #   r -1 select 5
          #  assert {[r -1 dbsize] == 0}
           # r -1 config set slave-read-only no
            #r -1 set key1 1 ex 5
            #r -1 set key2 2 ex 5
            #r -1 set key3 3 ex 5
            #assert {[r -1 dbsize] == 3}
            #after 6000
            #r -1 dbsize
        #} {0}
    }
}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so}} {
    start_server {overrides {crdt-gid 1} module {crdt.so}} {
        test {First server should have role slave after SLAVEOF} {
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 master_link_status] eq {up}
            } else {
                fail "Replication not started."
            }
        }

        set numops 20000 ;# Enough to trigger the Script Cache LRU eviction.

        # While we are at it, enable AOF to test it will be consistent as well
        # after the test.
        r config set appendonly yes



        test {SLAVE can reload "lua" AUX RDB fields of duplicated scripts} {
            # Force a Slave full resynchronization
            r debug change-repl-id
            r -1 client kill type master

            # Check that after a full resync the slave can still load
            # correctly the RDB file: such file will contain "lua" AUX
            # sections with scripts already in the memory of the master.

            wait_for_condition 50 100 {
                [s -1 master_link_status] eq {up}
            } else {
                fail "Replication not started."
            }

            wait_for_condition 50 100 {
                [r debug digest] eq [r -1 debug digest]
            } else {
                fail "DEBUG DIGEST mismatch after full SYNC with many scripts"
            }
        }
    }
}
