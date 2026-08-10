# =============================================================================
# dbg_sessrun.tcl -- THE GRADED OpenOCD/gdb SESSION.  This is dbg_sessgrade.tcl
# (the acceptance author's FAIL leg, and their stated wiring template) with the
# one difference that file names: where it calls `run`, this calls the bridge's
# service loop.
#
#   D5_PORTFILE=<path> D5_PROFILE=d5sess ./xrun_dbg_verify.sh \
#       verify_castaliadebug ../kba/xrv32ua-p-d5sessmp.rcf dbg_sessrun.tcl
#
# =============================================================================
# THE DRIVER CONTRACT -- READ THIS BEFORE WRITING A GDB SCRIPT.
#
# Every grader below is an ORDERING BETWEEN SNAPSHOTS, and the snapshots are
# taken by the DRIVER, over the bridge's passive control channel, at the
# instants only the driver knows about (between one gdb verb and the next).
# The harness cannot take them itself: it is inside the bridge's event loop for
# the whole session.
#
# The driver therefore sends, on the control port, one line per instant:
#
#   SNAP ATTACH        after attach + hart enumeration, before anything is halted
#   SNAP HALT_PRE      immediately before halting the victim
#   SNAP HALT_POST     immediately after the victim reports halted
#   SNAP COOKIE_POST   after the three cookie writes (a5, mscratch, MEMW)
#   SNAP BP_RESUMED    after `continue` toward the software breakpoint
#   SNAP BP_HIT        after the breakpoint reports hit
#   SNAP STEP_POST     after one `stepi`
#   SNAP RESUME_POST   after the final resume
#   SNAP RH_GATED      after PWRCR gates the victim tile (reset-halt, 5.4-1)
#   SNAP RH_POST       after the victim halts at reset release
#   SNAP MSIP_RESUME   immediately after the wedge-walk resume (5.4-3)
#   SNAP MSIP_LATER    a second time, later, WITHOUT resuming anything
#   SNAP MSIP_CLEARED  after `set *(unsigned*)(0x5000+4h) = 0`, before resume
#
# A0 is taken by THIS FILE before the bridge starts listening, so there is
# always a pre-session baseline even if the driver never connects.
#
# WHY THE LABELS ARE FIXED AND NOT DISCOVERED.  A grader called with a label
# that was never snapped reports NOT-GRADED, which is counted separately and is
# never a pass (sess_grade_summary refuses to say passed while NOT-GRADED > 0).
# So a driver that skips an instant produces a loud, named gap rather than a
# quiet green.  That is the intended failure mode: the contract is enforced by
# the summary, not by trust.
#
# THE CONTROL CHANNEL IS PASSIVE-ONLY.  It performs snapshot-class READS and
# nothing else -- no force, no run, no DMI.  Two reasons, and both are
# correctness rather than tidiness: anything that advanced simulation time
# there would make the session non-reproducible for the RUNNING tiles (the
# clause-5 argument), and anything that drove the DM would put a SECOND MASTER
# on the very port the debugger is using, which changes what is being measured.
# =============================================================================

if {[llength [info procs sess_snap]] == 0} {
    if {[file exists dbg_sess_lib.tcl]} {
        source dbg_sess_lib.tcl
    } else {
        source ../behavioral_mp/dbg_sess_lib.tcl
    }
}
if {[llength [info procs rbb_session]] == 0} {
    if {[file exists dbg_rbb_bridge.tcl]} {
        source dbg_rbb_bridge.tcl
    } else {
        source ../behavioral_mp/dbg_rbb_bridge.tcl
    }
}

# The victim and the witnesses.  Hart 2 is the victim because the d5sess image
# gives harts 0, 1 and 2 monotonic LIVE counters (dbg_sess_lib's own layout:
# LIVE0 0x10058, LIVE1 0x1005C, LIVE2 0x10060), so halting 2 leaves TWO
# independent witnesses for the "the others keep running" clause instead of the
# one the dbgtrpmp profile can offer.  Hart 3 is deliberately never launched.
set ::D5_VICTIM  [expr {[info exists ::env(D5_VICTIM)] ? $::env(D5_VICTIM) : 2}]
set ::D5_OTHERS  [expr {[info exists ::env(D5_OTHERS)] ? $::env(D5_OTHERS) : [list 0 1]}]

