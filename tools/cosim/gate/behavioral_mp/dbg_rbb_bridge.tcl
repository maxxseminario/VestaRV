# =============================================================================
# dbg_rbb_bridge.tcl -- THE D5 TRANSPORT.  xmsim's OWN Tcl interpreter listens
# on the OpenOCD `remote_bitbang` TCP port and drives the five JTAG formals.
# No co-process.  No DPI.  SOURCED as a library; `dbg_sessrun.tcl` is the
# harness that uses it.
#
# Architecture RULED by R-D5-1(3) on measurement, not taste: a Tcl socket works
# in xmsim in both directions (ipc probe C2), and on the REAL design DPI wins
# only 1.5x (95 vs 142 us/TCK) because ~75 % of the per-TCK cost is simulating
# Castalia for one TCK period, not the IPC.  Adopting DPI would introduce
# SystemVerilog, DPI and mixed-language elaboration into a -V200X VHDL tree
# with none of the three anywhere in it, for 1.5x.  The working DPI bridge
# stays on record as the measured fallback.
#
# -----------------------------------------------------------------------------
# THE PROTOCOL (OpenOCD doc/manual/jtag/drivers/remote_bitbang.txt; the tree's
# own `tools/debug/riscv-tests-debug/rbb_daisychain.py` is a second, on-disk
# reference implementation of the same alphabet):
#   '0'..'7'   set pins, value-'0' = (tck<<2)|(tms<<1)|tdi
#   'R'        sample TDO, reply exactly one byte, '0' or '1'
#   'r's't''u' reset lines: index into "rstu" = (trst<<1)|srst
#   'B' 'b'    blink on / off -- no reply, no effect
#   'Q'        quit: stats line, close, RETURN (see THE Q CONTRACT below)
#
# -----------------------------------------------------------------------------
# THE ELEVEN FROZEN CLAUSES (d5_spec 2), and where each one lives here.  They
# are numbered because every one of them is a measurement somebody already paid
# for, and a future edit that "simplifies" one of them will silently undo it.
#
#  1  full alphabet ......................... rbb_process's dispatch
#  2  `Listening on port NNNN.` + flush ...... rbb_listen
#  3  NEVER -buffering none .................. rbb_accept  (24 us PER CHARACTER
#                                              -- one syscall per byte, ipc C6)
#  4  chunked reads .......................... rbb_process (6.5x, ipc C16)
#  5  no poll loop; the wait advances NO sim
#     time -- see THE SERVICE MODEL below ... rbb_session (CORRECTNESS: a
#                                              polling loop advances sim time
#                                              while waiting for the debugger,
#                                              so sim-time-per-op becomes a
#                                              function of the human.  For the
#                                              running tiles that is not
#                                              cosmetic -- ipc C15.)
#  6  a NONZERO `run` between pin-set bytes .. rbb_set_pins (same-time forces
#                                              COLLAPSE -- 8 toggles + one run
#                                              produced ONE edge, ipc C23 --
#                                              and `run 0 ns` does not
#                                              propagate at all, C24)
#  7  lazy pin forcing; TAP_WATCH_READY OFF .. rbb_set_pins (1.22x; and the
#                                              watch mode alone costs 143
#                                              us/TCK, more than the entire
#                                              real design, ipc C5)
#  8  TCK period >= 140 ns .................... RBB_STEP_NS default 70
#  9  heartbeat carrying pending_out ......... rbb_beat
# 10  catch-wrapped handlers, explicit report . rbb_on_rbb / rbb_on_ctl
# 11  the 100 ms tb watchdog needs nothing ..... see THE WATCHDOG BANNER below
#
# -----------------------------------------------------------------------------
# THE ONE-BIT-SHIFT TRAP, and it is the reason for the phase comments below.
# Sampling TDO one phase late does NOT produce garbage.  It produces the entire
# bitstream shifted by exactly one bit: measured, 0x1CA57EEF read back as
# 0x0E52BF77 (ipc C26).  That is the dangerous kind of wrong -- it looks
# structured, it reads as "the IDCODE is nearly right so the transport works
# and the RTL must be off by one", and it points the investigation at the DUT.
#
#   *** A BIT-SHIFTED IDCODE READBACK IS A BRIDGE PHASE SYMPTOM UNTIL PROVEN
#   *** OTHERWISE.  Check this file before you open jtag_dtm.vhd.
#
# The protocol places the sample correctly BY CONSTRUCTION and we must not
# "help": OpenOCD emits, per TCK, the pin-set with tck=0 CARRYING the new
# TMS/TDI, then 'R', then the pin-set with tck=1.  So TDO is sampled after the
# low phase has been applied AND simulated, before the rising edge -- which is
# exactly where dbg_tap.tcl's three-phase tap_step samples it.  We need only
# TWO runs per TCK, not three, because the data travels WITH the low-phase byte
# and is settled for a full half period before the edge (ipc C28).
#
# -----------------------------------------------------------------------------
# THE Q CONTRACT.  'Q' closes the socket and RETURNS.  It does NOT `exit`.
# That is deliberate and it is what makes the session gradeable: the D5 session
# graders (dbg_sess_lib.tcl) are PASSIVE and run in this same interpreter, so
# they can only run when the serve loop has given the interpreter back.  A
# bridge that exited on Q would take every post-session snapshot with it.
#
# -----------------------------------------------------------------------------
# THE WATCHDOG BANNER -- EXPECTED, NOT A FAULT.  At sim t = 100 ms the tb's
# watchdog fires once:
#     REPORT/FAILURE ... SIMULATION TIMEOUT REACHED
# A `severity failure` in this flow HALTS THE RUN TO THE TCL PROMPT and the
# script continues; the watchdog process then ends in `wait;`, so it fires
# EXACTLY ONCE and never again (riscv_tb.vhd, tree probe C44/C45, measured on a
# real D3-era log).  The serve loop issues its next `run` and sim time
# continues indefinitely.  Nothing needs to be done about this.  It is
# documented here so that nobody debugs it.
#
# The a0 pass/fail monitor halts the same way, which is why a session image
# whose hart 0 never terminates (d5sess) is the better subject.
#
# -----------------------------------------------------------------------------
# HEALTH IS AN ORDERING OVER COUNTERS, NEVER A DURATION (method rule 17, and
# the DD9-5 dispensation adopted at R-D5-1(4)).  Wall clock per TCK is NOT a
# health metric: the ipc probe's own instrument reported 20,130 us/TCK -- 142x
# the healthy figure -- for a session that was perfectly healthy, because the
# human paused for 8 s.
#
# `pending_out` is the ONLY discriminator between the two states that are
# otherwise IDENTICAL in every externally visible signal (ipc C31):
#   BLOCKED-ON-DEBUGGER  benign, unbounded: xmsim S at ~0 % CPU, sim time
#                        frozen, no bytes moving, both peers alive
#   DEADLOCK             we hold reply bytes the debugger is blocked waiting
#                        for and have not flushed them
# No amount of ps, pgrep, sim-time watching or wall-clock budgeting separates
# those.  It is one counter, and it exists in this file's FIRST version rather
# than being added when a deadlock appears -- because by then the symptom is
# "OpenOCD hangs" and the investigation goes to the Debug Module.
#
# A session emitting this heartbeat is DISPENSED from the 1-minute rule.
# =============================================================================

