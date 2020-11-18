start_server {tags {"repl"} config {crdt.conf} overrides {crdt-gid 1 repl-diskless-sync-delay 1} module {crdt.so}} {
    test {INCR against non existing key} {
        set res {}
        append res [r incr novar]
        append res [r get novar]
    } {11}

    test {INCR against key created by incr itself} {
        r incr novar
    } {2}

    test {INCR against key originally set with SET} {
        r set novar 100
        r incr novar
    } {101}

    test {INCR over 32bit value} {
        r set novar 17179869184
        r incr novar
    } {17179869185}

    test {INCRBY over 32bit value with over 32bit increment} {
        r set novar 17179869184
        r incrby novar 17179869184
    } {34359738368}

    test {INCR fails against key with spaces (left)} {
        r set novar_1 "    11"
        catch {r incr novar_1} err
        format $err
    } {ERR*}

    test {INCR fails against key with spaces (right)} {
        r set novar_1 "11    "
        catch {r incr novar_1} err
        format $err
    } {ERR*}

    test {INCR fails against key with spaces (both)} {
        r set novar_1 "    11    "
        catch {r incr novar_1} err
        format $err
    } {ERR*}

    test {INCR fails against a key holding a list} {
        r hset myhash h 1
        catch {r incr myhash} err
        r hdel myhash h
        format $err
    } {WRONGTYPE*}

    test {DECRBY over 32bit value with over 32bit increment, negative res} {
        r set novar 17179869184
        r decrby novar 17179869185
    } {-1}

    test {INCR uses shared objects in the 0-9999 range} {
        r set foo -1
        r incr foo
        # assert {[r object refcount foo] > 1}
        r set foo 9998
        r incr foo
        # assert {[r object refcount foo] > 1}
        r incr foo
        # assert {[r object refcount foo] == 1}
    }

    test {INCR can modify objects in-place} {
        r set foo 20000
        r incr foo
        # assert {[r object refcount foo] == 1}
        # set old [lindex [split [r debug object foo]] 1]
        r incr foo
        # set new [lindex [split [r debug object foo]] 1]
        # assert {[string range $old 0 2] eq "at:"}
        # assert {[string range $new 0 2] eq "at:"}
        # assert {$old eq $new}
    }

    test {INCRBYFLOAT against non existing key} {
        r del novar
        list    [roundFloat [r incrbyfloat novar 1]] \
                [roundFloat [r get novar]] \
                [roundFloat [r incrbyfloat novar 0.25]] \
                [roundFloat [r get novar]]
    } {1 1 1.25 1.25}

    test {INCRBYFLOAT against key originally set with SET} {
        r set novar 1.5
        roundFloat [r incrbyfloat novar 1.5]
    } {3}

    test {INCRBYFLOAT over 32bit value} {
        r set novar 17179869184
        r incrbyfloat novar 1.5
    } {17179869185.5}

    test {INCRBYFLOAT over 32bit value with over 32bit increment} {
        r set novar 17179869184
        r incrbyfloat novar 17179869184
    } {34359738368}

    test {INCRBYFLOAT fails against key with spaces (left)} {
        set err {}
        r set novar_1 "    11"
        catch {r incrbyfloat novar_1 1.0} err
        format $err
    } {ERR*valid*}

    test {INCRBYFLOAT fails against key with spaces (right)} {
        set err {}
        r set novar_1 "11    "
        catch {r incrbyfloat novar_1 1.0} err
        format $err
    } {ERR*valid*}

    test {INCRBYFLOAT fails against key with spaces (both)} {
        set err {}
        r set novar_1 " 11 "
        catch {r incrbyfloat novar_1 1.0} err
        format $err
    } {ERR*valid*}

    test {INCRBYFLOAT fails against a key holding a list} {
        r del myhash
        set err {}
        r hset myhash h 1
        catch {r incrbyfloat myhash 1.0} err
        r hdel myhash h
        format $err
    } {WRONGTYPE*}

    test {INCRBYFLOAT does not allow NaN or Infinity} {
        r set foo 0
        set err {}
        catch {r incrbyfloat foo +inf} err
        set err
        # p.s. no way I can force NaN to test it from the API because
        # there is no way to increment / decrement by infinity nor to
        # perform divisions.
    } {ERR*would produce*}

    test {INCRBYFLOAT decrement} {
        r set foo 1
        roundFloat [r incrbyfloat foo -1.1]
    } {-0.1}

    # test {string to double with null terminator} {
    #     r set foo 1
    #     r setrange foo 2 2
    #     catch {r incrbyfloat foo 1} err
    #     format $err
    # } {ERR*valid*}


    test "incrbyfloat" {
        # (1.0 1.1 1 abc) * (null int float str)
        test "null" {
            r incrbyfloat  "key_is_null_1.0" 1.0
            assert_equal [r get "key_is_null_1.0" ] 1
            r incrbyfloat  "key_is_null_1.1" 1.1
            assert_equal [r get "key_is_null_1.1" ] 1.1
            r incrbyfloat  "key_is_null_1" 1
            assert_equal [r get "key_is_null_1" ] 1
            catch {r incrbyfloat  "key_is_null_abc" abc} error 
            assert_equal [r get "key_is_null_abc" ] {}
        } 
        test "int-1" {
            r set "key_is_int_1.0" 1
            r incrbyfloat  "key_is_int_1.0" 1.0
            assert_equal [r get "key_is_int_1.0" ] 2

            r set "key_is_int_1.1" 1
            r incrbyfloat  "key_is_int_1.1" 1.1
            assert_equal [r get "key_is_int_1.1" ] 2.1

            r set "key_is_int_1" 1
            r incrbyfloat  "key_is_int_1" 1
            assert_equal [r get "key_is_int_1" ] 2

            r set "key_is_int_abc" 1
            catch {r incrbyfloat  "key_is_int_abc" abc} error
            assert_equal [r get "key_is_int_abc" ] 1
        }

        test "int-2" {
            r set "key_is_int1_1.0" 1.0
            r incrbyfloat  "key_is_int1_1.0" 1.0
            assert_equal [r get "key_is_int1_1.0" ] 2

            r set "key_is_int1_1.1" 1.0
            r incrbyfloat  "key_is_int1_1.1" 1.1
            assert_equal [r get "key_is_int1_1.1" ] 2.1

            r set "key_is_int1_1" 1.0
            r incrbyfloat  "key_is_int1_1" 1
            assert_equal [r get "key_is_int1_1" ] 2

            r set "key_is_int1_abc" 1.0
            catch {r incrbyfloat  "key_is_int1_abc" abc} error
            assert_equal [r get "key_is_int1_abc" ] 1
        }

        test "float-2" {
            r set "key_is_float_1.0" 1.1
            r incrbyfloat  "key_is_float_1.0" 1.0
            assert_equal [r get "key_is_float_1.0" ] 2.1

            r set "key_is_float_1.1" 1.1
            r incrbyfloat  "key_is_float_1.1" 1.1
            assert_equal [r get "key_is_float_1.1" ] 2.2

            r set "key_is_float_1" 1.1
            r incrbyfloat  "key_is_float_1" 1
            assert_equal [r get "key_is_float_1" ] 2.1

            r set "key_is_float_abc" 1.1
            catch {r incrbyfloat  "key_is_float_abc" abc} error
            assert_equal [r get "key_is_float_abc" ] 1.1
        }
    }
    test "int_max_and_min" {
        test "max" {
            r incrby int_max 576460752303423487
            assert_equal [r get int_max] 576460752303423487
            catch {r incr int_max 1} error
            assert_equal [r get int_max] 576460752303423487
            catch {r incrby int_max 1} error
            assert_equal [r get int_max] 576460752303423487
        }
        
        test "min" {
            r incrby int_min -576460752303423488
            assert_equal [r get int_min] -576460752303423488
            catch {r decr int_min 1} error
            assert_equal [r get int_min] -576460752303423488
            catch {r incrby int_max -1} error
            assert_equal [r get int_min] -576460752303423488
        }

        
    }
}


