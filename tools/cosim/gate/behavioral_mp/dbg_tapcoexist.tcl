# =============================================================================
# dbg_tapcoexist.tcl -- D3 instrument T6: THE COEXISTENCE REGRESSION.
# Proves d3_cdc_spec section 7's OR-merge design: the DTM lives inside the MCU
# beside dm0, the external dmi_* ports are RETAINED, and BOTH masters reach the
# Debug Module -- family A's forces at the unassociated formals AND the TAP.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_tapcoexist.tcl
#
# BLIND-AUTHORED 2026-08-06 against d3_cdc_spec.md 7 (FROZEN).
#
# WHY THIS INSTRUMENT HAD TO BE WRITTEN, AND WHAT IT IS DEFENDING AGAINST
#   d3_probe P4.4 priced the failure mode precisely: if the DTM takes over the
#   DM's dmi_* inputs, family A (the 13 tcl force harnesses) sees its forces
#   become no-ops while `dmi_present` still returns 1, because name resolution
#   survives the hijack -- "loud but misattributed".  Family B (J1) is worse:
#   no elaboration error, all 47 checks silently reading defaults -- "SILENT,
#   the worst class".  NEITHER FAMILY HAS A TRIPWIRE FOR IT.  This file is that
#   tripwire, and it is the only instrument in the D3 set whose job is to fail
#   when the OR-merge is wrong rather than when the DTM is wrong.
#
#   The 13 harnesses and J1 re-run unchanged on the D3 tree are the OTHER half
#   of this regression (see d3_acceptance_report.md section on the coexistence
#   plan).  They are the breadth; this file is the discriminator that says WHY
#   they broke if they do.
#
# CHECK LIST (C-numbers; the runner greps for "CHECK FAILED"):
#   C1  BOTH port groups exist: all eight dmi_* names AND all five JTAG names
#       (the retention proof -- d3_cdc_spec 7 keeps the DMI ports, and a build
#       that dropped them would still pass every TAP check in T2/T3/T5)
#   C2  INERTNESS: with trstn at its fail-safe default and TCK never toggled,
#       ZERO DM accepts occur over a long window.  The DTM issues nothing.
#   C3  family A still works with the DTM present-and-inert: a raw forced DMI
#       transaction reaches the DM and returns a real dmstatus
#   C4  ...and it costs EXACTLY ONE accept over a 60 us window -- the OR is
#       transparent, not duplicating, and no LATE duplicate follows
#   C4b ...and the same on the SLOW proxy path, where a duplicate is likeliest
#   C5  after the TAP is brought live, a raw forced transaction STILL works
#   C6  a TAP transaction returns the same dmstatus as the raw one did
#   C7  raw and TAP transactions INTERLEAVED both keep returning correct
#       results -- the two masters coexist across a boundary in both directions
#   C8  a raw WRITE is visible to a TAP READ (data0 proxy): the two masters are
#       talking to ONE Debug Module, not to two shadows
#   C9  ...and the converse, a TAP write read back over the raw port
#
# AT UNIMPLEMENTED HEAD the JTAG half is absent, so C1 FAILS by design and the
# rest are skipped -- but note C3/C4 are ALSO the D2 baseline, so running this
# file on a debug-ON D2 tree measures the "before" of the regression.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }

set DMI_OK  [dmi_present]
set TAP_OK  [tap_present]

run 2 ms

d2_chk [expr {$DMI_OK == 1}] \
    "C1a: all EIGHT frozen dmi_* ports still resolve (d3_cdc_spec 7 RETAINS them; a DTM that repurposed them would fail here and nowhere else)"
d2_chk [expr {$TAP_OK == 1}] \
    "C1b: all FIVE JTAG ports resolve"