# --- dependencies -----------------------------------------------------------
# CWD is the staged verify dir (xrun_dbg_verify.sh does `cd "$VABS"`), so the
# behavioral_mp copies are one level over.  Same fallback shape every D-series
# harness uses.
if {[llength [info procs tap_run]] == 0} {
    if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }
}

# --- knobs ------------------------------------------------------------------
# RBB_STEP_NS is the HALF period: two runs per TCK, so the JTAG period is
# 2*RBB_STEP_NS = 420 ns by default (~2.38 MHz).  See the measurement below
# for why the default is not the 140 ns floor.
#
# DO NOT SHORTEN THIS WITHOUT A SEPARATE MEASUREMENT.  jtag_dtm.vhd's dtmcs
# `idle` = 7 is DERIVED from a stated assumption of T_TCK >= 140 ns against
# mclk 41.667 ns, and 7 is the maximum the 3-bit field can express -- there is
# no headroom left to advertise.  Going faster is not a speed knob, it is a
# change to a CDC contract (d3_cdc_spec), and d5_spec 2.8 puts it out of scope.
# The ipc probe measured that halving the period would beat DPI outright
# (C21); that is a real lever and it is deliberately untaken here.
#
# THE DEFAULT IS 210 (420 ns period) AS AN INTERIM WORKAROUND, NOT AS "THE
# OPERATING RATE".  140 ns is a FLOOR: the contract forbids SHORTENING, and
# lengthening needs no authorisation (method rule 15 -- the fail-safe
# direction, because at 70 the failure is not a slow session but a SILENTLY
# CORRUPT one that reads as a chip defect).
#
# THE MECHANISM IS MEASURED, AND IT IS NOT THIS BRIDGE'S TIMING.  Do not
# "fix" this by shortening the period back.  Measured 2026-08-10:
#
#   1. jtag_dtm.vhd advertises dtmcs.idle = 7 and DERIVES its CDC margin from
#      the debugger dwelling that many Run-Test/Idle cycles after a DMI scan.
#   2. The three-phase BFM (dbg_tap.tcl) honours it -- dbg_gateidc reports
#      dwell=8 -- and at 140 ns the chip is CLEAN: dbg_abs 13/13 including
#      A7a "POSTEXEC ran the program buffer with cmderr = 0" and A7b, the
#      progbuf actually moving a word through the hart's own bus.  So the
#      chip is not the problem at its own stated floor.
#   3. STOCK OPENOCD DOES NOT HONOUR dtmcs.idle.  Measured ON THE WIRE by the
#      RTI census below, at 140 ns: dwell histogram
#         0:424  1:12  2:168  3:45  4:96  5:27  6:157  7:53  8:54
#      -- 929 of 1036 inter-scan gaps (90%) BELOW the advertised 7, and 424
#      of them (41%) with NO idle cycle at all.
#   4. A too-early scan makes the DTM report BUSY and set sticky, and
#      DEVIATION 4 (jtag_dtm.vhd) then SILENTLY DROPS every non-NOP Update-DR
#      while sticky.  So an intermediate progbuf WRITE is dropped while
#      OpenOCD believes it landed; its dmireset+retry recovers the scan it
#      knows about, not the one it never learned was lost.
#   5. postexec then executes a HALF-WRITTEN program buffer, the hart traps,
#      and the DM correctly reports cmderr=3 EXCEPTION -- which surfaces as
#      "Failed to read MISA from hart N".
#
# At 420 ns the absolute inter-scan time covers the DM's turnaround even with
# ZERO idle cycles, so step 4 never fires: ALL FOUR harts examine
# (misa 0x40101107, dmiresets 8), reproduced twice.  That is why this works
# and why it is a WORKAROUND: the interop hazard is unresolved and is a
# finding above this file.  See the D5 implementation report.
set ::RBB_STEP_NS [expr {[info exists ::env(D5_STEP_NS)] ? $::env(D5_STEP_NS) : 210}]
set ::RBB_PORT    [expr {[info exists ::env(D5_RBBPORT)] ? $::env(D5_RBBPORT) : 0}]
set ::RBB_PORTFILE [expr {[info exists ::env(D5_PORTFILE)] ? $::env(D5_PORTFILE) : ""}]
set ::RBB_BEAT_TCK [expr {[info exists ::env(D5_BEAT_TCK)] ? $::env(D5_BEAT_TCK) : 2000}]
# TARGET WEDGE bound, clause 9.  Counted in DMI TRANSACTIONS SINCE THE LAST
# CHANGE in any DM response word -- never in seconds.  It must be generous:
# "the DM answered the same thing again" is NORMAL for a poll loop, and OpenOCD
# polls dmstatus continuously.  400 DMI transactions is ~4x the entire
# single-hart examine (66 DMI scans, toolchain probe 27b), so a session that
# has made 400 consecutive identical-response transactions is not polling, it
# is stuck.  Stated deliberately, per the clause.
set ::RBB_WEDGE_N  [expr {[info exists ::env(D5_WEDGE_N)] ? $::env(D5_WEDGE_N) : 400}]
# The deliberate-deadlock provocation (d5_spec 2.9 as amended by R-D5-2): when
# set, the bridge withholds the flush of its reply bytes so the DEADLOCK
# verdict can be SEEN TO FIRE.  A discriminator never observed firing is not
# known to work.  Default OFF, obviously.
set ::RBB_NOFLUSH  [expr {[info exists ::env(D5_NOFLUSH)] ? $::env(D5_NOFLUSH) : 0}]

