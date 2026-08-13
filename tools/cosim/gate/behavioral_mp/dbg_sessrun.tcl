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
#   SNAP RH_PRE        the RH victim halted and quiescent, immediately BEFORE
#                      the PWRCR write (reset-halt, 5.4-1)
#   SNAP RH_GATED      after PWRCR gates the RH victim's tile
#   SNAP RH_POST       after the RH victim halts at reset release
#   SNAP MSIP_RESUME   immediately after the wedge-walk resume (5.4-3)
#   SNAP MSIP_LATER    a second time, later, WITHOUT resuming anything
#   SNAP MSIP_CLEARED  after `set *(unsigned*)(0x5000+4h) = 0`, before resume
#   SNAP MSIP_RESCUED  after the RESCUED resume -- the outcome the rescue
#                      grader reads
#
# A0 is taken by THIS FILE before the bridge starts listening, so there is
# always a pre-session baseline even if the driver never connects.
#
# =============================================================================
# FOUR WIRING DEFECTS IN THE FIRST DRAFT OF THIS FILE, FOUND BY READING IT
# AGAINST THE GRADERS' OWN ARGUMENT LISTS AT THE T4 HANDOFF, AND FIXED HERE.
# They are recorded rather than quietly corrected, because every one of them
# would have produced a FAILING grader on a CORRECT chip -- the expensive
# direction of wrong.
#
#  D1  `set prev [sess_tcm_word ...]` ran AFTER `rbb_session`, so the value
#      passed to sess_grade_swbp as the PRE-session word was literally the same
#      read the grader then makes for the POST-session word.  SG-G1's two
#      clauses ("the pre-session word equals the objdump original" AND "the
#      word is now an ebreak") are mutually exclusive under that wiring: it
#      could never pass.  The capture now happens before the session.
#
#  D2  sess_grade_reset_halt was called with `before` = HALT_POST.  Its
#      zero-retire clause (SG-J3) asserts the victim's liveness counter is
#      UNCHANGED from `before` to `after` -- but between HALT_POST and RH_POST
#      the victim is deliberately resumed twice (into the breakpoint, and
#      again at RESUME_POST), so its counter MUST move.  A correct chip failed
#      the clause. Fixed by the new RH_PRE instant.
#
#  D3  sess_grade_msip_rescue was called with `after` = RESUME_POST, which is
#      an instant BEFORE the wedge is even walked into.  SG-K3 reads the
#      victim's state "after the rescued resume" from it.  Fixed by the new
#      MSIP_RESCUED instant.
#
#  D4  ONE victim served every grader.  The reset-halt leg power-cycles the
#      victim's tile, and that is a COLD gate with no retention: the tile's TCM
#      is EMPTY afterwards.  SG-G1 reads the breakpoint word out of the TCM at
#      GRADING time, i.e. after the whole session -- so a single victim erases
#      the evidence for its own breakpoint grader.  The legs are split:
#        D5_VICTIM   (default 2) halt-one / cookies / breakpoint / step / resume
#        D5_RHVICTIM (default 1) reset-halt / msip wedge / msip rescue
#      Hart 2 stays the halt-one victim because d5_spec 5.2 words the headline
#      clause that way, and the d5sess image gives harts 0 and 1 the two
#      independent witnesses it needs.  Hart 1 takes the power-cycle legs
#      because the recovery lever exists FOR HARTS 1..N-1 ONLY -- PWRCR bit 0
#      is RO-0 and hart 0 has no lever at all.
# =============================================================================
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
# The power-cycle legs run on a DIFFERENT hart -- see defect D4 in the header.
set ::D5_RHVICTIM [expr {[info exists ::env(D5_RHVICTIM)] ? $::env(D5_RHVICTIM) : 1}]

# The breakpoint site and the step successor come off OBJDUMP of the session
# image at a labelled site, never off a directive -- `.balign` is a silent
# no-op inside a `.option norvc` region, so a directive is not evidence about
# an address (method rule 7).  The graders assert the pre-session word equals
# the objdump original, so a wrong address FAILS LOUDLY instead of silently
# covering nothing.
set ::D5_BPADDR  [expr {[info exists ::env(D5_BPADDR)]  ? $::env(D5_BPADDR)  : 0}]
set ::D5_BPWORD  [expr {[info exists ::env(D5_BPWORD)]  ? $::env(D5_BPWORD)  : 0}]
set ::D5_STEPTO  [expr {[info exists ::env(D5_STEPTO)]  ? $::env(D5_STEPTO)  : 0}]

