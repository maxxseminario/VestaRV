# =============================================================================
# dbg_tramp_lib.tcl -- the D4 acceptance library: expected-page arithmetic, the
# DM-VISIBILITY readback, the page census, and the NO-FORCE GUARD.
#
# SOURCED by every D4 harness AFTER dbg_bfm.tcl.  It is not a harness itself.
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN 2026-08-07) sections 1,
# 2, 3, 6 by an agent that has not seen and will never see the D4 implementation.
# Committed polarity (R-K5-8): CORRECT RTL = PASS.  Every check below is
# written so that a chip whose Debug Module plants the trampoline passes it and
# the tree at 286921d -- which plants nothing -- fails it for a NAMED reason.
#
# -----------------------------------------------------------------------------
# THE NO-FORCE GUARD, and why it is code rather than a promise
#
#   d4_spec 3 and 6 both require legs in which the harness plants NOTHING: the
#   whole point of D4 is that the DM plants the page itself, and a set in which
#   every harness still forces cannot distinguish a working plant from a broken
#   one (d4_probe P7).  "I did not call dbg_plant_trampoline" is exactly the
#   kind of claim that rots -- one copied line from dbg_abs.tcl and the leg is
#   silently worthless while still reporting PASS.
#
#   So the proc is RENAMED out of the way and replaced by a FAILING stub.  A
#   D4 harness that plants by force fails its own run and says so.  The real
#   proc survives as `d4_force_plant_control` and is reachable ONLY through
#   d4_control_plant, ONLY when D4_CONTROL=1 is in the environment, and it
#   prints a banner naming itself as a liveness-control arm rather than a
#   graded leg.
#
# -----------------------------------------------------------------------------
# THE TWO OBSERVATION CHANNELS, and which one grades
#
#   1. DM VISIBILITY (d4_dm_readback) -- the graded channel for the plant
#      detector, per d4_spec 6 ("never through tcl peeks alone").  The DM is
#      made to drive a HALTED victim through progbuf `lw` of each of the 40
#      entry-page words and the value is read back over DMI as a GPR.  Every
#      byte of that path is the design's own: the DM's master engine planted
#      it, the hart's own load read it, the DMI returned it.
#
#   2. THE PAGE CENSUS (d4_page_census) -- a tcl peek of the 40 RAM cells.
#      CORROBORATING, never sole.  It exists because it can tell three
#      failures apart that the DM channel reports identically: page never
#      written (all zero), page written by somebody else (poison intact), page
#      written wrong (some words match, some do not).
#
#   3. IN-BAND (the image's own scan; see dbgtrpmp.S) -- a THIRD channel that
#      needs no halted hart at all, so it is the only one that can observe the
#      dmactive-rise plant WITHOUT a halt confounding it with the on-halt
#      plant.  It is a running hart executing loads through mp_arbiter.
#
# -----------------------------------------------------------------------------
# BUDGETS.  d2_spec's dm_wait_notbusy defaults to 400 rounds of 2 us = 800 us.
# The DM's OWN bound on an unpublished FLAGS token is POLL_LIMIT = 65535 mclk
# = 2.73 ms at 24 MHz (debug_module.vhd, measured), so the D2 default expires
# BEFORE the subject does and would report a harness timeout where the design
# has a defined, quotable answer (cmderr = OTHER = 7).  That is the SS9a class
# -- a budget that expires before the subject exists.  Every wait in this file
# uses D4_BUSY_BUDGET, sized to outlast the DM's own bound.
# =============================================================================

# ---------------------------------------------------------------------------
# the no-force guard
# ---------------------------------------------------------------------------
if {[llength [info procs dbg_plant_trampoline]] == 1 &&
    [llength [info procs d4_force_plant_control]] == 0} {
    rename dbg_plant_trampoline d4_force_plant_control
}
proc dbg_plant_trampoline {args} {
    puts "DMILOG D4_FORCE_PLANT_ATTEMPTED -- a D4 harness tried to plant the"
    puts "DMILOG   trampoline by tcl force.  Every D4 leg is a NO-FORCE leg by"
    puts "DMILOG   construction (d4_spec 3/6); a forced page proves nothing"
    puts "DMILOG   about a Debug Module that is supposed to plant it itself."
    puts "DMILOG   This is a HARNESS defect, and it fails the run."
    incr ::D2_FAILS
    incr ::D2_CHECKS
    flush stdout
    return 0
}