# --- counters (clause 9) ----------------------------------------------------
set ::RBB_BYTES_IN   0
set ::RBB_BYTES_OUT  0
set ::RBB_PENDING    0   ;# reply bytes built but not yet written+flushed
set ::RBB_ROUNDTRIPS 0
set ::RBB_TCK        0
set ::RBB_FORCES     0
set ::RBB_FORCE_ERRS 0
set ::RBB_RUNS       0
set ::RBB_DMIRESETS  0
set ::RBB_DMI_XACT   0
set ::RBB_SRST_REQ   0
set ::RBB_TRST_REQ   0
set ::RBB_LASTBEAT   0
set ::RBB_STATEDESC  "INIT"
set ::RBB_SAMEDMI    0   ;# consecutive DMI transactions with an unchanged response
set ::RBB_LASTDMIRSP "-"

# pin shadow, for clause 7 (force only what changed)
set ::RBB_TCKV 0 ; set ::RBB_TMSV 0 ; set ::RBB_TDIV 0 ; set ::RBB_TRSTNV 1

# ---------------------------------------------------------------------------
# TAP FSM / IR / DR SHADOW.
#
# WHY THE BRIDGE DECODES AT ALL, since a bitbang transport does not need to.
# Clause 9 asks for `dmiresets` "when derivable" AND for a TARGET WEDGE verdict
# defined over "the DM's own observable ... unchanged over N transactions".
# Neither is derivable from raw pin bytes, so the bridge tracks the same
# 16-state table the DUT implements (::TAP_NEXT, from dbg_tap.tcl -- the table
# is shared rather than re-typed, so a bridge/BFM divergence is impossible),
# plus the IR, plus the shifted DR.
#
# COST: integer ops only, no `force` and no `run`.  Against 3.9 us per force
# and ~5 us per run, the decode is noise.  It is measured and reported in the
# final stats line as `decode_us` rather than asserted.
#
# NOTE this shadow is an OBSERVER.  Nothing in the data path reads it; if it
# is wrong, the transport still works and only the diagnostics lie.  That is
# the correct blast radius for a convenience.
# ---------------------------------------------------------------------------
set ::RBB_ST   0        ;# TAP state ordinal, dbg_tap.tcl's numbering
set ::RBB_IR   $::IR_IDCODE
set ::RBB_DR   0        ;# shifted IN  on TDI -- the REQUEST
set ::RBB_DRO  0        ;# shifted OUT on TDO -- the RESPONSE
set ::RBB_DRN  0
set ::RBB_DROB 0        ;# how many TDO bits we have actually collected

# State ordinals are LOOKED UP, not typed.  The author's first draft hard-coded
# 2/5/10/13 and every one of them was wrong (SHIFT_DR is 4, UPDATE_DR is 8).
# tap_sidx reads dbg_tap.tcl's own ::TAP_NAMES, so the bridge and the BFM can
# never disagree about the graph, and a renumbering upstream cannot silently
# rot this file -- method rule 16, prefer the edit that satisfies a simple
# check over the check that accommodates the edit.
set ::RBB_S_SHIFTDR  [tap_sidx SHIFT_DR]
set ::RBB_S_UPDATEDR [tap_sidx UPDATE_DR]
set ::RBB_S_SHIFTIR  [tap_sidx SHIFT_IR]
set ::RBB_S_UPDATEIR [tap_sidx UPDATE_IR]
set ::RBB_S_RTI      [tap_sidx RUN_TEST_IDLE]
# THE RTI CENSUS.  dtmcs.idle = 7 is a REQUEST: jtag_dtm.vhd's CDC margin is
# derived assuming the debugger dwells that many Run-Test/Idle cycles after a
# DMI scan.  Whether a given debugger actually does so is a MEASUREMENT, not a
# property of the field, and it must be taken from the wire rather than from
# the debugger's own log annotation.  This counts the dwell between leaving RTI
# and re-entering it, so the histogram answers "was idle=7 honoured" directly.
set ::RBB_RTIDWELL 0
array set ::RBB_RTIHIST {}
# THE NAVIGATION-GAP CENSUS.  The idle DERIVATION in jtag_dtm.vhd's header
# MODELS the debugger's navigation as "Update + idle + 3 TCK" (Update-DR ->
# Run-Test/Idle, `idle` cycles, then Select-DR -> Capture-DR).  That 3 is a
# model of a debugger, so it is measured here rather than assumed: this counts
# the rising edges from entering Update-DR to entering the next Capture-DR,
# which is the window the DM actually has to turn a transaction around.
set ::RBB_S_CAPTUREDR [tap_sidx CAPTURE_DR]
set ::RBB_GAP 0
set ::RBB_GAPACT 0
array set ::RBB_GAPHIST {}

proc rbb_fsm_edge {tms tdi} {
    # Called on each TCK RISING edge with the TMS/TDI that were set up on the
    # preceding low phase -- the same sampling instant the TAP itself uses.
    set s $::RBB_ST
    if {$s == $::RBB_S_SHIFTDR} {
        set ::RBB_DR [expr {($::RBB_DR >> 1) | ($tdi << ($::RBB_DRN - 1))}]
    } elseif {$s == $::RBB_S_SHIFTIR} {
        set ::RBB_IR [expr {(($::RBB_IR >> 1) | ($tdi << 4)) & 0x1F}]
    }
    set ::RBB_ST [lindex [lindex $::TAP_NEXT $s] $tms]
    # RTI dwell census -- see the declaration above.  A rising edge that both
    # starts and ends in Run-Test/Idle is one inserted idle cycle.
    if {$::RBB_ST == $::RBB_S_RTI && $s == $::RBB_S_RTI} {
        incr ::RBB_RTIDWELL
    } elseif {$::RBB_ST != $::RBB_S_RTI && $s == $::RBB_S_RTI} {
        incr ::RBB_RTIHIST($::RBB_RTIDWELL)
        set ::RBB_RTIDWELL 0
    }
    # navigation gap: rising edges from entering Update-DR to entering the
    # next Capture-DR -- the window the DM actually gets.
    if {$::RBB_GAPACT} { incr ::RBB_GAP }
    if {$::RBB_ST == $::RBB_S_UPDATEDR && $s != $::RBB_S_UPDATEDR} {
        set ::RBB_GAP 0 ; set ::RBB_GAPACT 1
    } elseif {$::RBB_GAPACT && $::RBB_ST == $::RBB_S_CAPTUREDR} {
        incr ::RBB_GAPHIST($::RBB_GAP)
        set ::RBB_GAPACT 0
    }
    # entering Shift-DR: size the register the IR selected, and reset BOTH
    # shadows -- the request we are shifting in and the response coming out.
    if {$::RBB_ST == $::RBB_S_SHIFTDR && $s != $::RBB_S_SHIFTDR} {
        # NUMERIC comparison, deliberately, and this cost a real bug before it
        # ever reached the chip.  The first draft used `switch -- $::RBB_IR
        # $::IR_DMI {...}`, which compares as STRINGS: the shifted IR is the
        # integer 17 while $::IR_DMI is the literal "0x11", so every scan fell
        # through to `default` and every DR was sized as BYPASS (DRN=1).  The
        # transport would have worked perfectly and every diagnostic would have
        # been silently empty -- dmiresets stuck at 0, which reads as "the
        # transport never had to recover".  Caught by unit-testing the shadow
        # against a KNOWN-NONZERO expectation instead of against zero.
        if {$::RBB_IR == $::IR_DMI} {
            set ::RBB_DRN $::DRLEN_DMI
        } elseif {$::RBB_IR == $::IR_DTMCS} {
            set ::RBB_DRN $::DRLEN_DTMCS
        } elseif {$::RBB_IR == $::IR_IDCODE} {
            set ::RBB_DRN $::DRLEN_IDCODE
        } else {
            set ::RBB_DRN $::DRLEN_BYPASS
        }
        set ::RBB_DR 0 ; set ::RBB_DRO 0 ; set ::RBB_DROB 0
    }
    if {$::RBB_ST == $::RBB_S_UPDATEDR && $s != $::RBB_S_UPDATEDR} { rbb_update_dr }
}

