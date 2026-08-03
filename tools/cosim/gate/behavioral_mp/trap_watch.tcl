# trap_watch.tcl — negative-control harness for the core-features work.
# Drives a poison test (rv32ua-p-ext{mul,div,amo,rvc,zb}) on the STRIPPED
# build (every ENABLE_* generic false) and decides the verdict by watching
# hart 0 directly instead of waiting out the 100 ms testbench watchdog:
#   * trap_flag = '1' with a0 not at a verdict label  -> EXTOFF_TRAP_OK
#     (the disabled-extension instruction took the illegal-instruction trap)
#   * a0 = DEADBEEF  -> EXTOFF_SURVIVED (the instruction executed and fell
#     through to the test's explicit fail path — decode gating is broken)
#   * a0 = CAFEBABE  -> EXTOFF_UNEXPECTED_PASS (misa advertised the extension
#     on a stripped build — misa gating is broken)
# Chunked run + flush per the live-progress convention; xmsim `value` returns
# bit-strings WITH literal quote chars, so compares use quoted literals.
source ../../disable_x_warnings.tcl
set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""
set trap_path {:dut:hart0:core:trap_flag}
set a0_path   {:a0}
set verdict TIMEOUT
# 800 x 25 us = 20 ms budget: the SPI boot copy alone takes ~9.6 ms sim-time
# (verdicts land at ~9.7-9.9 ms); 20 ms gives 2x headroom.
for {set i 0} {$i < 800} {incr i} {
    run 25 us
    set av [value $a0_path]
    if {$av eq $dead_q} { set verdict SURVIVED;        break }
    if {$av eq $cafe_q} { set verdict UNEXPECTED_PASS; break }
    if {[string match {*1*} [value $trap_path]]} { set verdict TRAP_OK; break }
}
# pc is frozen in TRAP_STATE at the trapping instruction — cross-check it
# against the poison's address in the test's .dump.
puts "EXTOFF_VERDICT=$verdict (chunk $i) pc=[value :dut:hart0:core:pc]"
flush stdout
exit