# The liveness-control arm.  D2/D3 precedent: an instrument that has only ever
# been seen to FAIL has not been shown to be capable of passing.  The forced
# plant is a faithful stand-in for a correct DM plant -- identical content, at
# identical addresses -- so a leg that passes under it and fails without it has
# demonstrated both directions.
proc d4_control_plant {} {
    if {![info exists ::env(D4_CONTROL)] || $::env(D4_CONTROL) ne "1"} { return 0 }
    puts "DMILOG ============================================================"
    puts "DMILOG D4 LIVENESS CONTROL ARM (D4_CONTROL=1) -- NOT A GRADED LEG."
    puts "DMILOG   The trampoline is being planted by tcl FORCE, standing in"
    puts "DMILOG   for the DM plant this instrument exists to detect.  A PASS"
    puts "DMILOG   here proves the instrument CAN pass; it says nothing about"
    puts "DMILOG   the RTL.  The graded arm runs with D4_CONTROL unset."
    puts "DMILOG ============================================================"
    flush stdout
    return [d4_force_plant_control]
}

# Release the control-arm plant again.  A forced word is read-only, so a leg
# that has to CORRUPT the page in band (dbg_trprep, dbg_trpheal) cannot do it
# under a live force -- the store would be silently dropped and the leg would
# grade a corruption that never happened.  The control arm therefore plants,
# releases, lets the corruption land, and re-plants at the point where the RTL
# trigger under test would have fired.  Each of those is a hand-simulation of
# one RTL step; the arm proves the CHECKS are satisfiable and nothing else.
proc d4_control_unplant {} {
    if {![info exists ::env(D4_CONTROL)] || $::env(D4_CONTROL) ne "1"} { return 0 }
    for {set n 0} {$n < $::D4_TRAMP_WORDS} {incr n} {
        sh_release [expr {$::DBG_ENTRY_ADDR + 4*$n}]
    }
    puts "DMILOG D4 CONTROL: the forced plant is RELEASED (the page is writable again)"
    flush stdout
    return 1
}

# ---------------------------------------------------------------------------
# the expected page
# ---------------------------------------------------------------------------
set ::D4_WORDS_PATH "$::env(HOME)/vestarv/software/dbg_trampoline/bin/dbg_trampoline.words"
set ::D4_TRAMP_WORDS 40
set ::D4_BUSY_BUDGET 2000            ;# 2000 * 2 us = 4 ms > the DM's 2.73 ms
set ::D4_POISON 0x5EAD0000
set ::D4_TAIL_ADDR 0x10864           ;# entry-page words 57..63, the unused tail
set ::D4_TAIL_WORDS 7
set ::D4_TAILMARK 0x5A170057

# Read the built .words deliverable.  A line of exactly 32 '0'/'1' characters
# is a planted word; anything else means "left writable" (the dbg_bfm.tcl
# contract, unchanged -- D4 does not move the deliverable's format).
# REFUSES on any count other than 40: the whole D4 mechanism is coupled to that
# number (debug_module.vhd's W_ABST = W_ENTRY + 40), so a silent 39 or 41 would
# grade a different chip.
proc d4_load_words {} {
    if {![file exists $::D4_WORDS_PATH]} {
        puts "DMILOG D4_WORDS_ABSENT path=$::D4_WORDS_PATH"
        puts "DMILOG   The built trampoline is the CONTENT ORACLE for every D4"
        puts "DMILOG   readback.  Without it nothing below can be graded."
        flush stdout
        return {}
    }
    set f [open $::D4_WORDS_PATH r]
    set lines [split [read $f] "\n"]
    close $f
    set out {}
    foreach ln $lines {
        set ln [string trim $ln]
        if {[regexp {^[01]{32}$} $ln]} { lappend out [expr {"0b$ln"}] }
    }
    if {[llength $out] != $::D4_TRAMP_WORDS} {
        puts "DMILOG D4_WORDS_COUNT_WRONG got=[llength $out] want=$::D4_TRAMP_WORDS"
        puts "DMILOG   REFUSING to grade against a deliverable of the wrong"
        puts "DMILOG   length -- W_ABST = W_ENTRY + 40 is coupled to it."
        flush stdout
        return {}
    }
    return $out
}