# Called from rbb_tdo, which is where TDO bits actually arrive.  OpenOCD emits
# the low-phase pin-set, then 'R', then the high-phase pin-set, so a bit
# sampled while we are in SHIFT_DR is the bit about to be clocked out -- LSB
# first, the same order the request goes in.
proc rbb_tdo_shift {b} {
    if {$::RBB_ST != $::RBB_S_SHIFTDR} { return }
    if {$::RBB_DROB >= $::RBB_DRN}     { return }
    set ::RBB_DRO [expr {$::RBB_DRO | ($b << $::RBB_DROB)}]
    incr ::RBB_DROB
}

proc rbb_update_dr {} {
    if {$::RBB_IR == $::IR_DTMCS} {
        # dmireset is bit 16, dmihardreset bit 17 (d3_spec).  This is F1's
        # counter: OpenOCD issues dmireset automatically after every FAILED
        # (toolchain probe claim 22), and VestaRV's DTM drops EVERY non-NOP
        # Update-DR while dmistat is nonzero, so a climbing dmireset count with
        # no successful DMI between them is the deaf-transport signature.
        if {($::RBB_DR >> 16) & 1} { incr ::RBB_DMIRESETS ; rbb_beat_now "DMIRESET" }
        if {($::RBB_DR >> 17) & 1} { incr ::RBB_DMIRESETS ; rbb_beat_now "DMIHARDRESET" }
    } elseif {$::RBB_IR == $::IR_DMI} {
        set op [expr {$::RBB_DR & 3}]
        if {$op != 0} {
            incr ::RBB_DMI_XACT
            # TARGET WEDGE (clause 9) needs "the DM's own observable unchanged
            # over N transactions", so the observable is the CAPTURED response
            # DR -- op and data together -- not the request.  Counted in
            # transactions, never in seconds.
            set rsp [format "%011X" $::RBB_DRO]
            if {$rsp eq $::RBB_LASTDMIRSP} { incr ::RBB_SAMEDMI } else { set ::RBB_SAMEDMI 0 }
            set ::RBB_LASTDMIRSP $rsp
        }
    }
}

# ---------------------------------------------------------------------------
# rbb_set_pins -- clauses 6 and 7.
# ---------------------------------------------------------------------------
# rbb_force -- force ONE pin lazily, and never lie about whether it took.
# Returns 1 if the pin was (re)forced, 0 if it was already at that value.
proc rbb_force {path want shadowvar} {
    upvar #0 $shadowvar cur
    if {$want == $cur} { return 0 }
    if {[catch {force $path [expr {$want ? "'1'" : "'0'"}]} err]} {
        incr ::RBB_FORCE_ERRS
        puts "RBBERROR force FAILED on $path -> $want <$err>.  The shadow is NOT"
        puts "RBBERROR   updated, so the next byte will retry.  If this is tck, the"
        puts "RBBERROR   TAP saw NO EDGE and any TDO sampled since is stale."
        puts "RBBERROR   force_errs=$::RBB_FORCE_ERRS"
        flush stdout
        return 0
    }
    incr ::RBB_FORCES
    set cur $want
    return 1
}

proc rbb_set_pins {v} {
    set tck [expr {($v >> 2) & 1}]
    set tms [expr {($v >> 1) & 1}]
    set tdi [expr {$v & 1}]
    set rising [expr {$tck && !$::RBB_TCKV}]
    # LAZY (clause 7): in a DR shift TMS is constant and TDI changes about half
    # the time, so this is ~1.5 forces per byte instead of 3.
    # A SWALLOWED FORCE ERROR IS THE WORST POSSIBLE FAILURE HERE, AND THE FIRST
    # draft swallowed it.  `catch {force ...}` with the shadow updated
    # unconditionally means a force that did NOT take leaves the bridge
    # believing the pin moved -- and because the forcing is LAZY, the bridge
    # then never re-forces that pin until its shadow changes again.  On tck
    # that is a STOPPED CLOCK: the DUT's TAP freezes, TDO holds its last value,
    # and every subsequent 'R' returns the same bit, so a whole scan comes back
    # all-zeros or all-ones while the transport looks perfectly healthy.  That
    # is precisely the shape of a corrupt DMI read, so it would be diagnosed as
    # a chip defect.  rbb_force reports and REFUSES to update the shadow, so a
    # failed force is a named error and self-heals on the next byte.
    # DATA PINS BEFORE THE CLOCK, always.  All three forces land at the SAME
    # simulation time (there is no `run` between them), so ordering them this
    # way is free; the reverse order asks the TAP's rising_edge(tck) process to
    # read tms/tdi that changed in the same instant, which is a delta race
    # rather than a setup time.  It costs nothing to not have that argument.
    rbb_force $::TAP_TMS $tms ::RBB_TMSV
    rbb_force $::TAP_TDI $tdi ::RBB_TDIV
    set tck_took [rbb_force $::TAP_TCK $tck ::RBB_TCKV]
    if {$rising && !$tck_took} {
        # The shadow said we were low and the force did not take, so there was
        # no edge.  Do not count one: a phantom rising edge would desynchronise
        # the FSM shadow from the DUT for the rest of the session.
        set rising 0
    }
    # Clause 6: a NONZERO run, every byte.  `run 0 ns` does not propagate and
    # same-time forces collapse.  This line is not an optimisation target.
    rbb_advance $::RBB_STEP_NS
    if {$rising} { incr ::RBB_TCK ; rbb_fsm_edge $tms $tdi }
}

