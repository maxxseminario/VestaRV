# =============================================================================
# dbg_sess_lib.tcl -- THE D5 SESSION GRADERS: what marks an OpenOCD/gdb
# session's chip-side effects as PROVEN.  SOURCED; not a harness itself.
#
# BLIND-AUTHORED 2026-08-10 against d5_spec.md sections 5.2 and 5.4 (FROZEN) by
# an agent that has not seen and will never see the D5 bridge, the .cfg files
# or the implementation.  Committed polarity (R-K5-8): a correct chip driven by
# a correct debugger stack = PASS.
#
# ---------------------------------------------------------------------------
# WHY THE GRADERS ARE SNAPSHOT-AND-ORDER AND NOT "WATCH THE SESSION"
#   In the ruled bridge architecture (R-D5-1(3)) xmsim's own Tcl interpreter
#   IS the transport: while a session runs, the interpreter is inside the
#   bridge's blocking serve loop.  Nothing else in this process can `run`, and
#   an instrument that tried would fight the bridge for simulation time and
#   change what it is measuring.
#
#   So every grader here is PASSIVE and STATELESS: `sess_snap` reads values and
#   advances nothing -- no `run`, no `force`, no `deposit`, no DMI transaction.
#   The implementer calls `sess_snap <label>` at named points around their
#   session (before attach, after attach, before/after each verb) and the
#   grade is an ORDERING BETWEEN SNAPSHOTS.  That is method rule 17 taken
#   seriously: there is not one duration anywhere in this file, and the one
#   wall/sim-time field a snapshot carries is printed for context and is never
#   read by any grader.
#
#   IT ALSO MAKES THE GRADERS DEBUGGER-AGNOSTIC.  Nothing below knows that
#   OpenOCD exists.  A session driven by gdb, by a raw DMI harness, or by hand
#   is graded identically, which is the only way a grader can be evidence
#   about the CHIP rather than about the debugger.
#
# ---------------------------------------------------------------------------
# THE NO-PERTURBATION GUARANTEE, AND HOW IT IS ENFORCED RATHER THAN PROMISED
#   `sess_snap` routes every read through `sess_peek`, which is `value` and
#   nothing else.  Sourcing dbg_tramp_lib.tcl brings the D4 NO-FORCE GUARD with
#   it: `dbg_plant_trampoline` is already renamed out of the way and replaced
#   by a stub that FAILS the run.  A D5 harness that plants the page by force
#   therefore cannot grade an attach by accident.
#
# ---------------------------------------------------------------------------
# THE IMAGE CONTRACT (the acceptance author owns this; the image is the
# implementer's).  Section 5.1 authorises a dbgtrpmp sibling.  Two profiles:
#
#   D5_PROFILE=dbgtrpmp  (the default, and it works TODAY with the existing
#                         rv32ua-p-dbgtrpmp image)
#       LIVE(1) = 0x10074   (dbgtrpmp's SH_RAN, hart 1's own loop counter)
#       no LIVE for harts 0 or 2 -> every grader that needs them says
#       NOT-GRADED and never says PASS.
#
#   D5_PROFILE=d5sess    (the sibling image, if the implementer builds one)
#       0x10050 PHASE   0x10054 READY   0x10058 LIVE0  0x1005C LIVE1
#       0x10060 LIVE2   0x10064 MEMW    0x10068 SEED   0x1006C SPARE
#       0x10070 DIAG    0x10074 (LEFT FREE -- dbgtrpmp's RAN, so the two
#                                images can share this band unambiguously)
#       0x10078 REL     0x1007C MARK  (= 0xD5000001, the image identity magic)
#
#   LEDGER: both layouts live ENTIRELY inside the D-series debug acceptance
#   band 0x10050-0x1007C, which CLAUDE.md already claims for exactly this
#   reuse-with-different-meanings under the one-image-per-sim rule.  NO NEW
#   SHARED-WORD CLAIM IS OWED by anything in this file.  If the implementer
#   needs a word outside it, that is a new ledger row in the same change.
#
#   LIVE counters must be MONOTONIC and never reset by the image, because
#   every progress grader below is "strictly greater than", which is immune to
#   sampling instants and to wrap-free counting; a counter the image resets
#   would make a correct chip fail.
#
# ---------------------------------------------------------------------------
# WHAT A GRADER MAY REPORT.  Three outcomes, never two:
#     PASS       the ordering held
#     FAIL       the ordering did not hold, and the report names the values
#     NOT-GRADED a witness this grader needs does not exist in this run
#                (missing probe, missing image word, missing snapshot).
#                NOT-GRADED is counted separately and is NEVER a pass -- the
#                R-D3-4(5) minimum-check lesson, one level up.
# =============================================================================

# dbg_bfm.tcl FIRST and explicitly.  MEASURED DEFECT, first run of this file
# 2026-08-10: dbg_tramp_lib.tcl does NOT source dbg_bfm.tcl -- every D4 harness
# sources both, in that order, and the library quietly inherits `sh_get`,
# `d2_chk`, `d2_int` from its caller.  Sourcing only dbg_tramp_lib.tcl gave
# `invalid command name "sh_get"` inside sess_probe_report, and because
# Xcelium's tcl continues to the next TOP-LEVEL command after an error, the
# run then walked through every remaining grader printing almost nothing --
# a harness failure that reads, at a glance, like a chip with no observables.
if {[llength [info procs sh_get]] == 0} {
    if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
}
if {[llength [info procs d4_page_census]] == 0} {
    if {[file exists dbg_tramp_lib.tcl]} {
        source dbg_tramp_lib.tcl
    } else {
        source ../behavioral_mp/dbg_tramp_lib.tcl
    }
}