# The rolling hash the IN-BAND scan computes (dbgtrpmp.S, a_scan).  Rotate-left
# by one then xor, so position matters: a page that holds the right 40 words in
# the wrong order hashes differently.  Defined here and there and NOWHERE else;
# the two definitions are three lines each and are meant to be read side by side.
proc d4_hash {words} {
    set h 0
    foreach w $words {
        set h [expr {((($h << 1) & 0xFFFFFFFE) | (($h >> 31) & 1)) ^ ($w & 0xFFFFFFFF)}]
    }
    return $h
}

# ---------------------------------------------------------------------------
# channel 2: the page census (peek).  CORROBORATING, never sole.
# Returns a dict-ish list: nmatch nzero npoison firstbad gotbad wantbad
# ---------------------------------------------------------------------------
proc d4_page_census {want} {
    set nmatch 0 ; set nzero 0 ; set npoison 0
    set firstbad -1 ; set gotbad -1 ; set wantbad -1
    for {set n 0} {$n < $::D4_TRAMP_WORDS} {incr n} {
        set a [expr {$::DBG_ENTRY_ADDR + 4*$n}]
        set v [sh_get $a]
        set e [lindex $want $n]
        if {$v == 0} { incr nzero }
        if {$v == $::D4_POISON} { incr npoison }
        if {$e ne "" && $v == $e} {
            incr nmatch
        } elseif {$firstbad < 0} {
            set firstbad $n ; set gotbad $v ; set wantbad $e
        }
    }
    return [list $nmatch $nzero $npoison $firstbad $gotbad $wantbad]
}

proc d4_report_census {tag c} {
    foreach {nmatch nzero npoison firstbad gotbad wantbad} $c { break }
    set msg "DMILOG $tag CENSUS(peek) match=$nmatch/$::D4_TRAMP_WORDS zero=$nzero poison=$npoison"
    if {$firstbad >= 0} {
        append msg " firstbad=word$firstbad got=[format 0x%08X $gotbad]"
        if {$wantbad ne "" && $wantbad >= 0} { append msg " want=[format 0x%08X $wantbad]" }
    }
    puts $msg
    flush stdout
}

# ---------------------------------------------------------------------------
# channel 1: the DM-VISIBILITY readback.  THE GRADED CHANNEL.
#
# Mechanism (the dbg_abs.tcl A7 idiom, extended into a walk):
#   a6 (x16) <- 0x10780, written by an abstract GPR write
#   progbuf0 = lw   a7, 0(a6)        0x00082883
#   progbuf1 = addi a6, a6, 4        0x00480813
#   ...then, per word: one POSTEXEC command (transfer=0) followed by an
#   abstract GPR read of a7.  The address advances in the hart's own register,
#   so the walk is structurally determined and nothing is calibrated.
#   progbufsize is 2 and the sequence needs a third word to return, so a
#   working walk is also `impebreak` working.
#
# STOPS AT THE FIRST FAILING COMMAND, deliberately.  On an unplanted page every
# abstract command burns the DM's full 65535-mclk FLAGS wait (2.73 ms) before
# answering cmderr = OTHER; forty of those is 109 ms and would trip the tb's
# own 100 ms watchdog, turning a clean, named, positive failure into a
# watchdog abort.  One timeout is the evidence; the other thirty-nine are cost.
#
# Returns: {ok nread values firstbad cmderr}
#   ok=1  all 40 words read back and every one matched
#   ok=0  see cmderr (>=0: the DM answered and said so; -1: the harness's own
#         budget expired first, which is a HARNESS finding, reported as one)
# ---------------------------------------------------------------------------
set ::D4_PB_LW   0x00082883
set ::D4_PB_ADDI 0x00480813
set ::D4_R_A6    0x1010
set ::D4_R_A7    0x1011

proc d4_wait_notbusy {} { return [dm_wait_notbusy $::D4_BUSY_BUDGET] }

proc d4_abs_read {regno} {
    dmi_write $::DM_COMMAND [ac_cmd $regno 0 1 0]
    set acs [d4_wait_notbusy]
    if {$acs < 0} { return [list -2 -1] }
    set e [acs_cmderr $acs]
    if {$e != 0} { return [list -1 $e] }
    return [list [dmi_read $::DM_DATA0] 0]
}

proc d4_abs_write {regno val} {
    dmi_write $::DM_DATA0 $val
    dmi_write $::DM_COMMAND [ac_cmd $regno 1 1 0]
    set acs [d4_wait_notbusy]
    if {$acs < 0} { return -2 }
    return [acs_cmderr $acs]
}