puts "DMILOG dbg_sessrun: profile=$::D5_PROFILE NHARTS=$::D5_NHARTS victim=$::D5_VICTIM others={$::D5_OTHERS} rh_victim=$::D5_RHVICTIM"
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

# DEFECT D1: this capture MUST happen before the session.  It is the
# PRE-session word at the breakpoint site, and the grader compares it against
# the objdump-derived original while separately requiring the word to be an
# ebreak by grading time.  Read after the session, it was the same read twice.
set ::D5_BPPREV [expr {$::D5_BPADDR != 0 ? [sess_tcm_word $::D5_VICTIM $::D5_BPADDR] : ""}]
puts "DMILOG dbg_sessrun: pre-session word at [format 0x%08X $::D5_BPADDR] in hart $::D5_VICTIM's TCM = [expr {$::D5_BPPREV eq {} ? {(absent)} : [format 0x%08X $::D5_BPPREV]}]"
flush stdout

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
    sess_grade_swbp $::D5_BPPREV BP_RESUMED BP_HIT $::D5_VICTIM $::D5_BPADDR $::D5_BPWORD
    sess_grade_step BP_HIT STEP_POST $::D5_VICTIM $::D5_STEPTO
} else {
    puts "DMILOG dbg_sessrun: D5_BPADDR unset -- swbp/step deliberately NOT called"
    puts "DMILOG   (a grader called with a fabricated address would cover nothing"
    puts "DMILOG    while looking green; NOT-GRADED is the honest outcome)."
}

sess_grade_resume BP_HIT RESUME_POST $::D5_VICTIM
sess_grade_reset_halt RH_PRE RH_GATED RH_POST $::D5_RHVICTIM

set wedged [sess_grade_msip_wedge MSIP_RESUME MSIP_LATER $::D5_RHVICTIM]
sess_grade_msip_rescue MSIP_RESUME MSIP_CLEARED MSIP_RESCUED $::D5_RHVICTIM $wedged

# ---------------------------------------------------------------------------
# THE INHERITED-WIRING CHECK.  Not a grader, and deliberately not counted: it
# prints what defects D2 and D3 above WOULD have graded, from this same run's
# snapshots, so that the claim "the old wiring could not pass on a correct
# chip" is a measurement in the record rather than an assertion in a comment.
# ---------------------------------------------------------------------------
if {[info exists SNAP(HALT_POST,live,$::D5_RHVICTIM)] && [info exists SNAP(RH_POST,live,$::D5_RHVICTIM)]} {
    set ob $SNAP(HALT_POST,live,$::D5_RHVICTIM) ; set oa $SNAP(RH_POST,live,$::D5_RHVICTIM)
    set nb $SNAP(RH_PRE,live,$::D5_RHVICTIM)
    puts "DMILOG INHERITED-WIRING CHECK (not a grader) -- SG-J3 zero-retire under the OLD before=HALT_POST wiring: $ob -> $oa, equal=[expr {$ob == $oa}].  Under the fixed before=RH_PRE wiring: $nb -> $oa, equal=[expr {$nb == $oa}]"
}
if {[info exists SNAP(RESUME_POST,state,$::D5_RHVICTIM)] && [info exists SNAP(MSIP_RESCUED,state,$::D5_RHVICTIM)]} {
    puts "DMILOG INHERITED-WIRING CHECK (not a grader) -- SG-K3 read its outcome state from RESUME_POST ('$SNAP(RESUME_POST,state,$::D5_RHVICTIM)'), an instant BEFORE the wedge was walked into; the fixed wiring reads MSIP_RESCUED ('$SNAP(MSIP_RESCUED,state,$::D5_RHVICTIM)')"
}

