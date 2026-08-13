# =============================================================================
# gate_m7probe.tcl -- THE M7 QUESTION, ASKED BEFORE ANYTHING ELSE.
#
# d5_spec section 6: "The tb `component MCU` ends at `a0_3` -- the M7 question
# (does a hierarchical force reach the Verilog top's unconnected JTAG inputs?)
# is the implementer's FIRST gate-leg measurement; prefer forcing the Verilog
# nets over editing riscv_tb_gate.vhd, and STOP-AND-REPORT if neither works."
#
# WHY A SEPARATE PROBE RATHER THAN JUST RUNNING dbg_gateidc.tcl
#   Every force in dbg_tap.tcl is `catch`-wrapped (deliberately -- it is how the
#   BFM survives a tree with no TAP).  So a WRONG PATH SPELLING or a wrong value
#   literal does not raise: it silently does nothing, the scan shifts nothing,
#   and the leg reports IDCODE = 0x00000000.  That is the least informative
#   possible failure and the D3 author already paid for it once
#   (dbg_gateidc.tcl:88-93).  This file asks the question where the answer
#   cannot be swallowed: resolve, then FORCE, then READ BACK and compare.
#
# It grades nothing and asserts nothing about the chip.  It reports:
#   RESOLVE  <path>  ok|<error>          -- does the name exist at all
#   FORCE    <path> <literal> -> <read>  -- did the force take
# and ends with a one-line M7 VERDICT naming the spelling that works, or
# M7 VERDICT = UNREACHABLE, which is a STOP-AND-REPORT per the spec.
# =============================================================================
source ../../disable_x_warnings.tcl

proc m7_try_resolve {p} {
    if {[catch {value $p} v]} { return [list 0 $v] }
    return [list 1 $v]
}

puts "M7LOG ================ gate M7 probe: can a force reach the Verilog top's JTAG pins? ================"
flush stdout

# ---- 1. which spelling of the hierarchical path resolves at all -------------
# ':dut' is the VHDL instance label in riscv_tb_gate.vhd; the module it binds to
# is Verilog, so the separator INSIDE it is '.' and not ':'.  Both are tried,
# plus the fully-qualified forms, because being wrong here is silent.
# ':' is the TESTBENCH TOP -- the VHDL signals this flow's private
# riscv_tb_gate.vhd declares and hands to the DUT.  It is tried FIRST because
# it is the one the leg actually uses, and a probe that never exercises the
# spelling under test is decoration (the first draft of this file tried only
# the ':dut' family and reported a verdict about paths the leg does not use).
set prefixes [list ":" ":dut." ":dut:" "dut." ":riscv_tb.dut." ":riscv_tb:dut."]
set good_pfx ""
foreach pfx $prefixes {
    set allok 1
    foreach pin {tck tms tdi tdo trstn} {
        set r [m7_try_resolve "${pfx}${pin}"]
        if {[lindex $r 0]} {
            puts "M7LOG RESOLVE  ${pfx}${pin}  ok  value=[lindex $r 1]"
        } else {
            puts "M7LOG RESOLVE  ${pfx}${pin}  FAILED  ([lindex $r 1])"
            set allok 0
        }
    }
    if {$allok && $good_pfx eq ""} { set good_pfx $pfx }
    puts "M7LOG   -- prefix '$pfx': [expr {$allok ? {ALL FIVE RESOLVE} : {incomplete}}]"
    flush stdout
}

if {$good_pfx eq ""} {
    puts "M7LOG M7 VERDICT = UNREACHABLE (no spelling resolves all five JTAG pins)"
    puts "M7LOG   d5_spec section 6 says STOP-AND-REPORT here -- do not improvise."
    flush stdout
    exit
}
puts "M7LOG   first fully-resolving prefix: '$good_pfx'"

# ---- 2. does a FORCE actually take, and in which literal spelling ----------
# The BFM writes VHDL literals ('1'/'0').  On a Verilog net the accepted forms
# are 1'b1 / 1.  Each candidate is forced and then READ BACK -- the readback is
# the measurement; the absence of an error is not.
set tck "${good_pfx}tck"
set works {}
foreach lit [list "'1'" "1'b1" "1"] {
    catch {release $tck}
    set err ""
    if {[catch {force $tck $lit} err]} {
        puts "M7LOG FORCE    $tck  $lit  -> REFUSED ($err)"
        continue
    }
    set r [m7_try_resolve $tck]
    set rv [expr {[lindex $r 0] ? [lindex $r 1] : "unreadable"}]
    puts "M7LOG FORCE    $tck  $lit  -> readback $rv"
    # a force that took reads back as a 1 in whatever spelling this object uses
    if {[string match "*1*" $rv] && ![string match "*x*" $rv] && ![string match "*z*" $rv]} {
        lappend works $lit
    }
}
catch {release $tck}

# ---- 3. and does the DUT's TDO output remain READABLE (it is an output) -----
set r [m7_try_resolve "${good_pfx}tdo"]
puts "M7LOG TDO      ${good_pfx}tdo readable=[lindex $r 0] value=[lindex $r 1]"

if {[llength $works] == 0} {
    puts "M7LOG M7 VERDICT = RESOLVES BUT UNFORCEABLE (path '$good_pfx' resolves; no literal took)"
    puts "M7LOG   Fall back to the riscv_tb_gate.vhd copy in THIS directory (it is a"
    puts "M7LOG   private copy -- the standing genus_mp flow is untouched), or STOP."
} else {
    puts "M7LOG M7 VERDICT = REACHABLE  TAP_PFX='$good_pfx'  literals that took: $works"
}
flush stdout
exit