# Wait out any residual busy and clear a stale cmderr before an abstract
# phase.  Without it a leg that follows a DROPPED resume (which is what an
# unplanted page does to every resume) reports cmderr = BUSY (1) instead of the
# DM's real answer -- measured 2026-08-07 at HEAD in dbg_trpheal H5 and
# dbg_trpsess S9.  Both are failures either way, but a FAIL leg is only useful
# if it names the right cause.
proc d4_settle {} {
    d4_wait_notbusy
    ac_clear_cmderr
}

proc d4_dm_readback {want {base -1}} {
    if {$base < 0} { set base $::DBG_ENTRY_ADDR }
    d4_settle
    set e [d4_abs_write $::D4_R_A6 $base]
    if {$e != 0} {
        puts "DMILOG D4_READBACK_SETUP_FAILED: abstract write of a6 returned cmderr=$e"
        puts "DMILOG   The victim cannot even be given the address to read, so the"
        puts "DMILOG   entry page is not executing the DM's abstract sequence."
        flush stdout
        return [list 0 0 {} -1 $e]
    }
    dmi_write $::DM_PROGBUF0 $::D4_PB_LW
    dmi_write $::DM_PROGBUF1 $::D4_PB_ADDI

    set vals {} ; set firstbad -1
    for {set n 0} {$n < $::D4_TRAMP_WORDS} {incr n} {
        dmi_write $::DM_COMMAND [ac_cmd 0 0 0 1]        ;# transfer=0 postexec=1
        set acs [d4_wait_notbusy]
        if {$acs < 0} {
            puts "DMILOG D4_READBACK_HARNESS_BUDGET word=$n -- abstractcs.busy never"
            puts "DMILOG   cleared inside $::D4_BUSY_BUDGET rounds (4 ms > the DM's own"
            puts "DMILOG   2.73 ms bound).  That is a HARNESS/RTL finding, not a verdict."
            flush stdout
            return [list 0 $n $vals $n -1]
        }
        set e [acs_cmderr $acs]
        if {$e != 0} {
            puts "DMILOG D4_READBACK_CMDERR word=$n cmderr=$e ([d4_cmderr_name $e])"
            flush stdout
            return [list 0 $n $vals $n $e]
        }
        set r [d4_abs_read $::D4_R_A7]
        set v [lindex $r 0]
        if {$v < 0} {
            puts "DMILOG D4_READBACK_GPRERR word=$n cmderr=[lindex $r 1]"
            flush stdout
            return [list 0 $n $vals $n [lindex $r 1]]
        }
        lappend vals $v
        if {$firstbad < 0 && $v != [lindex $want $n]} { set firstbad $n }
    }
    return [list [expr {$firstbad < 0}] $::D4_TRAMP_WORDS $vals $firstbad 0]
}

proc d4_cmderr_name {e} {
    switch -- $e {
        0 { return NONE } 1 { return BUSY } 2 { return NOT_SUPPORTED }
        3 { return EXCEPTION } 4 { return HALT_RESUME } 5 { return BUS }
        7 { return OTHER }
        default { return "?$e" }
    }
}

# The one-line verdict a leg quotes.  Deliberately names the DIAGNOSIS, not
# just the count, because at unimplemented HEAD the three failures are
# different findings and a bare "0/40" would hide which one happened.
proc d4_readback_report {tag r want} {
    foreach {ok nread vals firstbad cmderr} $r { break }
    if {$ok} {
        puts "DMILOG $tag READBACK(DM) 40/40 words match the built deliverable"
        flush stdout
        return
    }
    set msg "DMILOG $tag READBACK(DM) FAILED nread=$nread"
    if {$cmderr == 7} {
        append msg " -- the DM's own FLAGS wait timed out (cmderr=OTHER)."
        append msg "  The victim is halted but never published TOK_HALTED, which is"
        append msg " exactly what a hart fetching from an UNPLANTED entry page does:"
        append msg " it takes an illegal-instruction exception on the first word and"
        append msg " re-enters at DEBUG_ENTRY_ADDR forever, retiring nothing."
    } elseif {$cmderr == 3} {
        append msg " -- cmderr=EXCEPTION: the page executed and FAULTED (planted-but-wrong,"
        append msg " not unplanted)."
    } elseif {$firstbad >= 0 && $nread > $firstbad} {
        append msg " firstbad=word$firstbad got=[format 0x%08X [lindex $vals $firstbad]]"
        append msg " want=[format 0x%08X [lindex $want $firstbad]]"
    }
    puts $msg
    flush stdout
}