if {$DMI_OK} {
    # ---- C2: inertness, measured -----------------------------------------
    # trstn is left at its ENTITY DEFAULT and TCK is never touched.  If the DTM
    # is inert, nothing at all reaches the DM, so the acknowledge never pulses.
    # This is the strongest inertness statement obtainable from outside the
    # MCU, and it is the claim d3_spec 0 makes for the fail-safe defaults.
    # tap_accepts_window OWNS its time advance (instrument defect I-4).  The
    # first cut used tap_watch_ready_begin + `run 200 us`, whose counter lives
    # inside tap_run -- which never executes here.  It therefore reported 0
    # because it COULD NOT REPORT ANYTHING ELSE, and would have passed on a
    # DTM hammering the DM continuously.  20000 x 10 ns = 200 us, sampled.
    set n [tap_accepts_window 20000]
    d2_chk [expr {$n == 0}] \
        "C2: with trstn at its fail-safe default and TCK never toggled, the DM saw $n accepts over 200 us (SAMPLED), want 0 -- the DTM is INERT"

    # ---- C3/C4: family A, DTM present-and-inert ---------------------------
    # tap_raw_xact_counted performs the family-A handshake AND counts the
    # acknowledge in its own poll loops, including a 60 us TAIL -- because the
    # DM's re-capture window re-opens 9 mclk AFTER a capture, so a duplicate
    # accept is a LATE event that a counter stopping at the response would
    # miss entirely (instrument defect I-4).
    set r [tap_raw_xact_counted $::DMI_OP_READ $::DM_DMSTATUS 0]
    set s_raw [lindex $r 2]
    set n     [lindex $r 3]
    d2_chk [expr {[lindex $r 0] == 1 && [lindex $r 1] == 0 && [dms_version $s_raw] == 3}] \
        "C3: a RAW forced DMI transaction reaches the DM with the DTM present (dmstatus [format 0x%08X $s_raw], op [lindex $r 1]) -- family A survives the OR-merge"
    d2_chk [expr {$n == 1}] \
        "C4: ...and it cost exactly $n accept over a 60 us window, want 1 -- the OR is transparent, not duplicating, and no LATE duplicate follows"

    # C4b: the same question on the SLOW proxy path, where the DM is busy for
    # tens of mclk and the re-open window is comfortably inside the response
    # latency -- the shape most likely to earn a second accept.
    set r [tap_raw_xact_counted $::DMI_OP_READ $::DM_DATA0 0]
    d2_chk [expr {[lindex $r 3] == 1}] \
        "C4b: a RAW transaction on the SLOW proxy path (data0 -> shared 0x10680) cost exactly [lindex $r 3] accept, want 1"
}

if {$DMI_OK && $TAP_OK} {
    # ---- C5..C9: both masters, alternating --------------------------------
    tap_init
    tap_calibrate_idle 8

    set s_raw2 [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {$::DMI_ROP == 0 && [dms_version $s_raw2] == 3}] \
        "C5: a raw forced transaction STILL works after the TAP has been brought live"

    set s_tap [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {$::TAPROP == 0 && [dms_version $s_tap] == 3}] \
        "C6a: a TAP transaction returns a real dmstatus ([format 0x%08X $s_tap])"
    d2_chk [expr {[dms_version $s_tap] == [dms_version $s_raw2] &&
                  [d2_fld $s_tap 22 0] == [d2_fld $s_raw2 22 0]}] \
        "C6b: ...and it agrees with the raw read in every field below bit 23 -- one DM, two transports"

    set bad 0
    for {set i 0} {$i < 3} {incr i} {
        set a [dmi_read $::DM_HARTINFO]
        if {$::DMI_ROP != 0 || [d2_fld $a 11 0] != 0x680} { incr bad }
        set b [dmi_read_tap $::DM_HARTINFO]
        if {$::TAPROP != 0 || [d2_fld $b 11 0] != 0x680} { incr bad }
    }
    d2_chk [expr {$bad == 0}] \
        "C7: three raw/TAP INTERLEAVED transaction pairs, $bad wrong answers, want 0"

    dmi_write $::DM_DATA0 0x1CE1CE1C
    set v [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$v == 0x1CE1CE1C}] \
        "C8: a RAW write is visible to a TAP read (data0 = [format 0x%08X $v]) -- one Debug Module, not two shadows"

    dmi_write_tap $::DM_DATA0 0x0FF0BEEF
    set v [dmi_read $::DM_DATA0]
    d2_chk [expr {$v == 0x0FF0BEEF}] \
        "C9: ...and the converse, a TAP write read back over the raw port ([format 0x%08X $v])"
}

tap_cost "dbg_tapcoexist"
tap_summary "dbg_tapcoexist" [expr {$DMI_OK && $TAP_OK}] 12
flush stdout
