# TEMP shtimer post-mortem: run to the failure assertion, then dump hart 0's
# registers. All shtimer fail paths converge on one spin, but s2 holds the
# peripheral base in use and t0-t6 the last comparison values -> identifies
# the failing check. (xmsim `value` returns bit-strings WITH quote chars.)
source ../../disable_x_warnings.tcl
run
puts "== POSTMORTEM hart0 regs =="
foreach r {1 5 6 7 10 18 19 23 28 29 30 31} {
    set v "?"
    if {[catch { set v [value :dut:core:datapath_inst:rf:registers($r)] } err]} {
        set v "ERR: $err"
    }
    puts "x$r = $v"
}
flush stdout
exit
