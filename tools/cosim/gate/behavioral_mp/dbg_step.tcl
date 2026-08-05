# =============================================================================
# dbg_step.tcl -- the D1 step harness for rv32ua-p-dbgstepmp.
#
#   ./xrun_dbg.sh rv32ua-p-dbgstepmp dbg_step.tcl
#
# ONE external event in the whole run: a single halt request on hart 1, held
# until dbg_halted rises and then released.  Everything after that -- writing
# dpc, arming dcsr.step, four single steps, arming dcsr.ebreakm, the ebreak
# entry and the final dret -- is driven by the debug stub the test planted at
# DEBUG_ENTRY_ADDR.  See dbgstepmp.S's header.
#
# ARMING IS STRUCTURAL, NOT TIMED.  The subject parks in a one-instruction
# self-loop (`h1_wait: j h1_wait`) and stays there until halted, so the harness
# fires when it OBSERVES hart 1's pc land in the same 16-byte window on two
# consecutive samples.  A tight loop is the only way that happens, and the loop
# is absorbing, so sampling early just loops again.  Nothing is calibrated: the
# stub rewrites dpc on entry 1, so it does not matter WHERE in the loop the
# request lands (method rule 7).
#
# THE ONE REQUEST IS NEVER RE-ARMED, and since R-D1-2(1b) it does not need to
# be.  The implemented core carries WAIT-FOR-RELEASE on dbg_haltreq (the
# mp_arbiter `need_release` idiom): a continuously held request produces
# exactly ONE entry.  Single-step would be impossible otherwise -- the second
# entry would report cause haltreq instead of cause step.  This harness drops
# the request anyway, as a debugger would.
#
# DIAGNOSTICS, all named (corrected 2026-08-05, method rule 12 -- the old
# NO_HALTED line fired spuriously because a 25 us poll steps straight over a
# halt window that wait-for-release keeps microseconds long):
#   STEPLOG PORT_ABSENT       the debug ports do not exist -- the part-1
#                             seen-to-FAIL leg
#   STEPLOG HALT_NOT_SAMPLED  no sample caught dbg_halted high AND the test
#                             PASSED.  BENIGN, never counted as a failure.
#   STEPLOG NO_HALTED         no sample caught it high AND the test FAILED.
#   STEPLOG SPIN_TIMEOUT      hart 1 never settled into a loop (image, not RTL)
# =============================================================================
source ../../disable_x_warnings.tcl

set REQ ":dut:hart1:dbg_haltreq"
set HLT ":dut:hart1:dbg_halted"
set PC  ":dut:hart1:core:pc"

set PORTS 1
if {[catch {value $HLT} e]} {
    puts "STEPLOG PORT_ABSENT path=$HLT err=$e"
    puts "STEPLOG VERDICT=INSTRUMENT_DEAD (no D1 debug interface in this build)"
    flush stdout
    set PORTS 0
}

proc pcw {p} {
    if {[catch {value $p} v]} { return -1 }
    set b [string map {\" ""} $v]
    if {![regexp {^[01]{32}$} $b]} { return -1 }
    return [expr {[expr {"0b$b"}] & ~15}]
}

set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""

# ---- 1. wait for hart 1 to settle into its self-loop -----------------------
set prev -2
set armed 0
for {set i 0} {$i < 1600} {incr i} {
    run 25 us
    set w [pcw $PC]
    if {$w >= 0x8200 && $w == $prev} { set armed 1; break }
    set prev $w
}
puts [format "STEPLOG arm i=%d armed=%d pcwindow=0x%08X" $i $armed [expr {$prev < 0 ? 0 : $prev}]]
flush stdout
if {!$armed} { puts "STEPLOG SPIN_TIMEOUT -- hart 1 never settled; the image, not the RTL" }

# ---- 2. one halt request, released as soon as it is acknowledged -----------
set halted 0
if {$PORTS} {
    if {[catch {force $REQ '1'} e]} {
        puts "STEPLOG FORCE_REFUSED err=$e"
    } else {
        # 500 ns per sample (~12 mclk), 4000 samples = 2 ms -- fine enough to
        # land inside a halt window only a few microseconds long.
        for {set i 0} {$i < 4000} {incr i} {
            run 500 ns
            if {[catch {value $HLT} v]} { break }
            if {[string match {*1*} $v]} {
                set halted 1
                catch {release $REQ}
                puts "STEPLOG halted at sample $i -- request released"
                break
            }
        }
    }
    flush stdout
}

# ---- 3. run to the test's own verdict --------------------------------------
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
set out "STEPLOG VERDICT=$verdict"
foreach {tag idx} {a0 10 a1 11 a2 12 a3 13} {
    if {[catch {value :dut:hart0:core:datapath_inst:rf:registers($idx)} v]} {
        set v ERR
    } else { set v [hex32 $v] }
    append out " $tag=$v"
}
if {$PORTS && !$halted} {
    if {$verdict eq "PASSED"} {
        puts "STEPLOG HALT_NOT_SAMPLED -- no sample caught dbg_halted high, but the"
        puts "STEPLOG   test PASSED, so all six debug entries happened.  BENIGN."
    } else {
        puts "STEPLOG NO_HALTED -- request raised, dbg_halted never sampled high,"
        puts "STEPLOG   and the test FAILED.  This is the finding."
    }
}
puts $out
puts "STEPLOG   hart1 pc=[hex32 [value $PC]] state=[value :dut:hart1:core:current_state]"
flush stdout
exit
