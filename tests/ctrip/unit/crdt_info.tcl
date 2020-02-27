proc get_info_field {info field} {
    set fl [string length $field]
    append field :
    foreach line [split $info "\n"] {
        set line [string trim $line "\r\n "]
        if {[string range $line 0 $fl] eq $field} {
            return [string range $line [expr {$fl+1}] end]
        }
    }
    return {}
}

start_server {tags {"repl"} overrides {crdt-gid 1} module {crdt.so} } {

    test {"[crdt_info.tcl]info stats"} {
        set stats [r info stats]
        get_info_field $stats "instantaneous_write_kbps"
    } {0.00}

}