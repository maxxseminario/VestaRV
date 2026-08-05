# =============================================================================
# dbg_rst.tcl -- the D1 HALT-ON-RESET instrument.  Structural, graded by grep,
# and it needs NO test software of its own.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_rst.tcl
#
# WHY IT CARRIES NO IMAGE.  d1_spec.md 2 makes dbg_resethaltreq an entry cause
# sampled at reset release, "before the first instruction retires".  On this
# chip DEBUG_ENTRY_ADDR is inside the private TCM, and at reset the TCM is
# UNINITIALISED -- so a hart halted on reset would execute X.  A debug ROM is
# D4's, not D1's.  Halt-on-reset is therefore only checkable STRUCTURALLY at
# D1: did dbg_halted rise, did it rise before the hart retired anything, and
# does dcsr.cause say 5?  None of that needs a program, so this harness rides
# whatever test is running on hart 0 and observes hart 1.
#
# WHAT IT CHECKS
#   R1  dbg_resethaltreq held across reset release raises dbg_halted on hart 1
#   R2  hart 1's pc is DEBUG_ENTRY_ADDR when it halts
#   R3  hart 1 never left PC_RST_VAL for the boot ROM first -- i.e. it halted
#       BEFORE running any instruction.  Measured as: hart 1's pc is never
#       observed inside the boot ROM's post-reset stretch (0x4..0x1FF) on any
#       sample before dbg_halted rises.  Sampled every 500 ns from time 0,
#       which is ~12 mclk at 24 MHz -- fine enough to see a hart that boots.
#   R4  hart 0 is UNAFFECTED: its own test still reaches its verdict, so a
#       halt-on-reset on one tile is not a chip-wide event.
#
# Grade by grep: PASS iff RSTLOG VERDICT=PASS.  At unimplemented HEAD it prints
# RSTLOG PORT_ABSENT and VERDICT=INSTRUMENT_DEAD -- the part-1 seen-to-FAIL leg.
# =============================================================================
source ../../disable_x_warnings.tcl

set RRQ ":dut:hart1:dbg_resethaltreq"
set HLT ":dut:hart1:dbg_halted"
set PC  ":dut:hart1:core:pc"
set DBG_ENTRY 0xBE00

proc hex32 {bits} {
    set b [string map {\" ""} $bits]
    if {![regexp {^[01]{32}$} $b]} { return $bits }
    return [format "0x%08X" [expr {"0b$b"}]]
}
proc pcv {p} {
    if {[catch {value $p} v]} { return -1 }
    set b [string map {\" ""} $v]
    if {![regexp {^[01]{32}$} $b]} { return -1 }
    return [expr {"0b$b"}]
}

set fails 0
if {[catch {value $HLT} e]} {
    puts "RSTLOG PORT_ABSENT path=$HLT err=$e"
    puts "RSTLOG VERDICT=INSTRUMENT_DEAD (no D1 debug interface in this build)"
    flush stdout
    exit
}
if {[catch {force $RRQ '1'} e]} {
    puts "RSTLOG FORCE_REFUSED path=$RRQ err=$e"
    puts "RSTLOG VERDICT=INSTRUMENT_DEAD"
    flush stdout
    exit
}
puts "RSTLOG resethaltreq forced high from time 0"

# ---- R1/R2/R3: watch hart 1 from time 0 ------------------------------------
set halted 0
set ranrom 0
set pcat -1
for {set i 0} {$i < 400} {incr i} {
    run 500 ns
    set p [pcv $PC]
    if {$p > 0 && $p < 0x200} { set ranrom 1 }
    set v [value $HLT]
    if {[string match {*1*} $v]} { set halted 1; set pcat $p; break }
}
puts [format "RSTLOG R1 halted=%d after %d x 500ns  pc=0x%08X  ran_bootrom_first=%d" \
      $halted $i [expr {$pcat < 0 ? 0 : $pcat}] $ranrom]
if {!$halted} { puts "RSTLOG CHECK FAILED R1: dbg_halted never rose"; incr fails }
if {$halted && $pcat != $DBG_ENTRY} {
    puts [format "RSTLOG CHECK FAILED R2: pc at halt is 0x%08X, expected 0x%08X" $pcat $DBG_ENTRY]
    incr fails
}
if {$ranrom} { puts "RSTLOG CHECK FAILED R3: hart 1 executed boot ROM before halting"; incr fails }
catch {release $RRQ}
flush stdout

# ---- R4: hart 0's own test must still reach its verdict --------------------
set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""
set verdict TIMEOUT
for {set i 0} {$i < 2400} {incr i} {
    run 25 us
    set av [value :a0]
    if {$av eq $dead_q} { set verdict FAILED; break }
    if {$av eq $cafe_q} { set verdict PASSED; break }
}
puts "RSTLOG R4 hart0 verdict=$verdict"
if {$verdict ne "PASSED"} { puts "RSTLOG CHECK FAILED R4: hart 0 disturbed"; incr fails }

if {$fails == 0} { puts "RSTLOG VERDICT=PASS" } else { puts "RSTLOG VERDICT=FAIL ($fails checks)" }
flush stdout
exit