# ---------------------------------------------------------------------------
# channel 3: the in-band scan.  Drives dbgtrpmp.S's agent hart through the
# SEQ/ACK handshake.  NO hart need be halted, so this is the only channel that
# can observe the dmactive-rise plant unconfounded by the on-halt plant.
# ---------------------------------------------------------------------------
set ::DBGTRP_PHASE 0x10050
set ::DBGTRP_READY 0x10054
set ::DBGTRP_CMD   0x10058
set ::DBGTRP_ARG   0x1005C
set ::DBGTRP_SEQ   0x10060
set ::DBGTRP_ACK   0x10064
set ::DBGTRP_CHK   0x10068
set ::DBGTRP_W0    0x1006C
set ::DBGTRP_W39   0x10070
set ::DBGTRP_RAN   0x10074
set ::DBGTRP_REL   0x10078
set ::DBGTRP_DIAG  0x1007C

set ::DBGTRP_CMD_POISON  1
set ::DBGTRP_CMD_SCAN    2
set ::DBGTRP_CMD_CORRUPT 3

set ::D4_SEQ 0
# Issue one in-band command and wait for the agent hart to echo the sequence
# number.  An ORDERING (the echo), never a delay.  Bounded; a missing echo is
# reported as an IMAGE finding and never as a DM verdict.
proc d4_cmd {cmd {arg 0} {budget 300}} {
    incr ::D4_SEQ
    sh_force $::DBGTRP_ARG $arg
    sh_force $::DBGTRP_CMD $cmd
    sh_force $::DBGTRP_SEQ $::D4_SEQ
    for {set i 0} {$i < $budget} {incr i} {
        run 50 us
        if {[sh_get $::DBGTRP_ACK] == $::D4_SEQ} { return 1 }
    }
    puts "DMILOG D4_CMD_NO_ACK cmd=$cmd arg=$arg seq=$::D4_SEQ ack=[sh_get $::DBGTRP_ACK]"
    puts "DMILOG   The image's agent hart never acknowledged.  That is an IMAGE"
    puts "DMILOG   finding (a hart that stopped running), not a statement about"
    puts "DMILOG   the Debug Module."
    flush stdout
    return 0
}

# One in-band scan -> {ok chk w0 w39}
proc d4_inband_scan {} {
    if {![d4_cmd $::DBGTRP_CMD_SCAN]} { return [list 0 -1 -1 -1] }
    return [list 1 [sh_get $::DBGTRP_CHK] [sh_get $::DBGTRP_W0] [sh_get $::DBGTRP_W39]]
}

proc d4_wait_ready {{budget 400}} {
    for {set i 0} {$i < $budget} {incr i} {
        run 200 us
        if {[sh_get $::DBGTRP_READY] == 1} {
            puts "DMILOG image READY after i=$i (RAN=[sh_get $::DBGTRP_RAN] DIAG=[format 0x%08X [sh_get $::DBGTRP_DIAG]])"
            flush stdout
            return 1
        }
    }
    puts "DMILOG IMAGE_NEVER_READY -- a test-side finding, not a DM finding."
    flush stdout
    return 0
}

# The unused tail of the entry page (words 57..63).  d4_spec 1 says the plant
# touches words 0..39 ONLY; the image marks the tail before anything else runs,
# and it must still be there afterwards.  A plant that walks past 39 is caught
# here and by nothing else -- the DM legitimately rewrites 40..56 at every
# abstract command, so the tail is the only part of the upper page whose
# content is a stable assertion.
proc d4_tail_intact {} {
    for {set n 0} {$n < $::D4_TAIL_WORDS} {incr n} {
        set v [sh_get [expr {$::D4_TAIL_ADDR + 4*$n}]]
        if {$v != $::D4_TAILMARK} { return [list 0 $n [format 0x%08X $v]] }
    }
    return [list 1 -1 "(all $::D4_TAIL_WORDS intact)"]
}

# dmactive down, then up.  dm_dmcontrol always ORs bit 0 in, so the down-write
# is spelled raw on purpose.
proc d4_dmactive_off {} { dmi_write $::DM_DMCONTROL 0x00000000 }
proc d4_dmactive_on  {{h 0}} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h] }

puts "DMILOG D4LIB loaded (fmt=d4-lib-1; words=$::D4_WORDS_PATH)"
flush stdout