# TDO, read through dbg_tap.tcl's tap_bit so the APOSTROPHE trap is handled in
# exactly one place: `value` returns a std_logic as 'x' WITH APOSTROPHES, and a
# first draft that stripped double quotes and compared to "1" returned 0 for
# every bit ever sampled.
proc rbb_tdo {} {
    set b [tap_bit [value $::TAP_TDO]]
    rbb_tdo_shift $b
    return $b
}

# ---------------------------------------------------------------------------
# THE HEARTBEAT.  Verdicts are ORDERINGS over these counters; the only
# wall-clock quantity anywhere is the reporting cadence, which is not a verdict.
# ---------------------------------------------------------------------------
proc rbb_verdict {} {
    if {$::RBB_PENDING > 0}                { return "DEADLOCK" }
    if {$::RBB_SAMEDMI >= $::RBB_WEDGE_N}  { return "TARGET-WEDGE" }
    return $::RBB_STATEDESC
}

proc rbb_beat_now {why} {
    # The control channel's traffic is REPORTED HERE and not only in its own
    # replies, so a session transcript shows exactly how many snapshots the
    # driver asked for and how many commands were refused.  A passive side
    # channel that left no trace in the session record would be an
    # unaccountable second actor in the measurement.
    set ctl ""
    if {[info exists ::RBB_CTL_IN]} {
        set ctl [format " ctl_in=%d ctl_snaps=%d ctl_rejected=%d reentry=%d force_errs=%d" \
                 $::RBB_CTL_IN $::RBB_CTL_SNAPS $::RBB_CTL_REJ \
                 $::RBB_REENTRY $::RBB_FORCE_ERRS]
    }
    puts [format "RBBSTAT %s verdict=%s bytes_in=%d bytes_out=%d pending_out=%d roundtrips=%d tck_count=%d dmi_xact=%d dmiresets=%d same_dmi=%d forces=%d runs=%d sim_time=%s%s" \
          $why [rbb_verdict] $::RBB_BYTES_IN $::RBB_BYTES_OUT $::RBB_PENDING \
          $::RBB_ROUNDTRIPS $::RBB_TCK $::RBB_DMI_XACT $::RBB_DMIRESETS \
          $::RBB_SAMEDMI $::RBB_FORCES $::RBB_RUNS [rbb_simtime] $ctl]
    flush stdout
    set ::RBB_LASTBEAT $::RBB_TCK
}

# SIM TIME, and it is DERIVED rather than queried -- deliberately.
#
# Clause 9 requires sim_time in the heartbeat.  Querying the simulator for it
# from tcl is version-dependent (the author's own sess_snap_time gave up and
# returns "-"), and a field that silently degrades to "?" is a decorative
# metric, which is worse than an absent one because it reads as evidence
# (method rule 9).
#
# So the bridge counts what it itself advanced.  That is EXACT and it is the
# whole of it: clause 5 makes the reads BLOCKING, so during a session nothing
# else in this interpreter can `run`, and every nanosecond of simulated time
# between rbb_session's start and its return was advanced by a line in this
# file.  The preamble (tap_init + tap_reset) is counted the same way.
set ::RBB_SIMNS 0
proc rbb_advance {ns} { tap_run $ns ; incr ::RBB_RUNS ; incr ::RBB_SIMNS $ns }
proc rbb_simtime {} { return "${::RBB_SIMNS}ns(bridge-advanced)" }

proc rbb_beat_maybe {} {
    if {($::RBB_TCK - $::RBB_LASTBEAT) >= $::RBB_BEAT_TCK} { rbb_beat_now "BEAT" }
}

proc rbb_state {desc} {
    if {$desc ne $::RBB_STATEDESC} { set ::RBB_STATEDESC $desc ; rbb_beat_now "STATE" }
}


# ===========================================================================
# THE SERVICE MODEL -- EVENT-DRIVEN ON TWO CHANNELS.
#
# The first draft of this file blocked on `read $S 1` at the top of a serve
# loop.  That satisfies clause 5 for the JTAG channel and is WRONG the moment
# a second channel exists, for a reason worth writing down because it is a
# correctness bug that would have produced plausible green grades:
#
#   While the debugger is idle -- which is EXACTLY when the session script
#   wants a snapshot, between two gdb verbs -- a blocking read on the rbb
#   socket never looks at the control socket at all.  The snapshot request
#   would sit unserviced until OpenOCD sent its next bytes, so the snapshot
#   would land AFTER the next verb had already started.  Every grader here is
#   an ORDERING between snapshots, so the ordering would be wrong BY
#   CONSTRUCTION on a perfectly correct chip.
#
# So the interpreter waits on EVENTS, not on one channel: `fileevent` +
# `vwait`, both measured present in xmsim's interpreter (ipc probe C2).
#
# THIS DOES NOT WEAKEN CLAUSE 5, on either its letter or its purpose.  The
# clause forbids a POLL LOOP because a poll loop ADVANCES SIM TIME while
# waiting for the debugger, which makes sim-time-per-op a function of the
# human and destroys reproducibility for the running tiles (ipc C15's stated
# rationale is "sim time advances only for JTAG edges").  `vwait` is a
# blocking wait, not a poll; there is no `run` anywhere on the wait path or
# on the control path; sim time advances ONLY inside rbb pin-op execution.
#
# THE RE-ENTRANCY GUARD, and it is not paranoia.  If `run` inside the rbb
# handler ever pumps the Tcl event loop, a control event could fire in the
# MIDDLE of a chunk -- landing a snapshot at an arbitrary instant inside a
# verb, which is the precise failure this design exists to remove.  ::RBB_BUSY
# defers control requests to the end of chunk processing.  That is correct
# whether or not `run` pumps the loop, so the bridge does not depend on an
# answer it has not measured.
#
# THE CONTROL CHANNEL IS PASSIVE-ONLY AND THE WHITELIST IS THE ENFORCEMENT.
# It accepts snapshot-class READS and nothing else; every other verb is
# REJECTED BY NAME with a reply saying so, and counted.  No force, no run, no
# DMI ever reaches it.  Its traffic appears in the heartbeat (ctl_in /
# ctl_snaps / ctl_rejected) so a transcript shows what it did.
# ===========================================================================