# The breakpoint site and the step successor come off OBJDUMP of the session
# image at a labelled site, never off a directive -- `.balign` is a silent
# no-op inside a `.option norvc` region, so a directive is not evidence about
# an address (method rule 7).  The graders assert the pre-session word equals
# the objdump original, so a wrong address FAILS LOUDLY instead of silently
# covering nothing.
set ::D5_BPADDR  [expr {[info exists ::env(D5_BPADDR)]  ? $::env(D5_BPADDR)  : 0}]
set ::D5_BPWORD  [expr {[info exists ::env(D5_BPWORD)]  ? $::env(D5_BPWORD)  : 0}]
set ::D5_STEPTO  [expr {[info exists ::env(D5_STEPTO)]  ? $::env(D5_STEPTO)  : 0}]

puts "DMILOG dbg_sessrun: profile=$::D5_PROFILE NHARTS=$::D5_NHARTS victim=$::D5_VICTIM others={$::D5_OTHERS}"
puts "DMILOG dbg_sessrun: bp=[format 0x%08X $::D5_BPADDR] origword=[format 0x%08X $::D5_BPWORD] stepto=[format 0x%08X $::D5_STEPTO]"
flush stdout

# The image must be RUNNING before the session, or every snapshot is taken on a
# chip parked in the boot ROM and the known-nonzero control cannot fire.  The
# acceptance author recorded this as their MISS 1 and it is worth inheriting:
# a FAIL leg whose control does not fire proves much less than it appears to.
if {![d4_wait_ready]} {
    puts "DMILOG dbg_sessrun: WARNING -- the image never reached READY.  Every"
    puts "DMILOG   grade below would be about a parked chip.  Treat as INVALID."
    flush stdout
}

sess_probe_report
sess_snap A0

# ---- the session.  The driver does everything; we get the interpreter back
# ---- when it sends 'Q' or closes.
rbb_session

# ---------------------------------------------------------------------------
# Grading, after the fact, from the snapshots the driver asked for.
# ---------------------------------------------------------------------------
sess_grade_attach A0 ATTACH
sess_grade_hartcensus ATTACH [concat $::D5_OTHERS $::D5_VICTIM]

sess_grade_halt_one A0 HALT_PRE HALT_POST $::D5_VICTIM $::D5_OTHERS

sess_grade_gpr_write HALT_POST COOKIE_POST $::D5_VICTIM
sess_grade_csr_write HALT_POST COOKIE_POST $::D5_VICTIM
sess_grade_mem_write HALT_POST COOKIE_POST

if {$::D5_BPADDR != 0} {
    set prev [sess_tcm_word $::D5_VICTIM $::D5_BPADDR]
    sess_grade_swbp $prev BP_RESUMED BP_HIT $::D5_VICTIM $::D5_BPADDR $::D5_BPWORD
    sess_grade_step BP_HIT STEP_POST $::D5_VICTIM $::D5_STEPTO
} else {
    puts "DMILOG dbg_sessrun: D5_BPADDR unset -- swbp/step deliberately NOT called"
    puts "DMILOG   (a grader called with a fabricated address would cover nothing"
    puts "DMILOG    while looking green; NOT-GRADED is the honest outcome)."
}

sess_grade_resume BP_HIT RESUME_POST $::D5_VICTIM
sess_grade_reset_halt HALT_POST RH_GATED RH_POST $::D5_VICTIM

set wedged [sess_grade_msip_wedge MSIP_RESUME MSIP_LATER $::D5_VICTIM]
sess_grade_msip_rescue MSIP_RESUME MSIP_CLEARED RESUME_POST $::D5_VICTIM $wedged

sess_grade_sticky "end of a real OpenOCD/gdb session"
sess_oracle_dump $::D5_VICTIM [list 0x10050 0x10054 0x10058 0x1005C 0x10060 0x10064]

foreach h [list 1 2 3] { puts "DMILOG   hart$h state=[d2_state $h]" }
sess_grade_summary "dbg_sessrun" 15
flush stdout
exit
