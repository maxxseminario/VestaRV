# =============================================================================
# dbg_verdict.tcl -- run a test to its verdict and print hart 0's a0/a1/a2/a3.
#
# riscv_tb reports only a0 (PASS/FAIL).  Every D1 instrument encodes WHICH
# assertion failed in a1 (and detail in a2/a3), exactly as idcsrmp and rocsrw
# do, so a FAIL that cannot be read is a FAIL that cannot be diagnosed.
#
#   XRUN_MODE=batch XRUN_EXTRA_INPUT=dbg_verdict.tcl ./xrun.sh <test-pattern>
#
# Chunked so a hang is visible within seconds rather than at the 100 ms
# testbench watchdog (the live-progress convention).  60 ms of budget: a
# healthy MP test verdicts at ~25 ms sim, and the SPI boot copy alone is
# ~9.6 ms of that.
# =============================================================================
source ../../disable_x_warnings.tcl

set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""

proc hex32 {bits} {
    set b [string map {\" ""} $bits]
    if {![regexp {^[01]{32}$} $b]} { return $bits }
    return [format "0x%08X" [expr {"0b$b"}]]
}

set verdict TIMEOUT
for {set i 0} {$i < 2400} {incr i} {
    run 25 us
    set av [value :a0]
    if {$av eq $dead_q} { set verdict FAILED; break }
    if {$av eq $cafe_q} { set verdict PASSED; break }
}

set out "DBGVERDICT verdict=$verdict t=[expr {($i+1)*25}]us"
foreach {tag idx} {a0 10 a1 11 a2 12 a3 13} {
    if {[catch {value :dut:hart0:core:datapath_inst:rf:registers($idx)} v]} {
        set v "ERR"
    } else {
        set v [hex32 $v]
    }
    append out " $tag=$v"
}
puts $out
foreach {tag sig} {h1pc {:dut:hart1:core:pc} h1st {:dut:hart1:core:current_state} \
                   h2pc {:dut:hart2:core:pc} h2st {:dut:hart2:core:current_state} \
                   h3pc {:dut:hart3:core:pc} h3st {:dut:hart3:core:current_state}} {
    if {[catch {value $sig} v]} { set v "ERR" }
    if {[string match {*pc} $tag]} { set v [hex32 $v] }
    puts "DBGVERDICT   $tag=$v"
}
flush stdout
exit