set ::RBB_BUSY      0
set ::RBB_CTLQ      {}
set ::RBB_CTL_IN    0
set ::RBB_CTL_SNAPS 0
set ::RBB_CTL_REJ   0
set ::RBB_CLI       ""
set ::RBB_CTL       ""
set ::RBB_INCB      0
set ::RBB_REENTRY   0

# --- the JTAG channel -------------------------------------------------------

proc rbb_on_rbb {S} {
    # RE-ENTRANCY IS THE ONE STRUCTURAL DIFFERENCE BETWEEN THIS TRANSPORT AND
    # THE BFM THAT IS PROVEN GOOD, AND IT IS GUARDED HERE.
    #
    # rbb_process advances simulation time (`run`) from INSIDE a fileevent
    # callback.  Tcl is free to service the event loop while that call is in
    # progress, so a byte arriving mid-chunk can re-enter this callback and
    # interleave a second chunk's pin-sets and TDO samples with the first
    # one's.  The result is not a crash: it is a handful of scrambled bits in
    # an otherwise healthy session -- a scan that reads back all-zeros or
    # all-ones -- which is indistinguishable from a chip returning garbage,
    # and it gets WORSE as the per-byte `run` gets longer, because the window
    # is the run.
    #
    # Returning without reading is safe and is why this is a guard rather than
    # a queue: the channel is still readable, so Tcl re-fires the event as soon
    # as the outer call returns, and the outer call's own `read` drains
    # whatever arrived meanwhile.  RBB_REENTRY counts the events, so the
    # heartbeat says whether this ever actually happened instead of leaving it
    # an argument.
    if {$::RBB_INCB} { incr ::RBB_REENTRY ; return }
    set ::RBB_INCB 1
    # Clause 10: an error raised inside a socket callback goes to bgerror and
    # is SILENT here.  The ipc probe hit exactly this and the symptom was a
    # hang with no error.  Every callback body is catch-wrapped and REPORTS.
    if {[catch {rbb_process $S} err]} {
        set ::RBB_INCB 0
        puts "RBBERROR rbb handler: <$err>"
        puts "RBBERROR $::errorInfo"
        flush stdout
        catch {close $S}
        set ::RBB_DONE 1
    }
    set ::RBB_INCB 0
}

proc rbb_process {S} {
    # Channel is non-blocking; the event loop already told us it is readable,
    # so this returns the whole buffered chunk (clause 4, 6.5x measured) and
    # never waits.
    set c [read $S]
    if {$c eq ""} {
        if {[eof $S]} {
            catch {close $S}
            set ::RBB_CLI ""
            puts "RBBINFO debugger closed the connection"
            flush stdout
            set ::RBB_DONE 1
        }
        return
    }
    rbb_state "PROGRESSING"
    incr ::RBB_ROUNDTRIPS
    set ::RBB_BUSY 1
    set out ""
    set quit 0
    foreach ch [split $c ""] {
        incr ::RBB_BYTES_IN
        if {$ch eq "R"} {
            append out [rbb_tdo]
            incr ::RBB_PENDING
        } elseif {[string match {[0-7]} $ch]} {
            rbb_set_pins [expr {[scan $ch %c] - 48}]
        } elseif {$ch eq "Q"} {
            set quit 1 ; break
        } elseif {[string match {[rstu]} $ch]} {
            rbb_reset_cmd $ch
        }
        # 'B'/'b' blink and anything else: no reply, no effect (clause 1).
    }
    if {$out ne ""} {
        if {$::RBB_NOFLUSH} {
            # DELIBERATE PROVOCATION ONLY (d5_spec 2.9 as amended by R-D5-2).
            # We hold the reply the debugger is blocked on, so the DEADLOCK
            # verdict can be SEEN TO FIRE.  A discriminator never observed
            # firing is not known to work.
            puts "RBBPROVOKE withholding [string length $out] reply byte(s) ON PURPOSE (D5_NOFLUSH=1) -- the next heartbeat must read verdict=DEADLOCK"
            flush stdout
            set ::RBB_BUSY 0
            rbb_state "BLOCKED-ON-DEBUGGER"
            rbb_beat_now "PROVOKE"
            return
        }
        puts -nonewline $S $out
        flush $S
        incr ::RBB_BYTES_OUT [string length $out]
        set ::RBB_PENDING 0
    }
    set ::RBB_BUSY 0
    rbb_ctl_drain
    rbb_beat_maybe
    if {$quit} {
        puts "RBBINFO 'Q' received -- ending the session cleanly"
        flush stdout
        catch {close $S}
        set ::RBB_CLI ""
        set ::RBB_DONE 1
        return
    }
    rbb_state "BLOCKED-ON-DEBUGGER"
}

proc rbb_reset_cmd {ch} {
    set v [string first $ch "rstu"]
    set trst [expr {($v >> 1) & 1}]
    set srst [expr {$v & 1}]
    set n [expr {$trst ? 0 : 1}]
    if {$n != $::RBB_TRSTNV} {
        catch {force $::TAP_TRSTN [expr {$n ? "'1'" : "'0'"}]} ; incr ::RBB_FORCES
        set ::RBB_TRSTNV $n
    }
    incr ::RBB_TRST_REQ
    # SRST IS A LOGGED NO-OP, and the log line is the point.  VestaRV has NO
    # debugger-reachable system reset: ndmreset and hartreset are read-zero
    # WARL, and the only chip reset is the `resetn` pad, which also resets dm0
    # and drops the session.  Accepting SRST silently would let a debugger
    # believe it had reset something.  R-DD4(3).
    if {$srst} {
        incr ::RBB_SRST_REQ
        puts "RBBSRST ignored: SRST asserted by the debugger and NOT ACTED ON -- VestaRV has no debugger-reachable system reset (ndmreset/hartreset read-zero WARL; the real reset is the per-tile PWRCTRL path, harts 1..N-1 only). count=$::RBB_SRST_REQ"
        flush stdout
    }
    rbb_advance $::RBB_STEP_NS
}

