proc assert_log_file {log pattern} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    assert_equal [string match $pattern $content] 1
}