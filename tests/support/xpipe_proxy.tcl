package require Tcl 8.5
package provide proxy 0.1

namespace eval xpipe_proxy {}
set ::xpipe_proxy::id 0
array set ::xpipe_proxy::fd {}
array set ::xpipe_proxy::addr {}
array set ::xpipe_proxy::blocking {}
array set ::xpipe_proxy::deferred {}
array set ::xpipe_proxy::reconnect {}
array set ::xpipe_proxy::callback {}
array set ::xpipe_proxy::state {} ;# State in non-blocking reply reading
array set ::xpipe_proxy::statestack {} ;# Stack of states, for nested mbulks

proc xpipe_proxy {{server 127.0.0.1} {port 80} {defer 0} } {
    set fd [socket $server $port]
    fconfigure $fd -translation binary
    set id [incr ::xpipe_proxy::id]
    
    set ::xpipe_proxy::fd($id) $fd
    set ::xpipe_proxy::addr($id) [list $server $port]
    
    set ::xpipe_proxy::blocking($id) 1
    set ::xpipe_proxy::deferred($id) $defer
    set ::xpipe_proxy::reconnect($id) 0
    ::xpipe_proxy::proxy_reset_state $id
    interp alias {} ::xpipe_proxy::xpipe_proxyHandle$id {} ::xpipe_proxy::__dispatch__ $id

}

proc ::xpipe_proxy::__dispatch__ {id method args} {
    set errorcode [catch {::xpipe_proxy::__dispatch__raw__ $id $method $args} retval]
    if {$errorcode && $::xpipe_proxy::reconnect($id) && $::xpipe_proxy::fd($id) eq {}} {
        # Try again if the connection was lost.
        # FIXME: we don't re-select the previously selected DB, nor we check
        # if we are inside a transaction that needs to be re-issued from
        # scratch.
        set errorcode [catch {::xpipe_proxy::__dispatch__raw__ $id $method $args} retval]
    }
    return -code $errorcode $retval
}

proc ::xpipe_proxy::__dispatch__raw__ {id method argv} {
    set fd $::xpipe_proxy::fd($id)
    # Reconnect the link if needed.
    if {$fd eq {}} {
        lassign $::xpipe_proxy::addr($id) host port
        set ::xpipe_proxy::fd($id) [socket $host $port]
        fconfigure $::xpipe_proxy::fd($id) -translation binary
        set fd $::xpipe_proxy::fd($id)
    }
    
    set blocking $::xpipe_proxy::blocking($id)
    set deferred $::xpipe_proxy::deferred($id)
    if {$blocking == 0} {
        if {[llength $argv] == 0} {
            error "Please provide a callback in non-blocking mode"
        }
        set callback [lindex $argv end]
        set argv [lrange $argv 0 end-1]
    }
    
    if {[info command ::xpipe_proxy::__method__$method] eq {}} {
        set cmd "$method"
        foreach a $argv {
            append cmd " $a"
        }
        append cmd "\r\n"
        ::xpipe_proxy::proxy_write $fd $cmd
        if {[catch {flush $fd}]} {
            set ::xpipe_proxy::fd($id) {}
            return -code error "I/O error reading reply"
        }
        if {!$deferred} {
            if {$blocking} {
                ::xpipe_proxy::redis_read_reply $id $fd
            } else {
                # Every well formed reply read will pop an element from this
                # list and use it as a callback. So pipelining is supported
                # in non blocking mode.
                lappend ::xpipe_proxy::callback($id) $callback
                fileevent $fd readable [list ::xpipe_proxy::proxy_readable $fd $id]
            }
        }
    } else {
        uplevel 1 [list ::xpipe_proxy::__method__$method $id $fd $argv] 
    }
}


proc ::xpipe_proxy::__method__blocking {id fd val} {
    set ::xpipe_proxy::blocking($id) $val
    fconfigure $fd -blocking $val
}

proc ::xpipe_proxy::__method__reconnect {id fd val} {
    set ::xpipe_proxy::reconnect($id) $val
}

proc ::xpipe_proxy::__method__read {id fd} {
    ::xpipe_proxy::proxy_read_reply $id $fd
}

proc ::redis::__method__write {id fd buf} {
    ::xpipe_proxy::proxy_write $fd $buf
}

proc ::xpipe_proxy::__method__flush {id fd} {
    flush $fd
}


proc ::xpipe_proxy::proxy_reset_state id {
    set ::xpipe_proxy::state($id) [dict create buf {} mbulk -1 bulk -1 reply {}]
    set ::xpipe_proxy::statestack($id) {}
}