proc rbb_accept {S addr port} {
    # Clause 3: NEVER -buffering none -- 24 us PER CHARACTER, one syscall per
    # byte.  `full` + explicit flush sends a reply in ONE write (13.7 us,
    # faster than the python-to-python localhost floor).
    fconfigure $S -translation binary -buffering full -blocking 0
    set ::RBB_CLI $S
    set ::RBB_T0 [clock microseconds]
    puts "RBBINFO connection from $addr:$port" ; flush stdout
    rbb_state "BLOCKED-ON-DEBUGGER"
    fileevent $S readable [list rbb_on_rbb $S]
}

# --- the control channel (PASSIVE-ONLY) -------------------------------------

proc rbb_ctl_accept {S addr port} {
    fconfigure $S -translation auto -buffering line -blocking 0
    set ::RBB_CTL $S
    puts "RBBINFO control connection from $addr:$port" ; flush stdout
    fileevent $S readable [list rbb_on_ctl $S]
}

proc rbb_on_ctl {S} {
    if {[catch {rbb_ctl_read $S} err]} {
        puts "RBBERROR control handler: <$err>"
        puts "RBBERROR $::errorInfo"
        flush stdout
    }
}

proc rbb_ctl_read {S} {
    while {[gets $S line] >= 0} {
        set line [string trim $line]
        if {$line eq ""} { continue }
        incr ::RBB_CTL_IN
        if {$::RBB_BUSY} {
            # Re-entrancy guard: never let a snapshot land in the middle of a
            # chunk.  Deferred to rbb_ctl_drain at the end of chunk processing.
            lappend ::RBB_CTLQ $line
        } else {
            rbb_ctl_exec $S $line
        }
    }
    if {[eof $S]} {
        catch {close $S}
        set ::RBB_CTL ""
        puts "RBBINFO control channel closed" ; flush stdout
    }
}

proc rbb_ctl_drain {} {
    if {[llength $::RBB_CTLQ] == 0} { return }
    set q $::RBB_CTLQ
    set ::RBB_CTLQ {}
    foreach line $q { rbb_ctl_exec $::RBB_CTL $line }
}

proc rbb_ctl_reply {S msg} {
    if {$S eq ""} { return }
    catch { puts $S $msg ; flush $S }
}

# THE WHITELIST.  Passive reads only.  Anything else is rejected BY NAME --
# not ignored, because a silently-ignored control command looks exactly like a
# serviced one from the driver's side.
proc rbb_ctl_exec {S line} {
    set verb [string toupper [lindex $line 0]]
    set args [lrange $line 1 end]
    switch -- $verb {
        SNAP {
            set label [lindex $args 0]
            if {$label eq ""} { set label "unlabelled" }
            if {[llength [info procs sess_snap]] == 0} {
                rbb_ctl_reply $S "ERR SNAP: dbg_sess_lib.tcl is not sourced in this harness"
                return
            }
            sess_snap $label
            incr ::RBB_CTL_SNAPS
            rbb_ctl_reply $S "OK SNAP $label"
            flush stdout
        }
        PROBE {
            if {[llength [info procs sess_probe_report]] == 0} {
                rbb_ctl_reply $S "ERR PROBE: dbg_sess_lib.tcl is not sourced" ; return
            }
            sess_probe_report
            rbb_ctl_reply $S "OK PROBE"
            flush stdout
        }
        ORACLE {
            if {[llength [info procs sess_oracle_dump]] == 0} {
                rbb_ctl_reply $S "ERR ORACLE: dbg_sess_lib.tcl is not sourced" ; return
            }
            set h [lindex $args 0]
            if {$h eq ""} { set h 1 }
            sess_oracle_dump $h [lrange $args 1 end]
            rbb_ctl_reply $S "OK ORACLE $h"
            flush stdout
        }
        TCM {
            # TCM <addr> -- the word at <addr> in EVERY hart's own private TCM.
            # Added by the fifth implementer for the T4 Z0 question: a software
            # breakpoint is a memory write, and a tile's TCM is PRIVATE, so
            # "the Z0 landed in the wrong hart's TCM" and "the Z0 never landed
            # at all" are two different findings that a single-hart read cannot
            # tell apart.  A census over all N harts distinguishes them in one
            # line.  Passive: sess_tcm_word is a simulator peek -- no force, no
            # run, no DMI -- so it obeys the same PASSIVE-ONLY contract as SNAP.
            if {[llength [info procs sess_tcm_word]] == 0} {
                rbb_ctl_reply $S "ERR TCM: dbg_sess_lib.tcl is not sourced" ; return
            }
            set a [lindex $args 0]
            if {$a eq ""} { rbb_ctl_reply $S "ERR TCM: no address" ; return }
            # NOT `expr {... ? ... : [format 0x%08X $w]}`.  Tcl's expr RE-PARSES
            # the formatted string as a NUMBER, so the hex comes back out in
            # decimal (0x5D500313 -> 1565524755) -- measured, in this file's
            # first run.  It is the same trap that turned 00010004 into 4100
            # for the fourth implementer, and it survives review because a
            # value with a letter in it passes through untouched.  Format
            # OUTSIDE any expr, always.
            set out {}
            for {set h 0} {$h < $::D5_NHARTS} {incr h} {
                set w [sess_tcm_word $h $a]
                if {$w eq ""} { set t "(absent)" } else { set t [format 0x%08X $w] }
                lappend out "h$h=$t"
            }
            puts "DMILOG TCM CENSUS at [format 0x%05X $a]: [join $out {  }]"
            flush stdout
            rbb_ctl_reply $S "OK TCM $a"
        }
        STAT { rbb_beat_now "CTL" ; rbb_ctl_reply $S "OK STAT" }
        PING { rbb_ctl_reply $S "OK PING" }
        default {
            incr ::RBB_CTL_REJ
            rbb_ctl_reply $S "REJECTED $verb -- the control channel is PASSIVE-ONLY. Permitted: SNAP <label>, PROBE, ORACLE <hart> [addrs], TCM <addr>, STAT, PING. It performs no force, no run and no DMI, by design: anything that advanced simulation time here would make the session non-reproducible for the running tiles, and anything that drove the DM would put a second master on the port the debugger is using."
            puts "RBBCTLREJ $verb (count=$::RBB_CTL_REJ)" ; flush stdout
        }
    }
}

