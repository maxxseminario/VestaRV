# =============================================================================
# dbg_tapdtm.tcl -- D3 instrument T3: DTM REGISTER AND CROSSING SEMANTICS.
# Everything in d3_spec section 2 and d3_cdc_spec sections 2-4 that is
# observable from the four pins: dtmcs fields, the sticky machine in both of
# its flavours, dmireset, dmihardreset with its discard clause, the Capture-DR
# previous-result rule, and THE ONE-SHOT CLAUSE.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_tapdtm.tcl
#
# BLIND-AUTHORED 2026-08-06 against d3_spec.md 2 and d3_cdc_spec.md 2-4 (FROZEN).
#
# THE ONE-SHOT CLAUSE IS THE POINT OF THIS FILE.  d3_cdc_spec 2 calls the
# duplicate accept "the crossing's sharpest defect class" and it is invisible
# to every other instrument: a DM that accepts the same request twice returns
# two responses, the second of which usually carries the same value, so a
# harness that only reads results sees nothing at all.  It is instrumented here
# by COUNTING ACCEPTS, not by reading results -- the MCU's `dmi_req_ready`
# output is the DM's one-cycle acknowledge (debug_module.vhd:764, `ready_r`,
# verified registered at authoring time), d3_cdc_spec 7 fans the DM's responses
# out to BOTH masters, and one rising edge on it IS one accept.
#
# The provocation is not synthetic.  The re-capture lockout in the DM is a
# TIMER, not an observed-low discipline: the guard is `rsp_hold = 0 and
# rsp_arm = '0'` and the window RE-OPENS 9 mclk after a capture (re-derived
# independently at authoring time from debug_module.vhd:814-827 and :1121-1123;
# RSP_HOLD_CYCLES = 7 at :384).  A DD4-idiomatic master that held the request
# level until its response came back would hold it far longer than 9 mclk --
# the response has to cross a 3-flop chain into the TCK domain, which at ANY
# sane TCK rate is longer -- and would earn a second accept.  So the ordinary,
# most common transaction shape is the dangerous one, and D19/D20 use exactly
# that.  Nothing here needs a special sequence to provoke it.
#
# CHECK LIST (D-numbers; the runner greps for "CHECK FAILED"):
#   D0  the five JTAG pins exist                (else INSTRUMENT_DEAD)
#   D1  dtmcs at rest: version 1, abits 7, dmistat 0 -- the 0x71 base
#   D2  a plain DMI read through the TAP succeeds and returns a sane dmstatus
#   D3  Capture-DR returns the PREVIOUS op's result with the ADDRESS PRESERVED
#   D4  ...and a second, different address proves D3 is not a hardwired field
#   D5  NOP scans never arm busy: four back-to-back NOP captures, no busy, no
#       dmistat
#   D6  PROVOKED BUSY: a capture two TCK cycles after Update returns op = BUSY
#   D7  ...and the WHOLE 41-bit DR is literal 3 -- address 0 AND data 0, not
#       "the previous result with op = busy" (the Spike model, P2.7)
#   D8  ...and dtmcs.dmistat reads 3 (the sticky flag SET by the capture)
#   D9  while sticky, an Update-DR of dmi is IGNORED -- a write that would have
#       changed data0 did not change it
#   D10 dmireset clears dmistat to 0
#   D11 ...and the DTM is immediately usable again
#   D12 TEST-LOGIC-RESET does NOT clear the sticky flag (Spike semantics,
#       d3_cdc_spec 3 -- dmireset exists precisely for that)
#   D13 STICKY-FAILED: a DMI read of an unimplemented address returns op=FAILED
#   D14 ...and dtmcs.dmistat reads 2 -- the named deviation from Spike, which
#       does not mirror failure into dmistat at all
#   D15 ...cleared by dmireset
#   D16 dmihardreset DISCARDS an in-flight transaction: its late response never
#       appears as a subsequent capture's result
#   D17 ...and dmihardreset does NOT reset the Debug Module: DM-side state
#       (cmderr and hartsel) survives it
#   D18 TRSTn asserted mid-transaction leaves the DTM recoverable and leaks no
#       stale result
#   D19 ONE-SHOT, fast register: exactly ONE dmi_req_ready rising edge per
#       Update-DR
#   D20 ONE-SHOT, slow PROXY register (data0 -> shared 0x10680, tens of mclk
#       through the arbiter): still exactly ONE
#   D21 ONE-SHOT, aggregate: N transactions produce exactly N accepts
#   D22 dtmcs.idle is TRUTHFUL: dwelling exactly `idle` Run-Test/Idle cycles
#       after every Update produces ZERO busy captures over a long run
#   D23 a system reset asserted mid-transaction does not wedge the DTM: it
#       recovers through sticky-busy -> dmireset -> re-issue (LAST, because it
#       reboots the chip)
#   D24 STICKY-FAILED ALSO gates Update-DR (R-D3-4(2a), the uniform nonzero-
#       dmistat gate) -- five checks, including D24e which proves the gate is
#       a refusal and not a wedge.  This is the machinery the D3 wave's one
#       real RTL defect lived in
#   D25 after dmihardreset a Capture-DR of dmi returns 41'b0 -- the DEFINED
#       all-zeros shadow reset (R-D3-4(2b))
#   D26 Test-Logic-Reset does NOT clear the SHADOW (the half of C3.3 that was
#       named-open until the shadow's reset value was defined)
#
# AT UNIMPLEMENTED HEAD tap_present prints TAP_PORT_ABSENT / INSTRUMENT_DEAD
# and every check is skipped -- the part-1 seen-to-FAIL leg.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }

set NHARTS 4
if {[info exists ::env(D2_NHARTS)]} { set NHARTS $::env(D2_NHARTS) }

set PRESENT [tap_present]
set DMI_PORT_PRESENT [expr {![catch {value $::DMI_RQR}]}]

# Boot the chip.  D19-D21 watch the DM's acknowledge, which only exists once
# the DM has a clock, and D23 deliberately un-boots it at the end.
run 2 ms

# A distinctive, non-reset-looking value for the data0 proxy legs.
set VAL_A 0xA1B2C3D4
set VAL_B 0xDEADFEED
set VAL_C 0x5A5A1234

if {$PRESENT} {
    tap_init
    tap_calibrate_idle 8

    # ---- D1: dtmcs at rest --------------------------------------------------
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_version $t] == 1}] "D1a: dtmcs.version = [dtmcs_version $t], want 1"
    d2_chk [expr {[dtmcs_abits $t] == 7}]   "D1b: dtmcs.abits = [dtmcs_abits $t], want 7"
    d2_chk [expr {[dtmcs_dmistat $t] == 0}] \
        "D1c: dtmcs.dmistat = [dtmcs_dmistat $t] at rest, want 0 (nothing has gone wrong yet)"

    # ---- D2: a plain read ---------------------------------------------------
    set s [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {$::TAPROP == $::TAPRSP_SUCCESS}] \
        "D2a: a dmstatus read through the TAP returns op = SUCCESS (got $::TAPROP)"
    d2_chk [expr {[dms_version $s] == 3}] \
        "D2b: ...and the value is a real dmstatus -- version [dms_version $s] = 3, so the 41 bits landed where the DM expects them"

    # ---- D3/D4: Capture-DR returns the previous op's result, address kept ----
    # Armed by hand rather than through tap_dmi_xact, because the ADDRESS field
    # of the capture is the thing under test and the wrapper discards it.
    tap_dmi_scan 1 0 $::DM_HARTINFO
    tap_idle $::TAP_IDLE_DWELL
    set r [tap_dmi_scan 0 0 0]
    d2_chk [expr {[lindex $r 2] == $::DM_HARTINFO}] \
        "D3a: Capture-DR PRESERVES the address -- read back [format 0x%02X [lindex $r 2]], armed [format 0x%02X $::DM_HARTINFO]"
    d2_chk [expr {[lindex $r 0] == $::TAPRSP_SUCCESS && [d2_fld [lindex $r 1] 11 0] == 0x680}] \
        "D3b: ...with hartinfo's own data ([format 0x%08X [lindex $r 1]], dataaddr [format 0x%03X [d2_fld [lindex $r 1] 11 0]] = 0x680)"

    tap_dmi_scan 1 0 $::DM_DMSTATUS
    tap_idle $::TAP_IDLE_DWELL
    set r [tap_dmi_scan 0 0 0]
    d2_chk [expr {[lindex $r 2] == $::DM_DMSTATUS}] \
        "D4: ...and a SECOND, different address reads back as itself ([format 0x%02X [lindex $r 2]]) -- so D3a is not a hardwired field"

    # ---- D5: NOP scans never arm busy ---------------------------------------
    # Four NOP captures back to back with NO dwell between them.  If a NOP
    # armed the crossing, the second capture would find it in flight and go
    # busy -- which is precisely how D6 provokes busy with a REAL op.
    set nopbusy 0
    for {set i 0} {$i < 4} {incr i} {
        set r [tap_dmi_scan 0 0 0 UPDATE_DR]
        set r [tap_dmi_capture_now]
        if {[lindex $r 0] == $::TAPRSP_BUSY} { incr nopbusy }
    }
    d2_chk [expr {$nopbusy == 0}] \
        "D5a: four back-to-back NOP scans armed nothing -- $nopbusy busy captures, want 0"
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 0}] \
        "D5b: ...and dmistat is still [dtmcs_dmistat $t], want 0"

    # ---- D6/D7/D8: the provoked sticky busy ---------------------------------
    # Arm a REAL read and stay in Update-DR, then capture by the shortest path.
    tap_dmi_scan 1 0 $::DM_DMSTATUS UPDATE_DR
    set r [tap_dmi_capture_now]
    set cop [lindex $r 0] ; set cdat [lindex $r 1] ; set cadr [lindex $r 2]
    d2_chk [expr {$cop == $::TAPRSP_BUSY}] \
        "D6: a capture two TCK cycles after Update-DR returns op = BUSY (got $cop) -- the crossing cannot have answered inside its own 3-flop return chain"
    d2_chk [expr {$cop == $::TAPRSP_BUSY && $cdat == 0 && $cadr == 0}] \
        "D7: ...and the WHOLE 41-bit DR is literal 3 -- data [format 0x%08X $cdat] and address [format 0x%02X $cadr] both zero, not the previous result with op=busy"
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 3}] \
        "D8: ...and the capture SET the sticky flag -- dmistat = [dtmcs_dmistat $t], want 3"

    # ---- D9: Update-DR ignored while sticky ---------------------------------
    # data0 is a proxy for shared 0x10680, so its value is independently
    # readable and a write that "did not happen" is provable rather than
    # inferred.  VAL_A is planted BEFORE the sticky state; VAL_B is the write
    # that must be dropped.
    set stickystate 1
    tap_dmireset
    dmi_write_tap $::DM_DATA0 $VAL_A
    set v [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$v == $VAL_A}] "D9a: precondition -- data0 holds [format 0x%08X $v] before the sticky state"
    # go sticky again
    tap_dmi_scan 1 0 $::DM_DMSTATUS UPDATE_DR
    tap_dmi_capture_now
    # this write must be swallowed
    tap_dmi_scan 2 $VAL_B $::DM_DATA0
    tap_idle $::TAP_IDLE_DWELL
    tap_dmireset
    set v [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$v == $VAL_A}] \
        "D9b: a dmi Update-DR issued WHILE STICKY was IGNORED -- data0 still [format 0x%08X $v], not [format 0x%08X $VAL_B]"
    set w [sh_get $::DBG_DATA0_ADDR]
    d2_chk [expr {$w == $VAL_A}] \
        "D9c: ...confirmed at the shared word itself ([format 0x%05X $::DBG_DATA0_ADDR] = [format 0x%08X $w]) -- the DM never saw the write"

    # ---- D10/D11: dmireset ---------------------------------------------------
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 0}] "D10: dmireset cleared dmistat (reads [dtmcs_dmistat $t])"
    set s [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {$::TAPROP == $::TAPRSP_SUCCESS && [dms_version $s] == 3}] \
        "D11: ...and the DTM is immediately usable -- dmstatus reads [format 0x%08X $s] with op $::TAPROP"

    # ---- D12: TLR does NOT clear sticky --------------------------------------
    tap_dmi_scan 1 0 $::DM_DMSTATUS UPDATE_DR
    tap_dmi_capture_now
    set t [tap_read_dtmcs]
    set pre [dtmcs_dmistat $t]
    tap_reset
    set t [tap_read_dtmcs]
    d2_chk [expr {$pre == 3 && [dtmcs_dmistat $t] == 3}] \
        "D12: Test-Logic-Reset did NOT clear the sticky flag (dmistat $pre -> [dtmcs_dmistat $t], want 3 -> 3) -- Spike semantics, and the reason dmireset exists"
    tap_dmireset

    # ---- D13/D14/D15: sticky FAILED ------------------------------------------
    # 0x1A is unimplemented in the DM's address decode; dbg_conf's K11 pins the
    # same address to FAILED over the raw port, so the two transports are being
    # asked the identical question.
    tap_dmi_scan 1 0 0x1A
    tap_idle $::TAP_IDLE_DWELL
    set r [tap_dmi_scan 0 0 0]
    d2_chk [expr {[lindex $r 0] == $::TAPRSP_FAILED}] \
        "D13: a DMI read of unimplemented address 0x1A returns op = FAILED (got [lindex $r 0])"
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 2}] \
        "D14: ...and dmistat latched 2 (STICKY FAILED, the named deviation -- Spike never mirrors failure into dmistat)"
    tap_dmireset
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 0}] "D15: ...cleared by dmireset (reads [dtmcs_dmistat $t])"

    # ---- D16/D17: dmihardreset ------------------------------------------------
    # Set up DM state that a DM reset would destroy: select the last hart and
    # provoke a nonzero cmderr with a command aimed at a RUNNING hart (the
    # dbg_conf K13a provocation, whose answer HALT_RESUME is unambiguous).
    dmi_write_tap $::DM_DMCONTROL [expr {(($NHARTS - 1) << 16) | 1}]
    dmi_write_tap $::DM_COMMAND [ac_cmd 0x1008 0 1 0]
    set acs -1
    for {set i 0} {$i < 200} {incr i} {
        set acs [dmi_read_tap $::DM_ABSTRACTCS]
        if {$acs >= 0 && [acs_busy $acs] == 0} { break }
        tap_idle 4
    }
    set pre_cmderr [acs_cmderr $acs]
    # arm a transaction and hard-reset it away before it can return
    tap_dmi_scan 1 0 $::DM_HARTINFO UPDATE_DR
    tap_dmihardreset
    tap_idle 32
    set r [tap_dmi_capture_now]
    d2_chk [expr {[lindex $r 2] != $::DM_HARTINFO || [lindex $r 1] == 0}] \
        "D16a: dmihardreset DISCARDED the in-flight transaction -- the capture does not carry hartinfo's address+data (got addr [format 0x%02X [lindex $r 2]] data [format 0x%08X [lindex $r 1]])"
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 0}] \
        "D16b: ...and dmihardreset left dmistat clear (reads [dtmcs_dmistat $t])"
    set s [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {$::TAPROP == $::TAPRSP_SUCCESS && [dms_version $s] == 3}] \
        "D16c: ...and the DTM is usable afterwards, so the toggle chains stayed phase-coherent (d3_cdc_spec 3's recovery clause)"
    set dc [dmi_read_tap $::DM_DMCONTROL]
    set acs [dmi_read_tap $::DM_ABSTRACTCS]
    d2_chk [expr {[d2_fld $dc 25 16] == ($NHARTS - 1)}] \
        "D17a: dmihardreset did NOT reset the Debug Module -- hartsel is still [d2_fld $dc 25 16], want [expr {$NHARTS-1}]"
    d2_chk [expr {$pre_cmderr != 0 && [acs_cmderr $acs] == $pre_cmderr}] \
        "D17b: ...and cmderr survived it ($pre_cmderr -> [acs_cmderr $acs]); a DM reset would have cleared both"
    ac_clear_cmderr_tap
    dmi_write_tap $::DM_DMCONTROL 1

    # ---- D18: TRSTn mid-transaction -------------------------------------------
    tap_dmi_scan 1 0 $::DM_HARTINFO UPDATE_DR
    tap_trst_pulse 4
    tap_idle 32
    set r [tap_dmi_capture_now]
    d2_chk [expr {[lindex $r 2] != $::DM_HARTINFO || [lindex $r 1] == 0}] \
        "D18a: TRSTn asserted mid-transaction leaked no stale result (addr [format 0x%02X [lindex $r 2]])"
    tap_dmireset
    set s [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {$::TAPROP == $::TAPRSP_SUCCESS && [dms_version $s] == 3}] \
        "D18b: ...and the DTM recovered -- a fresh transaction succeeds"

    # ---- D19/D20/D21: THE ONE-SHOT CLAUSE -------------------------------------
    if {!$DMI_PORT_PRESENT} {
        puts "DMILOG ONESHOT_OBSERVABILITY_LOST -- $::DMI_RQR does not resolve, so"
        puts "DMILOG   accepts cannot be counted.  d3_cdc_spec 7 retains the external"
        puts "DMILOG   dmi_* ports and fans the DM's responses out to both masters; if"
        puts "DMILOG   that is still true this cannot happen.  REPORT, do not skip."
        flush stdout
        d2_chk 0 "D19-D21: the one-shot clause is UNOBSERVABLE in this build (dmi_req_ready absent) -- a FINDING about the OR-merge, not about the crossing"
    } else {
        tap_watch_ready_begin
        dmi_read_tap $::DM_DMSTATUS
        set n [tap_watch_ready_end]
        d2_chk [expr {$n == 1}] \
            "D19: ONE-SHOT on a fast register -- $n dmi_req_ready rising edge(s) for one Update-DR, want exactly 1 (2 = the duplicate accept the 9-mclk window re-opens for a held-valid master)"

        tap_watch_ready_begin
        dmi_read_tap $::DM_DATA0
        set n [tap_watch_ready_end]
        d2_chk [expr {$n == 1}] \
            "D20: ONE-SHOT on the SLOW proxy path (data0 -> shared 0x10680, tens of mclk through the arbiter) -- $n accept(s), want exactly 1"

        tap_watch_ready_begin
        for {set i 0} {$i < 6} {incr i} { dmi_read_tap $::DM_DMSTATUS }
        set n [tap_watch_ready_end]
        d2_chk [expr {$n == 6}] \
            "D21: ONE-SHOT in aggregate -- 6 transactions produced $n accepts, want exactly 6"
    }

    # ---- D22: dtmcs.idle is truthful -------------------------------------------
    # The spec does not fix the VALUE; it fixes the CONTRACT.  So the check is
    # written against whatever the DUT advertises: dwell exactly `idle` cycles
    # and no transaction may go busy.  A DTM advertising 0 while needing 4 fails
    # here, which is precisely the Spike behaviour d3_cdc_spec 4 says not to copy.
    set adv $::TAP_IDLE_ADV
    set busies 0
    for {set i 0} {$i < 20} {incr i} {
        tap_dmi_scan 1 0 $::DM_DMSTATUS
        tap_idle $adv
        set r [tap_dmi_scan 0 0 0]
        if {[lindex $r 0] == $::TAPRSP_BUSY} { incr busies ; tap_dmireset }
    }
    d2_chk [expr {$busies == 0}] \
        "D22: dtmcs.idle = $adv is TRUTHFUL -- 20 transactions dwelling exactly $adv Run-Test/Idle cycles produced $busies busy captures, want 0"

    # ---- D24: STICKY-FAILED ALSO GATES Update-DR (R-D3-4(2a)) ----------------
    # The uniform nonzero-dmistat gate, a named deviation from Spike (whose
    # gate is busy-only).  This check is the FAILED twin of D9, and it is now
    # the most load-bearing check in the file: the D3 implementation wave's one
    # real RTL defect lived in exactly this machinery -- sticky FAILED latched
    # at Capture-DR from the STALE shadow op, so one failed address silently
    # swallowed every later DMI WRITE and dmireset could not break the loop
    # (each new scan's capture re-raised it).  D24 asserts the gate does what
    # the amendment says; D24c then asserts the DTM is not WEDGED by it, which
    # is the half that defect would have failed.
    tap_dmireset
    dmi_write_tap $::DM_DATA0 $VAL_C
    set v [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$v == $VAL_C}] \
        "D24a: precondition -- data0 holds [format 0x%08X $v] before the sticky-FAILED state"
    tap_dmi_scan 1 0 0x1A                    ;# provoke sticky FAILED
    tap_idle $::TAP_IDLE_DWELL
    set r [tap_dmi_scan 0 0 0]
    set t [tap_read_dtmcs]
    d2_chk [expr {[lindex $r 0] == $::TAPRSP_FAILED && [dtmcs_dmistat $t] == 2}] \
        "D24b: precondition -- a bad address left op FAILED and dmistat [dtmcs_dmistat $t], want 2"
    tap_dmi_scan 2 $VAL_B $::DM_DATA0        ;# must be swallowed
    tap_idle $::TAP_IDLE_DWELL
    tap_dmireset
    set v [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$v == $VAL_C}] \
        "D24c: an Update-DR issued while dmistat = 2 (STICKY FAILED) was IGNORED -- data0 still [format 0x%08X $v], not [format 0x%08X $VAL_B]"
    set w [sh_get $::DBG_DATA0_ADDR]
    d2_chk [expr {$w == $VAL_C}] \
        "D24d: ...confirmed at the shared word ([format 0x%05X $::DBG_DATA0_ADDR] = [format 0x%08X $w]) -- the DM never saw the write"
    dmi_write_tap $::DM_DATA0 $VAL_A
    set v [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$v == $VAL_A}] \
        "D24e: ...and after dmireset the SAME write lands ([format 0x%08X $v]) -- the gate is a refusal, not a wedge.  D24c alone is satisfied by a DTM that has stopped accepting writes at all; this is what excludes it"

    # ---- D25/D26: the DEFINED shadow reset value (R-D3-4(2b)) ----------------
    # The amendment DEFINES the shadow's reset value as all-zeros, which turns
    # two previously named-open halves (my U13, and the shadow half of C3.3)
    # into assertable checks.
    tap_dmi_scan 1 0 $::DM_HARTINFO
    tap_idle $::TAP_IDLE_DWELL
    tap_dmi_scan 0 0 0
    tap_dmihardreset
    tap_idle 32
    set r [tap_dmi_capture_now]
    d2_chk [expr {[lindex $r 0] == 0 && [lindex $r 1] == 0 && [lindex $r 2] == 0}] \
        "D25: after dmihardreset a Capture-DR of dmi returns 41'b0 (got op [lindex $r 0] data [format 0x%08X [lindex $r 1]] addr [format 0x%02X [lindex $r 2]]) -- the DEFINED all-zeros shadow reset"

    # Re-establish a KNOWN, non-zero shadow, then reset the TAP and prove the
    # shadow survived.  D12 already proves TLR does not clear the STICKY flag;
    # this is the SHADOW half of the same clause, and the pair is what makes
    # "TLR does exactly one thing" a measured statement rather than a quote.
    tap_dmi_scan 1 0 $::DM_HARTINFO
    tap_idle $::TAP_IDLE_DWELL
    set r [tap_dmi_scan 0 0 0]
    set pre_addr [lindex $r 2] ; set pre_data [lindex $r 1]
    tap_reset
    set r [tap_dmi_capture_now]
    d2_chk [expr {[lindex $r 2] == $::DM_HARTINFO && [lindex $r 1] == $pre_data && $pre_addr == $::DM_HARTINFO}] \
        "D26: Test-Logic-Reset did NOT clear the SHADOW -- it still reads addr [format 0x%02X [lindex $r 2]] data [format 0x%08X [lindex $r 1]] (hartinfo), and TLR is the only thing that ran between the two captures"

    # ---- D23: a system reset mid-transaction must not wedge the DTM ------------
    # LAST, and deliberately so: it reboots the chip.  d3_cdc_spec 3 requires
    # that a response lost to a system reset leaves the DTM RECOVERABLE, with
    # the recovery being sticky-busy -> dmireset -> re-issue.  The DTM itself is
    # NOT reset by system resetn, so its own state must survive this.
    tap_dmireset
    tap_dmi_scan 1 0 $::DM_HARTINFO UPDATE_DR
    catch {force :dut:resetn_in '0'}
    run 20 us
    catch {force :dut:resetn_in '1'}
    catch {release :dut:resetn_in}
    run 2 ms
    set r [tap_dmi_capture_now]
    puts "DMILOG D23 post-reset capture op=[lindex $r 0] data=[format 0x%08X [lindex $r 1]] addr=[format 0x%02X [lindex $r 2]]"
    tap_dmireset
    set t [tap_read_dtmcs]
    d2_chk [expr {[dtmcs_dmistat $t] == 0}] \
        "D23a: after a system reset mid-transaction, dmireset restores dmistat to 0 (reads [dtmcs_dmistat $t])"
    set s [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {$::TAPROP == $::TAPRSP_SUCCESS && [dms_version $s] == 3}] \
        "D23b: ...and the DTM is NOT wedged -- a re-issued transaction succeeds (dmstatus [format 0x%08X $s])"
    set id [tap_read_idcode]
    d2_chk [expr {$id != 0}] \
        "D23c: ...and the TAP itself was never reset by system resetn -- IDCODE still reads [format 0x%08X $id] (d3_cdc_spec 3: a debugger must be attachable while the chip is held in reset)"
}

tap_cost "dbg_tapdtm"
tap_summary "dbg_tapdtm" $PRESENT 43
flush stdout