set ::D5_NG 0                      ;# NOT-GRADED count, kept apart from D2_FAILS
set ::D5_PROFILE [expr {[info exists ::env(D5_PROFILE)] ? $::env(D5_PROFILE) : "dbgtrpmp"}]
set ::D5_NHARTS  [expr {[info exists ::env(D2_NHARTS)] ? $::env(D2_NHARTS) : 4}]

# The cookies a gdb session writes.  They are ARBITRARY and DELIBERATELY
# unlikely: every cookie grader asserts the value was ABSENT before the write
# and PRESENT after, so a cookie that happened to be lying around already
# cannot make a grader pass.
set ::D5_GPR_COOKIE 0xD5C0FFEE     ;# gdb: set $a5 = 0xd5c0ffee   (x15)
set ::D5_CSR_COOKIE 0xD5C5C0DE     ;# gdb: set $mscratch = 0xd5c5c0de
set ::D5_MEM_COOKIE 0xD5EE7A11     ;# gdb: set *(unsigned*)MEMW = 0xd5ee7a11
set ::D5_GPR_INDEX  15             ;# a5
set ::D5_EBREAK     0x00100073     ;# the 32-bit ebreak gdb's Z0 plants
set ::D5_CEBREAK    0x9002         ;# c.ebreak, if the site is compressed

# ---------------------------------------------------------------------------
# probe layer.  Every hierarchical name in the D5 instrument set is declared
# HERE and nowhere else, so `sess_probe_report` is a complete inventory and a
# renamed signal produces one NOT-GRADED cluster instead of silent zeros.
# ---------------------------------------------------------------------------
proc sess_p_halted  {h} { return ":dut:hart${h}:dbg_halted" }
proc sess_p_state   {h} { return ":dut:hart${h}:core:current_state" }
proc sess_p_pc      {h} { return ":dut:hart${h}:core:pc" }
proc sess_p_dpc     {h} { return ":dut:hart${h}:core:csr_unit_inst:dpc_r" }
proc sess_p_mscr    {h} { return ":dut:hart${h}:core:csr_unit_inst:mscratch" }
proc sess_p_gpr     {h i} { return ":dut:hart${h}:core:datapath_inst:rf:registers($i)" }
proc sess_p_tcm     {h w} { return ":dut:hart${h}:ram0:RAM:mem($w)" }
proc sess_p_msip    {}  { return ":dut:clint0:msip_reg" }
proc sess_p_unavail {}  { return ":dut:dbg_unavail" }

# `value`, and nothing but `value`.  Returns "" when the name does not resolve.
proc sess_peek {path} {
    if {[catch {value $path} v]} { return "" }
    return $v
}
proc sess_peek_int {path} {
    set v [sess_peek $path]
    if {$v eq ""} { return "" }
    set i [d2_int $v]
    if {$i < 0} { return "" }
    return $i
}
proc sess_peek_bit {path} {
    set v [sess_peek $path]
    if {$v eq ""} { return "" }
    return [expr {[string match {*1*} $v] ? 1 : 0}]
}
# A TCM word.  hart_tile's RAM0 covers 0x8000-0xBFFF; the macro word index is
# (addr-0x8000)/4.  Refuses out of range rather than aliasing.
proc sess_tcm_word {h addr} {
    if {$addr < 0x8000 || $addr > 0xBFFC} { return "" }
    return [sess_peek_int [sess_p_tcm $h [expr {($addr - 0x8000) >> 2}]]]
}

# ---------------------------------------------------------------------------
# the image word map
# ---------------------------------------------------------------------------
proc sess_live_addr {h} {
    switch -- $::D5_PROFILE {
        d5sess {
            switch -- $h { 0 { return 0x10058 } 1 { return 0x1005C } 2 { return 0x10060 } }
            return ""
        }
        default {
            if {$h == 1} { return 0x10074 }   ;# dbgtrpmp SH_RAN
            return ""
        }
    }
}
proc sess_memw_addr {} { return [expr {$::D5_PROFILE eq "d5sess" ? 0x10064 : ""}] }
proc sess_seed_addr {} { return [expr {$::D5_PROFILE eq "d5sess" ? 0x10068 : ""}] }
proc sess_flags_addr {h} { return [expr {0x10700 + 4*$h}] }