# ---------------------------------------------------------------------------
# rbb_listen -- clause 2.  The line shape is EXACTLY what testlib.py scrapes
# (`Listening on port (\d+).`, testlib.py:222, the MultiSpike/rbb_daisychain
# path).  CORRECTION TO THE RECORD: that is NOT the line spike itself prints --
# spike says "Listening for remote bitbang connection on port N." and testlib
# scrapes THAT at :112.  We print the shorter shape because it is the one a
# generic scraper matches; the real mechanism for our harness is that the
# VestaRV target .py exports REMOTE_BITBANG_HOST/PORT itself.  The printed
# line is free insurance, not a dependency.
# ---------------------------------------------------------------------------
proc rbb_listen {} {
    set srv [socket -server rbb_accept -myaddr 127.0.0.1 $::RBB_PORT]
    set port [lindex [fconfigure $srv -sockname] 2]
    set ::RBB_SRV $srv

    set csrv [socket -server rbb_ctl_accept -myaddr 127.0.0.1 0]
    set cport [lindex [fconfigure $csrv -sockname] 2]
    set ::RBB_CSRV $csrv

    if {$::RBB_PORTFILE ne ""} {
        # write-then-rename so a reader never sees a half-written file
        set f [open "$::RBB_PORTFILE.tmp" w]
        puts -nonewline $f "$port $cport"
        close $f
        file rename -force "$::RBB_PORTFILE.tmp" $::RBB_PORTFILE
    }
    puts "Listening on port $port."
    puts "RBBINFO control port $cport (PASSIVE-ONLY: SNAP/PROBE/ORACLE/TCM/STAT/PING)"
    puts "RBBINFO step=${::RBB_STEP_NS}ns period=[expr {2*$::RBB_STEP_NS}]ns beat_tck=$::RBB_BEAT_TCK wedge_n=$::RBB_WEDGE_N noflush=$::RBB_NOFLUSH"
    puts "RBBINFO expect ONE spurious 'SIMULATION TIMEOUT REACHED' REPORT/FAILURE at sim t=100ms -- the tb watchdog fires exactly once and the session continues (riscv_tb.vhd; tree probe C44/C45). Do not debug it."
    flush stdout
    return [list $port $cport]
}

# ---------------------------------------------------------------------------
# rbb_session -- listen, serve one debugger, return.  The caller grades.
#
# `tap_init` BEFORE anything: riscv_tb declares MCU as a COMPONENT whose port
# list ends at a0_3, so trstn sits at its entity default '0' and the TAP is
# held in ASYNCHRONOUS RESET.  Without this the TAP answers IDCODE 0x00000000,
# which is the least informative possible failure.
#
# THE Q CONTRACT: 'Q' closes the socket and RETURNS.  It does NOT `exit`.  The
# D5 session graders are passive and live in THIS interpreter, so they can only
# run once the service loop has handed the interpreter back.  A bridge that
# exited on Q would take every post-session snapshot with it.
# ---------------------------------------------------------------------------
proc rbb_session {} {
    set ::TAP_WATCH_READY 0        ;# clause 7: 143 us/TCK by itself
    tap_init
    set ::RBB_TRSTNV 1
    set ::RBB_TCKV 0 ; set ::RBB_TMSV 0 ; set ::RBB_TDIV 0
    set ::RBB_ST 0 ; set ::RBB_IR $::IR_IDCODE
    set ports [rbb_listen]
    set ::RBB_DONE 0
    set ::RBB_T0 [clock microseconds]
    if {[catch {vwait ::RBB_DONE} verr]} {
        # Measured fallback.  If vwait is unavailable in this interpreter the
        # bridge still works, but `update` is a POLL of the event loop -- it
        # advances no simulation time (there is no `run` here), so clause 5 is
        # still satisfied; it just burns CPU.  Recorded as a deviation if it
        # ever fires.
        puts "RBBERROR vwait failed <$verr> -- falling back to an update spin (no sim time is advanced on this path)"
        flush stdout
        set guard 0
        while {!$::RBB_DONE && $guard < 2000000000} { update ; incr guard }
    }
    catch {close $::RBB_SRV}
    catch {close $::RBB_CSRV}
    catch {if {$::RBB_CLI ne ""} { close $::RBB_CLI }}
    catch {if {$::RBB_CTL ne ""} { close $::RBB_CTL }}
    rbb_beat_now "SESSION-END"
    set us [expr {[clock microseconds] - $::RBB_T0}]
    puts [format "RBBCOST wall=%.3fs bytes_in=%d bytes_out=%d tck=%d ctl_in=%d ctl_snaps=%d ctl_rejected=%d %s" \
          [expr {$us/1.0e6}] $::RBB_BYTES_IN $::RBB_BYTES_OUT $::RBB_TCK \
          $::RBB_CTL_IN $::RBB_CTL_SNAPS $::RBB_CTL_REJ \
          [expr {$::RBB_TCK > 0 ? [format "us_per_tck=%.1f" [expr {double($us)/$::RBB_TCK}]] : "us_per_tck=n/a"}]]
    set hist {}
    foreach k [lsort -integer [array names ::RBB_RTIHIST]] {
        lappend hist "${k}:$::RBB_RTIHIST($k)"
    }
    puts "RBBRTI dwell histogram (idle_cycles:count) = [join $hist { }]"
    set gh {}
    foreach k [lsort -integer [array names ::RBB_GAPHIST]] {
        lappend gh "${k}:$::RBB_GAPHIST($k)"
    }
    puts "RBBGAP Update-DR -> next Capture-DR, in TCK (gap:count) = [join $gh { }]"
    puts "RBBGAP  x T_TCK = the absolute time the DM gets to turn a transaction"
    puts "RBBGAP  around.  jtag_dtm.vhd: register access needs 417 ns, PROXIED"
    puts "RBBGAP  access up to 833 ns.  Compare, do not assume."
    puts "RBBRTI  dtmcs.idle advertises 7.  Any mass at dwells BELOW 7 means this"
    puts "RBBRTI  debugger did NOT honour the advertised dwell -- measured on the"
    puts "RBBRTI  wire, not read off the debugger's own log annotation."
    puts "RBBNOTE us_per_tck above INCLUDES the debugger's own think time and is NOT a health metric (ipc C29 measured 20,130 us/TCK on a perfectly healthy session). Health is the verdict field of RBBSTAT."
    puts "RBBEND session closed, interpreter returned to the harness (Q does not exit -- the graders run here)."
    flush stdout
    return $ports
}
