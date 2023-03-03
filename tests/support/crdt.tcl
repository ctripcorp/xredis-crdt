proc assert_log_file {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    if {[string match $pattern $content] != 1} {
        fail [format "assert log file %s content \n%s\n" $pattern $content]
    }
}