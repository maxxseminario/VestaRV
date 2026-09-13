# VestaRV: negative-control harness for the core-features work. Drives a poison
# test (rv32ua-p-ext{mul,div,amo,rvc,zb}) on the stripped build, every ENABLE_*
# generic false, and reads the verdict off hart 0 rather than waiting out the
# 100 ms testbench watchdog.
#   trap_flag = '1' with a0 at no verdict label: EXTOFF_TRAP_OK, the disabled
#     instruction took the illegal-instruction trap.
#   a0 = DEADBEEF: EXTOFF_SURVIVED, it executed and fell through to the test's
#     fail path, so decode gating is broken.
#   a0 = CAFEBABE: EXTOFF_UNEXPECTED_PASS, misa advertised the extension on a
#     stripped build, so misa gating is broken.
# The run is chunked and flushed for live progress. xmsim `value` returns
# bit-strings carrying literal quote characters, so the compares quote too.
source ../../disable_x_warnings.tcl
set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""
set trap_path {:uut:dut:hart0:core:trap_flag}
set a0_path   {:uut:a0}
set verdict TIMEOUT
# 800 x 25 us = 20 ms. The SPI boot copy alone takes about 9.6 ms of sim time and
# verdicts land at 9.7 to 9.9 ms, so this is 2x headroom.
for {set i 0} {$i < 800} {incr i} {
    run 25 us
    set av [value $a0_path]
    if {$av eq $dead_q} { set verdict SURVIVED;        break }
    if {$av eq $cafe_q} { set verdict UNEXPECTED_PASS; break }
    if {[string match {*1*} [value $trap_path]]} { set verdict TRAP_OK; break }
}
# pc is frozen in TRAP_STATE at the trapping instruction. Cross-check it against
# the poison's address in the test's .dump.
puts "EXTOFF_VERDICT=$verdict (chunk $i) pc=[value :uut:dut:hart0:core:pc]"
flush stdout
exit