proc ::xpipe_proxy::proxy_write {fd buf} {
    puts -nonewline $fd $buf
}

proc ::xpipe_proxy::proxy_read_reply {id fd} {
    set result [gets $fd]
    return $result
    # set type [read $fd 1]
    # switch -exact -- $type {
    #     : -
    #     + {redis_read_line $fd}
    #     - {return -code error [redis_read_line $fd]}
    #     $ {redis_bulk_read $fd}
    #     * {redis_multi_bulk_read $id $fd}
    #     default {
    #         if {$type eq {}} {
    #             set ::redis::fd($id) {}
    #             return -code error "I/O error reading reply"
    #         }
    #         return -code error "Bad protocol, '$type' as reply type byte"
    #     }
    # }
}

proc ::xpipe_proxy::xpipe_read_line fd {
    string trim [gets $fd]
}



proc ::xpipe_proxy::__method__ping {id fd argv} {
    set cmd "+PROXY PING\r\n"
    ::xpipe_proxy::proxy_write $fd $cmd
    if {[catch {flush $fd}]} {
        set ::xpipe_proxy::fd($id) {}
        return -code error "I/O error reading reply"
    }
    set type [read $fd 6]
    switch -exact -- $type {
        +PROXY {
            xpipe_read_line $fd
        }
        default {
            if {$type eq {}} {
                set ::redis::fd($id) {}
                return -code error "I/O error reading reply"
            }
            return -code error "Bad protocol, '$type' as reply type byte"
        }
    }
}

proc ::xpipe_proxy::__method__route {id fd argv} {
    set cmd "+PROXY ROUTE"
    foreach a $argv {
        append cmd " $a"
    }
    append cmd "\r\n"
    puts $cmd
    ::xpipe_proxy::proxy_write $fd $cmd
    if {[catch {flush $fd}]} {
        set ::xpipe_proxy::fd($id) {}
        return -code error "I/O error reading reply"
    }
}

#about redis

proc ::xpipe_proxy::redis_readnl {fd len} {
    set buf [read $fd $len]
    read $fd 2 ; # discard CR LF
    return $buf
}

proc ::xpipe_proxy::redis_bulk_read {fd} {
    set count [redis_read_line $fd]
    if {$count == -1} return {}
    set buf [redis_readnl $fd $count]
    return $buf
}

proc ::xpipe_proxy::redis_read_line fd {
    string trim [gets $fd]
}

proc ::xpipe_proxy::redis_read_reply {id fd} {
    set type [read $fd 1]
    switch -exact -- $type {
        : -
        + {redis_read_line $fd}
        - {return -code error [redis_read_line $fd]}
        $ {redis_bulk_read $fd}
        * {redis_multi_bulk_read $id $fd}
        default {
            if {$type eq {}} {
                set ::redis::fd($id) {}
                return -code error "I/O error reading reply"
            }
            return -code error "Bad protocol, '$type' as reply type byte"
        }
    }
}

proc ::xpipe_proxy::redis_multi_bulk_read {id fd} {
    set count [redis_read_line $fd]
    if {$count == -1} return {}
    set l {}
    set err {}
    for {set i 0} {$i < $count} {incr i} {
        if {[catch {
            lappend l [redis_read_reply $id $fd]
        } e] && $err eq {}} {
            set err $e
        }
    }
    if {$err ne {}} {return -code error $err}
    return $l
}


#monitor

proc ::xpipe_proxy::__method__monitor {id fd argv} {
    set cmd "+PROXY MONITOR "
    foreach a $argv {
        append cmd " $a"
    }
    append cmd "\r\n"
    puts $cmd
    ::xpipe_proxy::proxy_write $fd $cmd
     if {[catch {flush $fd}]} {
        set ::xpipe_proxy::fd($id) {}
        return -code error "I/O error reading reply"
    }
    ::xpipe_proxy::redis_read_reply $id $fd
}

proc ::xpipe_proxy::__method__closeChannel {id fd argv} {
    set cmd "+PROXY CLOSECHANNEL"
    foreach a $argv {
        append cmd $argv
    }
    append cmd "\r\n"
    puts $cmd
    ::xpipe_proxy::proxy_write $fd $cmd
    if {[catch {flush $fd}]} {
        set ::xpipe_proxy::fd($id) {}
        return -code error "I/O error reading reply"
    }
    return [gets $fd]
}