# ---------------------------------------------------------------------------
# sess_probe_report -- run ONCE, before grading.  Prints which probes resolve.
# An expected-zero needs independent proof the instrument was live (rule 5);
# this is that proof for the whole file, and it is printed whether or not
# anything later fails.
# ---------------------------------------------------------------------------
proc sess_probe_report {} {
    set n $::D5_NHARTS
    puts "DMILOG ---- D5 SESSION PROBE INVENTORY (profile=$::D5_PROFILE NHARTS=$n) ----"
    set dead 0
    foreach {label path} [list \
        "hart0.halted"  [sess_p_halted 0] \
        "hart0.state"   [sess_p_state 0] \
        "hart0.pc"      [sess_p_pc 0] \
        "hart0.dpc"     [sess_p_dpc 0] \
        "hart0.mscratch" [sess_p_mscr 0] \
        "hart0.x15"     [sess_p_gpr 0 15] \
        "hart1.halted"  [sess_p_halted 1] \
        "clint.msip"    [sess_p_msip] \
        "dbg_unavail"   [sess_p_unavail]] {
        set v [sess_peek $path]
        if {$v eq ""} { incr dead ; puts "DMILOG   ABSENT  $label  ($path)" } \
                      else        { puts "DMILOG   present $label  = $v" }
    }
    set w [d4_load_words]
    if {[llength $w]} {
        puts "DMILOG   trampoline oracle: [llength $w] words, hash=[format 0x%08X [d4_hash $w]]"
    } else {
        puts "DMILOG   trampoline oracle: ABSENT -- SG-A cannot be graded"
    }
    foreach h [list 0 1 2] {
        set a [sess_live_addr $h]
        if {$a eq ""} {
            puts "DMILOG   LIVE($h): none in profile $::D5_PROFILE -- graders needing it will say NOT-GRADED"
        } else {
            puts "DMILOG   LIVE($h) @ [format 0x%05X $a] = [sh_get $a]"
        }
    }
    puts "DMILOG   dead probes: $dead"
    flush stdout
    return $dead
}

