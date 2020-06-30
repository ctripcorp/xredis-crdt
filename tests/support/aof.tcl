proc cp_crdt_so {server_path} {
    set module_path [exec pwd]
    append module_path "/tests/assets/"
    set uname_S [exec uname -s]
    if {$uname_S eq "Darwin"} {
        append module_path "mac/"
    } elseif {$uname_S eq "Linux"} {
        append module_path "linux/"
    }
    append module_path "crdt.so"
    exec cp $module_path $server_path
}