# ---------------------------------------------------------------------------
# THE HALT-WINDOW DIAGNOSTIC.  Not a grader, and deliberately not counted.
#
# SG-Cb asks for TWO things at once from the SAME pair of labels: the victim
# must read RUNNING at `before` (SG-Ca's clause) and its liveness counter must
# be UNCHANGED from `before` to `after` (SG-Cb's clause).  Between those two
# instants the debugger has to CARRY OUT the halt, and on this transport that
# is thousands of TCK -- during every one of which the still-running victim
# retires instructions and its counter climbs.  The two clauses are therefore
# jointly unsatisfiable by any session script on a CORRECT chip, which is why
# this is printed rather than worked around.
#
# What the chip actually owes is printed beside it: across a window that BEGINS
# at a CONFIRMED halt (HALT_CONF, taken after OpenOCD's own `targets` table
# reports halted) and contains real JTAG traffic, the victim's counter must not
# move at all.  That is the measurable form of "the halt retired nothing", and
# it is an ordering between two counter reads with no duration in it.
# ---------------------------------------------------------------------------
if {[info exists SNAP(HALT_PRE,live,$::D5_VICTIM)] && [info exists SNAP(HALT_POST,live,$::D5_VICTIM)]} {
    set gb $SNAP(HALT_PRE,live,$::D5_VICTIM) ; set ga $SNAP(HALT_POST,live,$::D5_VICTIM)
    puts "DMILOG HALT-WINDOW DIAGNOSTIC (not a grader) -- SG-Cb's window HALT_PRE -> HALT_POST spans the halt REQUEST: victim live $gb -> $ga (delta [expr {$ga - $gb}]), and SG-Ca requires HALT_PRE to read RUNNING ([expr {$SNAP(HALT_PRE,halted,$::D5_VICTIM)}] = halted flag), so the retires in that window are the debugger's transport cost, not a chip property"
}
if {[info exists SNAP(HALT_CONF,live,$::D5_VICTIM)] && [info exists SNAP(HALT_FRZ,live,$::D5_VICTIM)]} {
    set cb $SNAP(HALT_CONF,live,$::D5_VICTIM) ; set ca $SNAP(HALT_FRZ,live,$::D5_VICTIM)
    puts "DMILOG HALT-WINDOW DIAGNOSTIC (not a grader) -- across a CONFIRMED-HALTED window with live JTAG traffic in it, hart $::D5_VICTIM's counter went $cb -> $ca (frozen=[expr {$cb == $ca}]), halted flag [expr {$SNAP(HALT_CONF,halted,$::D5_VICTIM)}] -> [expr {$SNAP(HALT_FRZ,halted,$::D5_VICTIM)}].  This is the clause SG-Cb is reaching for, measured on a window the debugger can actually deliver"
}

# ---------------------------------------------------------------------------
# THE Z0 CENSUS.  A software breakpoint is a MEMORY WRITE, and a tile's TCM is
# PRIVATE -- so "the Z0 landed in the wrong hart's TCM" and "the Z0 never
# landed anywhere" are two different findings that reading one hart cannot
# tell apart.  SG-G1 reads the victim only, by design.  This prints the word
# at the breakpoint site in EVERY hart's TCM at grading time, so a failing
# SG-G1 arrives with its own localisation attached.
# ---------------------------------------------------------------------------
if {$::D5_BPADDR != 0} {
    # Formatting is done OUTSIDE any expr on purpose -- see the note in
    # dbg_rbb_bridge.tcl's TCM verb: expr re-parses a formatted hex string as a
    # number and prints it back in decimal, measured in this file's own first
    # run (0x5D500313 came out as 1565524755).
    set cen {}
    for {set h 0} {$h < $::D5_NHARTS} {incr h} {
        set w [sess_tcm_word $h $::D5_BPADDR]
        if {$w eq ""} { set t "(absent)" } else { set t [format 0x%08X $w] }
        lappend cen "h$h=$t"
    }
    puts "DMILOG Z0 CENSUS (not a grader) -- word at [format 0x%05X $::D5_BPADDR] in every hart's own TCM at grading time: [join $cen {  }]  (ebreak = [format 0x%08X $::D5_EBREAK]; original = [format 0x%08X $::D5_BPWORD])"
}
flush stdout

sess_grade_sticky "end of a real OpenOCD/gdb session"
sess_oracle_dump $::D5_VICTIM [list 0x10050 0x10054 0x10058 0x1005C 0x10060 0x10064]

foreach h [list 1 2 3] { puts "DMILOG   hart$h state=[d2_state $h]" }
sess_grade_summary "dbg_sessrun" 15
flush stdout
exit