# ---------------------------------------------------------------------------
# sess_snap -- ONE passive snapshot.  Advances nothing.
# ---------------------------------------------------------------------------
proc sess_snap {label} {
    global SNAP
    set n $::D5_NHARTS
    set SNAP($label,time)  [sess_snap_time]
    for {set h 0} {$h < $n} {incr h} {
        set SNAP($label,halted,$h)  [sess_peek_bit [sess_p_halted $h]]
        set SNAP($label,state,$h)   [string map {\" ""} [sess_peek [sess_p_state $h]]]
        set SNAP($label,pc,$h)      [sess_peek_int [sess_p_pc $h]]
        set SNAP($label,dpc,$h)     [sess_peek_int [sess_p_dpc $h]]
        set SNAP($label,flags,$h)   [sh_get [sess_flags_addr $h]]
        set a [sess_live_addr $h]
        set SNAP($label,live,$h)    [expr {$a eq "" ? "" : [sh_get $a]}]
    }
    set SNAP($label,gpr)   [sess_peek_int [sess_p_gpr 0 $::D5_GPR_INDEX]]
    set SNAP($label,mscr)  [sess_peek_int [sess_p_mscr 0]]
    set SNAP($label,msip)  [sess_peek [sess_p_msip]]
    set SNAP($label,unav)  [sess_peek [sess_p_unavail]]
    set ma [sess_memw_addr]
    set SNAP($label,memw)  [expr {$ma eq "" ? "" : [sh_get $ma]}]
    set want [d4_load_words]
    if {[llength $want]} {
        set c [d4_page_census $want]
        set SNAP($label,page)  [lindex $c 0]
        set SNAP($label,pzero) [lindex $c 1]
        set SNAP($label,pbad)  [lindex $c 3]
    } else {
        set SNAP($label,page) "" ; set SNAP($label,pzero) "" ; set SNAP($label,pbad) ""
    }
    puts "DMILOG SNAP $label t=$SNAP($label,time) page=$SNAP($label,page)/40 halted=[sess_fmt_vec $label halted] live=[sess_fmt_vec $label live] flags=[sess_fmt_vec $label flags]"
    flush stdout
}
proc sess_snap_time {} {
    # Context only.  NO grader reads this field.  If the simulator refuses the
    # query the snapshot is still perfectly valid, which is the point.
    if {[catch {set t [time {}]}]} { set t "?" }
    if {[catch {set t [value :dut:resetn]}]} { set t "?" }
    return "-"
}
proc sess_fmt_vec {label key} {
    global SNAP
    set out {}
    for {set h 0} {$h < $::D5_NHARTS} {incr h} {
        if {[info exists SNAP($label,$key,$h)]} { lappend out $SNAP($label,$key,$h) }
    }
    return [join $out ,]
}

# ---------------------------------------------------------------------------
# grading primitives
# ---------------------------------------------------------------------------
proc sess_ng {tag why} {
    incr ::D5_NG
    puts "DMILOG GRADE NOT-GRADED $tag -- $why"
    puts "DMILOG   NOT-GRADED is not a pass.  It is counted separately and the"
    puts "DMILOG   summary refuses to say ALL GRADERS PASSED while any exist."
    flush stdout
    return 0
}
proc sess_grade {tag cond msg} {
    d2_chk $cond "GRADE $tag: $msg"
    return $cond
}
proc sess_have {args} {
    foreach v $args { if {$v eq "" || $v < 0} { return 0 } }
    return 1
}

# ===========================================================================
# SG-A  ATTACH.  d5_spec 5.2 "read the IDCODE / the hart list" -- the chip-side
#       half.  The witness is the ENTRY PAGE: since D4 the DM plants 40 words
#       out of its own constant table at every dmactive 0->1, so a page that
#       goes from unplanted to equal-to-the-built-deliverable across the attach
#       window is a latched, passive, port-free proof that a debugger set
#       dmactive.  Nothing else on this chip writes those words.
#
#       ORDERING, not a duration: page(before) < 40 AND page(after) == 40.
#       The "before" clause is load-bearing -- without it the grader would pass
#       on a run where the page was already planted by something else.
# ===========================================================================
proc sess_grade_attach {before after} {
    global SNAP
    if {$SNAP($before,page) eq "" || $SNAP($after,page) eq ""} {
        return [sess_ng "SG-A" "no trampoline oracle -- software/dbg_trampoline/bin/dbg_trampoline.words is the content oracle and it is absent"]
    }
    sess_grade "SG-A" [expr {$SNAP($before,page) < 40 && $SNAP($after,page) == 40}] \
      "ATTACH -- the entry page went from UNPLANTED to the built 40-word deliverable across the attach window ($SNAP($before,page)/40 -> $SNAP($after,page)/40).  Since D4 only the DM's own dmactive-rise plant writes those words, so this is a chip-side witness that a debugger attached, and it needs no probe inside the DM"
}

# ===========================================================================
# SG-B  HART CENSUS.  "the hart list (4 and 18 threads, distinct mhartid)" is a
#       DEBUGGER-side observable and is graded by reading gdb's own output --
#       see sess_oracle_dump, which prints the chip-side truth to diff against.
#       What the CHIP can prove is stronger and is what this grader asserts:
#       every hart the session HALTED published its own TOK_HALTED into
#       FLAGS[h].  Only the planted trampoline stores that word, and it stores
#       it per hart, so a nonzero FLAGS[h] is per-hart proof that hart h halted
#       AND executed real planted code -- the D4 N3 discriminator, once per
#       hart, for free.
#
#       N=18 FIRST-CLASS: the grader takes the list of harts the session was
#       supposed to touch, so an 18-hart session is graded over 18 rows.
# ===========================================================================
proc sess_grade_hartcensus {after harts} {
    global SNAP
    set silent {}
    foreach h $harts {
        if {![info exists SNAP($after,flags,$h)]} { lappend silent "h$h:nosnap" ; continue }
        if {$SNAP($after,flags,$h) <= 0} { lappend silent "h$h:[expr {$SNAP($after,flags,$h)}]" }
    }
    sess_grade "SG-B" [expr {[llength $silent] == 0}] \
      "HART CENSUS -- every hart the session halted published TOK_HALTED in its own FLAGS\[h\] word ([llength $harts] harts asked, [llength $silent] silent: {$silent}).  A silent hart either was never halted or halted into a page it could not execute -- the F-D4-1 signature"
}

# ===========================================================================
# SG-C  HALT ONE WHILE THE OTHERS RUN.  THE HEADLINE ORDERING of d5_spec 5.2,
#       and it is written exactly as the spec words it: the others' liveness
#       counters ADVANCE ACROSS THE HALT WINDOW.
#
#       Two clauses, graded together but reported apart:
#         (a) victim: halted(before)=0 -> halted(after)=1 AND its LIVE counter
#             is UNCHANGED between the two snapshots.  Not "small", unchanged.
#         (b) each other launched hart: LIVE strictly GREATER.
#
#       CLAUSE (b) IS ALSO THIS FILE'S KNOWN-NONZERO CONTROL (method rule 4),
#       and that is not a coincidence -- it is why the grader is built this
#       way.  In the debugger-less FAIL leg clause (b) PASSES (the harts are
#       running, so their counters move) while clause (a) FAILS (nothing ever
#       halted).  So the FAIL leg simultaneously demonstrates the grader can
#       fail and demonstrates that the counter probe is live and moving.  A
#       grader whose every clause fails in its FAIL leg has proved only that
#       the instrument noticed the chip was idle.
# ===========================================================================
#       THE `pre` SNAPSHOT IS NOT OPTIONAL AND IT IS NOT COSMETIC.  Measured
#       defect, first FAIL-leg run of dbg_sessgrade 2026-08-10: with only two
#       snapshots, "the victim's counter is UNCHANGED across the halt window"
#       was GREEN on a run where the victim had never been launched at all --
#       a counter frozen at 0 satisfies "unchanged" perfectly.  A zero-retire
#       clause needs proof the subject was retiring something first, so SG-Cb
#       is now an ORDERING OVER THREE SNAPSHOTS: advanced(pre->before), then
#       unchanged(before->after).  Same shape as the D4 T5 baseline lesson,
#       one step further out.
proc sess_grade_halt_one {pre before after victim others} {
    global SNAP
    set vb $SNAP($before,halted,$victim) ; set va $SNAP($after,halted,$victim)
    set lp $SNAP($pre,live,$victim)
    set lb $SNAP($before,live,$victim)   ; set la $SNAP($after,live,$victim)
    if {$vb eq "" || $va eq ""} { return [sess_ng "SG-C" "hart $victim halted probe absent"] }
    sess_grade "SG-Ca" [expr {$vb == 0 && $va == 1}] \
      "HALT ONE (victim) -- hart $victim was RUNNING and is now HALTED (halted $vb -> $va)"
    if {$lb eq "" || $la eq "" || $lp eq ""} {
        sess_ng "SG-Cb" "hart $victim has no LIVE counter in profile $::D5_PROFILE -- the zero-retire half of the halt cannot be graded from the chip side"
    } else {
        sess_grade "SG-Cb" [expr {$lb > $lp && $la == $lb}] \
          "HALT ONE (victim retired nothing) -- hart $victim's own liveness counter was ADVANCING before the halt ($lp -> $lb) and is UNCHANGED across the halt window ($lb -> $la).  The first half is load-bearing: without it a hart that was never launched passes this clause with a counter frozen at zero"
    }
    set frozen {} ; set moved {} ; set ungraded {}
    foreach h $others {
        set a $SNAP($before,live,$h) ; set b $SNAP($after,live,$h)
        if {$a eq "" || $b eq ""} { lappend ungraded $h ; continue }
        if {$b > $a} { lappend moved "h$h:$a->$b" } else { lappend frozen "h$h:$a->$b" }
    }
    if {[llength $moved] == 0 && [llength $frozen] == 0} {
        sess_ng "SG-Cc" "no other hart has a LIVE counter in profile $::D5_PROFILE -- the 'others keep running' clause, which is the whole point of the check, cannot be graded.  Build the d5sess sibling image or accept this clause as uncovered"
    } else {
        sess_grade "SG-Cc" [expr {[llength $frozen] == 0}] \
          "HALT ONE (others keep running) -- every other launched hart's liveness counter STRICTLY ADVANCED across hart $victim's halt window (moved: {$moved}; frozen: {$frozen}; ungraded: {$ungraded}).  This is an ORDERING between two counter reads and contains no duration -- and it is also the known-nonzero that proves the counter probe is live"
    }
}

# ===========================================================================
# SG-D  GPR WRITE and SG-E CSR WRITE.  A cookie must be ABSENT before and
#       PRESENT after.  Absence-before is what stops a stale value passing.
# ===========================================================================
proc sess_grade_gpr_write {before after victim} {
    global SNAP
    set b [sess_peek_int [sess_p_gpr $victim $::D5_GPR_INDEX]]
    if {![info exists SNAP($before,gpr)] || $b eq ""} { return [sess_ng "SG-D" "regfile probe absent on hart $victim"] }
    sess_grade "SG-D" [expr {$SNAP($before,gpr) != $::D5_GPR_COOKIE && $b == $::D5_GPR_COOKIE}] \
      "GPR WRITE -- x$::D5_GPR_INDEX on hart $victim did NOT hold the session cookie before the write and DOES hold it after ([format 0x%08X $SNAP($before,gpr)] -> [format 0x%08X $b], cookie [format 0x%08X $::D5_GPR_COOKIE]).  The absence-before clause is what stops a stale word passing this"
}
proc sess_grade_csr_write {before after victim} {
    global SNAP
    set b [sess_peek_int [sess_p_mscr $victim]]
    if {![info exists SNAP($before,mscr)] || $b eq ""} { return [sess_ng "SG-E" "mscratch probe absent on hart $victim"] }
    sess_grade "SG-E" [expr {$SNAP($before,mscr) != $::D5_CSR_COOKIE && $b == $::D5_CSR_COOKIE}] \
      "CSR WRITE -- mscratch on hart $victim went from [format 0x%08X $SNAP($before,mscr)] to [format 0x%08X $b] (cookie [format 0x%08X $::D5_CSR_COOKIE]).  mscratch is chosen because the image never touches it, so the debugger is the only possible author"
}

# ===========================================================================
# SG-F  MEMORY WRITE THROUGH PROGBUF.  The image pre-seeds MEMW with a
#       known-nonzero SEED and never touches it again; gdb writes the cookie.
#       Graded as seed-before AND cookie-after: two nonzero values, so neither
#       "it was already zero" nor "everything is zero" can pass.
# ===========================================================================
proc sess_grade_mem_write {before after} {
    global SNAP
    set ma [sess_memw_addr] ; set sa [sess_seed_addr]
    if {$ma eq ""} { return [sess_ng "SG-F" "profile $::D5_PROFILE has no MEMW word -- memory write/read is a d5sess-image grader"] }
    set b [sh_get $ma] ; set seed [sh_get $sa]
    sess_grade "SG-F" [expr {$seed != 0 && $SNAP($before,memw) == $seed && $b == $::D5_MEM_COOKIE}] \
      "MEMORY WRITE (progbuf) -- the shared word [format 0x%05X $ma] held the image's known-nonzero seed [format 0x%08X $seed] before the write and the session cookie [format 0x%08X $::D5_MEM_COOKIE] after (measured [format 0x%08X $SNAP($before,memw)] -> [format 0x%08X $b])"
}

# ===========================================================================
# SG-G  SOFTWARE BREAKPOINT.  Three clauses, and the third is the one that
#       makes it a BREAKPOINT rather than an asynchronous halt.
#
#       bpaddr and origword are STRUCTURALLY DETERMINED, never calibrated:
#       the caller reads both off `objdump` at a labelled site in the image
#       (method rule 7).  If the caller passes the wrong address the FIRST
#       clause fails loudly -- a wrong address cannot silently cover nothing.
#
#         (1) the word at bpaddr was origword before, and is an ebreak
#             encoding after -- gdb's Z0 really landed, in the tile's own TCM
#         (2) the hart is halted with dpc == bpaddr -- it stopped THERE
#         (3) its liveness counter ADVANCED between the resume snapshot and
#             the hit snapshot -- it RAN into the breakpoint.  Without (3) a
#             chip that simply re-asserted haltreq would satisfy (2).
# ===========================================================================
proc sess_grade_swbp {prevword resumed hit victim bpaddr origword} {
    global SNAP
    set wa [sess_tcm_word $victim $bpaddr]
    if {$wa eq ""} { return [sess_ng "SG-G" "TCM probe absent or bpaddr [format 0x%X $bpaddr] outside 0x8000-0xBFFC"] }
    set isbrk [expr {($wa == $::D5_EBREAK) || (($wa & 0xFFFF) == $::D5_CEBREAK)}]
    set rightsite [expr {$prevword ne "" && $origword ne "" && $prevword == $origword}]
    sess_grade "SG-G1" [expr {$rightsite && $isbrk}] \
      "SW BREAKPOINT (Z0 landed, at the RIGHT site) -- before the session the word at [format 0x%05X $bpaddr] in hart $victim's TCM read [format 0x%08X [expr {$prevword eq {} ? -1 : $prevword}]] and the objdump-derived original is [format 0x%08X [expr {$origword eq {} ? -1 : $origword}]] (match=$rightsite); it now reads [format 0x%08X $wa], an ebreak encoding (is_ebreak=$isbrk).  The match clause is what makes a WRONG bpaddr fail loudly instead of silently covering nothing (method rule 7)"
    set dp $SNAP($hit,dpc,$victim)
    sess_grade "SG-G2" [expr {$SNAP($hit,halted,$victim) == 1 && $dp eq "" ? 0 : ($SNAP($hit,halted,$victim) == 1 && $dp == $bpaddr)}] \
      "SW BREAKPOINT (hit) -- hart $victim is halted with dpc == the breakpoint address (dpc [format 0x%08X [expr {$dp eq {} ? -1 : $dp}]] vs [format 0x%08X $bpaddr])"
    set lr $SNAP($resumed,live,$victim) ; set lh $SNAP($hit,live,$victim)
    if {$lr eq "" || $lh eq ""} {
        sess_ng "SG-G3" "hart $victim has no LIVE counter in profile $::D5_PROFILE -- 'it ran into the breakpoint' cannot be separated from 'it was halted again'"
    } else {
        # `halted at the hit` is a PRECONDITION, not decoration.  Measured
        # defect, dbg_sessgrade FAIL leg 2026-08-10: without it, "the counter
        # advanced between two snapshots" is green on any running hart, so
        # this clause passed on a chip where no breakpoint and no halt had
        # ever happened.  Same class as SG-Cb and SG-I2; the liveness control
        # found all three, and the graded direction alone would have shipped
        # all three.
        sess_grade "SG-G3" [expr {$SNAP($hit,halted,$victim) == 1 && $lh > $lr}] \
          "SW BREAKPOINT (it RAN there) -- hart $victim is HALTED at the hit and its liveness counter advanced between the resume and the hit ($lr -> $lh).  This is the clause that separates a breakpoint from a second haltreq, and it is an ordering"
    }
}

# ===========================================================================
# SG-H  STEPI.  Graded against the STRUCTURALLY NEXT address, which the caller
#       reads off objdump.  "dpc changed" would also pass on a chip that took
#       an exception; "dpc == next" cannot.
# ===========================================================================
proc sess_grade_step {before after victim nextaddr} {
    global SNAP
    set b $SNAP($before,dpc,$victim) ; set a $SNAP($after,dpc,$victim)
    if {![sess_have $b $a]} { return [sess_ng "SG-H" "dpc probe absent on hart $victim"] }
    sess_grade "SG-H" [expr {$SNAP($after,halted,$victim) == 1 && $b != $a && $a == $nextaddr}] \
      "STEPI -- hart $victim is still halted and dpc advanced from [format 0x%08X $b] to [format 0x%08X $a], which is the objdump-derived NEXT instruction address [format 0x%08X $nextaddr].  Equality with a structurally determined successor is what makes this 'exactly one instruction' without counting anything"
}

# ===========================================================================
# SG-I  RESUME.  Two clauses; the counter clause is what separates "reports
#       running" from "is running".
# ===========================================================================
proc sess_grade_resume {before after victim} {
    global SNAP
    sess_grade "SG-I1" [expr {$SNAP($before,halted,$victim) == 1 && $SNAP($after,halted,$victim) == 0}] \
      "RESUME (state) -- hart $victim went HALTED -> RUNNING (halted $SNAP($before,halted,$victim) -> $SNAP($after,halted,$victim))"
    set b $SNAP($before,live,$victim) ; set a $SNAP($after,live,$victim)
    if {$b eq "" || $a eq ""} {
        sess_ng "SG-I2" "hart $victim has no LIVE counter in profile $::D5_PROFILE"
    } else {
        # Same precondition, same reason (see SG-G3): a hart that was never
        # halted advances its counter for free.
        sess_grade "SG-I2" [expr {$SNAP($before,halted,$victim) == 1 && $a > $b}] \
          "RESUME (it really runs) -- hart $victim was HALTED at the `before` snapshot and its liveness counter advanced after the resume ($b -> $a).  dmstatus.running is a state; a wedged hart reads running too, and a hart that was never stopped advances for free"
    }
}

# ===========================================================================
# SG-J  HALT-ON-RESET VIA THE PER-TILE PWRCTRL PATH, driven gdb-side (5.2 /
#       5.4-1 / C53).  The D4 N1/N2 shape, kept:
#         (1) the tile really was gated: dbg_unavail bit h was 0, then 1
#         (2) after release the hart reads HALTED
#         (3) ZERO RETIRES -- its liveness counter is unchanged across the
#             whole power-cycle window
#         (4) pc INSIDE the entry page, as an ORDERING WITH (3) and NOT as an
#             equality with DEBUG_ENTRY_ADDR.  D4 measured exactly why: on an
#             UNPLANTED page pc reads 0x00010780 exactly, and on a correct
#             chip the trampoline RUNS and pc is further in.  The equality
#             form passes on the broken chip and fails on the good one.
# ===========================================================================
proc sess_grade_reset_halt {before gated after victim} {
    global SNAP
    set ug $SNAP($gated,unav) ; set ub $SNAP($before,unav)
    if {$ug eq "" || $ub eq ""} {
        sess_ng "SG-J1" "dbg_unavail probe absent -- 'the tile was really gated' cannot be graded"
    } else {
        set gb [string index [string map {\" ""} $ug] end-$victim]
        set bb [string index [string map {\" ""} $ub] end-$victim]
        sess_grade "SG-J1" [expr {$bb eq "0" && $gb eq "1"}] \
          "RESET-HALT (the gate happened) -- dbg_unavail bit $victim went $bb -> $gb across the gdb-driven PWRCR write"
    }
    sess_grade "SG-J2" [expr {$SNAP($after,halted,$victim) == 1}] \
      "RESET-HALT (caught at release) -- hart $victim reads HALTED after the power-up, which is the held setresethaltreq catching it"
    set b $SNAP($before,live,$victim) ; set a $SNAP($after,live,$victim)
    if {$b eq "" || $a eq ""} {
        sess_ng "SG-J3" "hart $victim has no LIVE counter in profile $::D5_PROFILE -- the ZERO-RETIRE clause is the point of this grader and it cannot be graded"
    } else {
        sess_grade "SG-J3" [expr {$a == $b}] \
          "RESET-HALT (zero retires) -- hart $victim's liveness counter is unchanged across the whole power-cycle window ($b -> $a): it halted before executing anything of its own"
    }
    set pc $SNAP($after,pc,$victim)
    if {![sess_have $pc]} {
        sess_ng "SG-J4" "pc probe absent on hart $victim"
    } else {
        sess_grade "SG-J4" [expr {$pc >= 0x10780 && $pc <= 0x1087F}] \
          "RESET-HALT (pc reached the entry page) -- hart $victim's pc is [format 0x%08X $pc], INSIDE 0x10780-0x1087F.  Deliberately an interval and not an equality: D4 measured pc == 0x00010780 exactly on an UNPLANTED page, so the equality form passes on the broken chip and fails on the correct one"
    }
}

# ===========================================================================
# SG-K  THE R-D2-12 msip WEDGE: walk-in and procedural rescue (5.4-3).
#       Two signatures, defined here so the implementer measures rather than
#       argues.  The bound is expressed in SNAPSHOTS -- i.e. in the session's
#       own observed progress -- and never in seconds.
#
#       WEDGE  : after the resume the hart is in TRAP_STATE, its liveness
#                counter is frozen across two further snapshots, and it is not
#                halted.  (A cold-gated tile has an EMPTY TCM, so the counter
#                cannot advance from the image; the terminal state is the
#                positive part of the signature and the frozen counter is the
#                corroboration.)
#       RESCUE : msip[h] reads 0 before the resume, and afterwards the hart is
#                NOT in TRAP_STATE and its pc is inside the boot ROM
#                (0x0-0x3FFF) or it has reached the ROM's WFI park -- i.e. it
#                walked into the bootrom instead of into unarmed IVT slot 83.
# ===========================================================================
proc sess_grade_msip_wedge {afterresume later victim} {
    global SNAP
    set st $SNAP($afterresume,state,$victim)
    set l1 $SNAP($afterresume,live,$victim) ; set l2 $SNAP($later,live,$victim)
    set frozen [expr {($l1 eq "" || $l2 eq "") ? "n/a" : ($l1 == $l2)}]
    sess_grade "SG-K1" [expr {[string match "*TRAP_STATE*" $st]}] \
      "msip WEDGE WALK-IN -- hart $victim is in state '$st' after resuming from a reset-halt with msip still pending (want TRAP_STATE: R-D2-12's terminal trap at unarmed IVT slot 83; liveness frozen across the next snapshot = $frozen).  THIS GRADER PASSES WHEN THE WEDGE HAPPENS -- it is the measurement that turns the landmine into a disposition, not a health check"
}
#       BOTH RESCUE CLAUSES CARRY AN EXPLICIT PRECONDITION, for the reason the
#       first FAIL-leg run exposed: on a session-less chip msip is 0 and no
#       hart is in TRAP_STATE, so a naive "msip==0" and a naive "not
#       TRAP_STATE" are BOTH green while nothing whatever has happened.  A
#       rescue grader that passes when there was nothing to rescue is not a
#       grader.  So:
#         K2 is an ORDERING on msip: SET at `pending`, CLEAR at `cleared`.
#         K3 is graded ONLY when the caller states the wedge was reached
#            (`wedged` = the SG-K1 verdict); otherwise NOT-GRADED.
proc sess_grade_msip_rescue {pending cleared after victim wedged} {
    global SNAP
    set mp $SNAP($pending,msip) ; set mc $SNAP($cleared,msip)
    if {$mp eq "" || $mc eq ""} {
        sess_ng "SG-K2" "clint msip probe absent -- the rescue precondition cannot be shown"
    } else {
        set bp [string index [string map {\" ""} $mp] end-$victim]
        set bc [string index [string map {\" ""} $mc] end-$victim]
        sess_grade "SG-K2" [expr {$bp eq "1" && $bc eq "0"}] \
          "msip RESCUE (precondition, as an ORDERING) -- CLINT msip bit $victim was $bp with the interrupt pending and $bc after the gdb-side memory write to 0x[format %04X [expr {0x5000 + 4*$victim}]].  Both halves are required: a chip where msip was never set reads 0 for free.  MSIP is 0x5000+4h at BOTH N; MTIME and MTIMECMP move with NHARTS and must never be hard-coded"
    }
    if {!$wedged} {
        return [sess_ng "SG-K3" "the wedge was never walked into (SG-K1 did not fire), so there is nothing for a rescue to have rescued"]
    }
    set st $SNAP($after,state,$victim)
    set pc $SNAP($after,pc,$victim)
    sess_grade "SG-K3" [expr {![string match "*TRAP_STATE*" $st]}] \
      "msip RESCUE (it worked) -- hart $victim had wedged, and after the rescued resume it is in state '$st', pc [format 0x%08X [expr {$pc eq {} ? -1 : $pc}]].  Not TRAP_STATE = the procedural disposition holds; TRAP_STATE = the procedure does NOT rescue the flow, which d5_spec 5.4-3 makes a STOP"
}

# ===========================================================================
# SG-L  THE F1 / sticky-gate observation (5.4-0).  Passive read of the DTM's
#       own sticky field.  A session that ended with sticky nonzero is a
#       deafened transport whether or not anything else looks fine.
# ===========================================================================
proc sess_grade_sticky {label} {
    set s [sess_peek ":dut:dtm0:sticky"]
    if {$s eq ""} { return [sess_ng "SG-L" "dtm0 sticky probe absent (name may differ; declare it in sess_probe_report before relying on this)"] }
    set v [string map {\" ""} $s]
    sess_grade "SG-L" [expr {$v eq "00"}] \
      "STICKY CLEAR at $label -- the DTM's dmistat reads '$v' (want 00).  Nonzero means every subsequent non-NOP Update-DR of dmi is being silently DROPPED (jtag_dtm.vhd DEVIATION 4) until OpenOCD issues dtmcs.dmireset -- which it does automatically, so a session that ENDS nonzero has a live problem"
}

# ===========================================================================
# sess_oracle_dump -- THE CHIP-SIDE TRUTH, printed for the implementer to diff
# against what gdb printed.  READS are the one family of verbs whose observable
# is on the DEBUGGER side; this is how they stop being graded against a guess.
# ===========================================================================
proc sess_oracle_dump {victim {memaddrs {}}} {
    puts "DMILOG ---- D5 ORACLE (chip-side truth for hart $victim; diff gdb's output against THIS) ----"
    puts "DMILOG   pc      = [format 0x%08X [expr {[set v [sess_peek_int [sess_p_pc $victim]]] eq {} ? -1 : $v}]]"
    puts "DMILOG   dpc     = [format 0x%08X [expr {[set v [sess_peek_int [sess_p_dpc $victim]]] eq {} ? -1 : $v}]]"
    puts "DMILOG   mscratch= [format 0x%08X [expr {[set v [sess_peek_int [sess_p_mscr $victim]]] eq {} ? -1 : $v}]]"
    for {set i 0} {$i < 32} {incr i} {
        set g [sess_peek_int [sess_p_gpr $victim $i]]
        if {$g ne ""} { puts "DMILOG   x$i = [format 0x%08X $g]" }
    }
    foreach a $memaddrs { puts "DMILOG   mem\[[format 0x%05X $a]\] = [format 0x%08X [sh_get $a]]" }
    flush stdout
}

# ===========================================================================
proc sess_grade_summary {tag {min 1}} {
    puts "DMILOG ---- D5 GRADER SUMMARY ($tag) ----"
    puts "DMILOG   graded=$::D2_CHECKS  failed=$::D2_FAILS  NOT-GRADED=$::D5_NG"
    if {$::D5_NG > 0} {
        puts "DMILOG   $::D5_NG grader(s) could not be evaluated in this run.  That is"
        puts "DMILOG   NOT a pass: each named its missing witness above, and each is a"
        puts "DMILOG   clause of d5_spec 5.2/5.4 left uncovered by THIS run."
    }
    d2_summary $tag $min
}
