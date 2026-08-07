# =============================================================================
# dbg_bfm.tcl -- the D2 harness library: a DMI bus-functional model over the
# MCU's frozen d2_spec-2 port, a shared-bulk-RAM window, and the trampoline
# plant.  SOURCED by every D2 tcl harness; it is not a harness itself.
#
# BLIND-AUTHORED 2026-08-05 against d2_spec.md sections 2-4 (FROZEN) by an
# agent that has not seen and will never see the D2 implementation.
#
# ---------------------------------------------------------------------------
# WHY A FORCE-DRIVEN BFM AND NOT A VHDL ONE
#   riscv_tb.vhd declares MCU as a COMPONENT whose port list predates the DMI,
#   so on a D2 chip every dmi_* port of the MCU ENTITY is UNASSOCIATED and sits
#   at the entity default that d2_spec 2 requires ("all inputs defaulted so
#   existing benches/netlists stay legal").  An unassociated formal input is
#   exactly what D1's harnesses forced at :dut:hart1:dbg_haltreq, one level
#   deeper, and that force was proven to reach the logic (d1_acceptance_report
#   section 3; re-run as I4 at D2).  So the debugger in these harnesses is a
#   tcl process driving the same port a D3 DTM will drive -- which is the whole
#   point of designing the port once.
#
# MEASURED SIMULATOR FACTS THIS FILE DEPENDS ON (d2_depositprobe.tcl,
# 2026-08-05 -- measured, not assumed, because none of them was written down):
#   * force/deposit of a VHDL std_logic_vector needs the VHDL string-literal
#     spelling: the argument is `"0101..."` WITH the quote characters, the
#     vector analogue of D1's `force <std_logic> '1'`.  `2#...#` and `32'b...`
#     are refused (*E,PVHSAL / *E,SETNEL).
#   * a DEPOSIT into the shared bulk-RAM model does NOT persist -- one reverted
#     to zeros inside 10 us.  A FORCE held across 11.6 ms including the
#     bootrom's own zeroing of 0x10000-0x107FF, and released cleanly.
#     ** d2_spec 1 says the trampoline is "planted into the RAM model by the TB
#     (tcl deposit)".  Measured, a deposit cannot do it; `force` can, and is
#     also the semantically right verb -- a forced word IS read-only memory,
#     which is what a D4-ROM stand-in is.  Reported to Fable as a mechanism
#     correction. **
#   * end-to-end known-nonzero (d2_methodcheck.tcl): forcing shared 0x10060
#     during rv32ua-p-dbgdenymp's watch loop turned a PASS into the exact
#     predicted FAIL a1=0x0DB6DEB6 a2=0xD0B00003 -- so a forced word really is
#     seen by a running hart's load, through the RAM model and the arbiter.
#
# SHARED-RAM ADDRESS ARITHMETIC (MCU.vhd shbank0..3, 4 x sram1p16k):
#   word_addr = addr(16:2);  bank = word_addr(13:12);  macro word = addr(13:2)
#   0x10000 -> shbank0 word 0 ... 0x13FFC -> shbank0 word 4095, 0x14000 ->
#   shbank1 word 0, and so on.  d2_sh_cell does the arithmetic; check it there.
#
# EVERY LOOP IN THIS FILE IS BOUNDED.  A poll that never satisfies its
# condition must FAIL the run, never hang it (the dma_bfm_pkg rule, and the
# 1-minute rule).  A harness that can hang promises evidence that cannot occur.
# =============================================================================

# ---------------------------------------------------------------------------
# DM register map (DMI word addresses; debug_defines.h, quoted in d2_probe P6)
# ---------------------------------------------------------------------------
set ::DM_DATA0      0x04
set ::DM_DMCONTROL  0x10
set ::DM_DMSTATUS   0x11
set ::DM_HARTINFO   0x12
set ::DM_HALTSUM1   0x13
set ::DM_ABSTRACTCS 0x16
set ::DM_COMMAND    0x17
set ::DM_ABSTRACTAUTO 0x18
set ::DM_PROGBUF0   0x20
set ::DM_PROGBUF1   0x21
set ::DM_DMCS2      0x32
set ::DM_HALTSUM0   0x40

# dmcontrol bit masks a caller may need to HOLD across a dm_poll_status
set ::HALTREQ_BIT   0x80000000
set ::RESUMEREQ_BIT 0x40000000

# DMI request ops (DTM encoding, d2_spec 2) and response ops
set ::DMI_OP_READ   1
set ::DMI_OP_WRITE  2
set ::DMI_RSP_SUCCESS 0
set ::DMI_RSP_FAILED  2
set ::DMI_RSP_BUSY    3

# cmderr enum (d2_spec 3)
set ::CMDERR_NONE 0
set ::CMDERR_BUSY 1
set ::CMDERR_NOTSUP 2
set ::CMDERR_EXCEPTION 3
set ::CMDERR_HALTRESUME 4

# the frozen debug program page (d2_spec 1)
set ::DBG_DATA0_ADDR  0x10680
set ::DBG_FLAGS_BASE  0x10700
set ::DBG_ENTRY_ADDR  0x10780

# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
proc d2_bits {val width} {
    set s ""
    for {set i [expr {$width-1}]} {$i >= 0} {incr i -1} {
        append s [expr {($val >> $i) & 1}]
    }
    return $s
}
proc d2_hex {bits {digits 8}} {
    set b [string map {\" ""} $bits]
    if {![regexp {^[01]+$} $b]} { return $bits }
    return [format "0x%0${digits}X" [expr {"0b$b"}]]
}
proc d2_int {bits} {
    set b [string map {\" ""} $bits]
    if {![regexp {^[01]+$} $b]} { return -1 }
    return [expr {"0b$b"}]
}
proc d2_fld {val hi lo} { return [expr {($val >> $lo) & ((1 << ($hi-$lo+1)) - 1)}] }
proc d2_val {p} { if {[catch {value $p} v]} { return "ERR" } ; return $v }

# ---------------------------------------------------------------------------
# check bookkeeping.  A harness reports CHECK ok / CHECK FAILED lines and the
# runner greps, exactly as dbg_iface_tb does: a bench that stops at the first
# failure can never tell you whether the rest would also have failed.
# ---------------------------------------------------------------------------
set ::D2_FAILS 0
set ::D2_CHECKS 0
proc d2_chk {cond msg} {
    incr ::D2_CHECKS
    if {$cond} {
        puts "DMILOG CHECK ok: $msg"
    } else {
        incr ::D2_FAILS
        puts "DMILOG CHECK FAILED: $msg"
    }
    flush stdout
}
# R6 (R-D3-4(5), fixed at the D3 validation wave): a MINIMUM-CHECK GUARD.
#
# d2_summary reported success whenever the failure count was zero -- and zero
# checks have zero failures.  So any harness in this family, run against a tree
# WITHOUT the DMI port, printed a greppable `ALL CHECKS PASSED (0 checks)`
# while measuring nothing at all.  Found at D3 by the acceptance author's own
# FAIL-leg demonstration (the D3 harnesses grew tap_summary for exactly this),
# and it is live here in tools/cosim/gate/, so it is fixed at the source.
#
# No harness in this set legitimately runs zero checks: a harness that finds
# its port absent reports PORT_ABSENT / INSTRUMENT_DEAD and skips, which is
# precisely the case that must not read as a pass.  `min` defaults to 1 so
# every existing caller is unchanged; a caller that knows its own count may
# pass a stricter floor.
proc d2_summary {tag {min 1}} {
    if {$::D2_CHECKS < $min} {
        puts "DMILOG $tag NO_CHECKS -- only $::D2_CHECKS check(s) executed (minimum $min)."
        puts "DMILOG   This is NOT a pass and must never be greppable as one:"
        puts "DMILOG   zero checks have zero failures.  If the transport was"
        puts "DMILOG   absent the log says so above; if it was present, the"
        puts "DMILOG   harness stopped early and that is a finding."
        flush stdout
        return
    }
    if {$::D2_FAILS == 0} {
        puts "DMILOG $tag ALL CHECKS PASSED ($::D2_CHECKS checks)"
    } else {
        puts "DMILOG $tag FAILURES $::D2_FAILS of $::D2_CHECKS"
    }
    flush stdout
}

# ---------------------------------------------------------------------------
# the DMI port, and the ONE place its existence is decided
# ---------------------------------------------------------------------------
set ::DMI_RQV  ":dut:dmi_req_valid"
set ::DMI_RQOP ":dut:dmi_req_op"
set ::DMI_RQA  ":dut:dmi_req_addr"
set ::DMI_RQD  ":dut:dmi_req_data"
set ::DMI_RQR  ":dut:dmi_req_ready"
set ::DMI_RSV  ":dut:dmi_rsp_valid"
set ::DMI_RSD  ":dut:dmi_rsp_data"
set ::DMI_RSOP ":dut:dmi_rsp_op"

# Present iff EVERY one of the eight frozen names resolves.  Partial presence
# is reported as absence AND named, because a half-implemented port is a
# finding and must not read as "no DM yet".
proc dmi_present {} {
    set missing {}
    foreach p [list $::DMI_RQV $::DMI_RQOP $::DMI_RQA $::DMI_RQD \
                    $::DMI_RQR $::DMI_RSV $::DMI_RSD $::DMI_RSOP] {
        if {[catch {value $p} e]} { lappend missing "$p ($e)" }
    }
    if {[llength $missing] == 0} { return 1 }
    puts "DMILOG PORT_ABSENT count=[llength $missing] of 8"
    foreach m $missing { puts "DMILOG   missing: $m" }
    if {[llength $missing] < 8} {
        puts "DMILOG PARTIAL_PORT -- some dmi_* names resolve and some do not."
        puts "DMILOG   That is a FINDING, not an unimplemented feature."
    }
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no d2_spec-2 DMI port in this build)"
    flush stdout
    return 0
}

# ---------------------------------------------------------------------------
# dmi_xact -- ONE DMI transaction.  Returns {ok rsp_op rsp_data}.
#   ok = 0 means the handshake itself did not complete inside the budget; that
#   is a harness-visible protocol failure and is NEVER silently retried.
# Sampling is 10 ns (mclk is 41.667 ns), so a one-cycle rsp_valid pulse is
# sampled ~4 times and cannot be stepped over -- the D1 dbg_halt.tcl lesson,
# where a 25 us poll walked straight past a 2 us halt window.
# ---------------------------------------------------------------------------
proc dmi_xact {op addr data} {
    set BUDGET 6000                       ;# 60 us ~= 1440 mclk
    catch {force $::DMI_RQA  "\"[d2_bits $addr 7]\""}
    catch {force $::DMI_RQD  "\"[d2_bits $data 32]\""}
    catch {force $::DMI_RQOP "\"[d2_bits $op 2]\""}
    catch {force $::DMI_RQV  '1'}

    set accepted 0
    for {set i 0} {$i < $BUDGET} {incr i} {
        run 10 ns
        if {[string match {*1*} [d2_val $::DMI_RQR]]} { set accepted 1 ; break }
    }
    catch {force $::DMI_RQV  '0'}
    catch {force $::DMI_RQOP "\"00\""}
    if {!$accepted} {
        puts "DMILOG XACT_NO_READY op=$op addr=[format 0x%02X $addr]"
        flush stdout
        return [list 0 -1 -1]
    }

    set rop -1 ; set rdat -1 ; set got 0
    for {set i 0} {$i < $BUDGET} {incr i} {
        run 10 ns
        if {[string match {*1*} [d2_val $::DMI_RSV]]} {
            set rop  [d2_int [d2_val $::DMI_RSOP]]
            set rdat [d2_int [d2_val $::DMI_RSD]]
            set got 1
            break
        }
    }
    if {!$got} {
        puts "DMILOG XACT_NO_RSP op=$op addr=[format 0x%02X $addr]"
        flush stdout
        return [list 0 -1 -1]
    }
    return [list 1 $rop $rdat]
}

# dmi_read/dmi_write: convenience wrappers.  They record the response op in
# ::DMI_ROP so a caller can assert on `failed` / `busy` without a second read.
proc dmi_read {addr} {
    set r [dmi_xact $::DMI_OP_READ $addr 0]
    set ::DMI_OK  [lindex $r 0]
    set ::DMI_ROP [lindex $r 1]
    return [lindex $r 2]
}
proc dmi_write {addr data} {
    set r [dmi_xact $::DMI_OP_WRITE $addr $data]
    set ::DMI_OK  [lindex $r 0]
    set ::DMI_ROP [lindex $r 1]
    return [lindex $r 2]
}

# ---------------------------------------------------------------------------
# dmcontrol helpers.  hartsel lives in hartsello [25:16] (d2_spec 3); hartselhi
# reads zero on both chips.  dmactive is bit 0 and every write keeps it set --
# clearing it resets the DM, which is a deliberate act and never a side effect.
# ---------------------------------------------------------------------------
proc dm_dmcontrol {hartsel {extra 0}} {
    return [expr {($hartsel << 16) | $extra | 1}]
}
proc dm_select {h} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h] }
proc dm_haltreq {h} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h [expr {1 << 31}]] }
proc dm_clr_haltreq {h} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h] }
proc dm_resumereq {h} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h [expr {1 << 30}]] }
# resumereq written WHILE haltreq is still held.  d2_spec 4 as amended by
# R-D2-2(5) DEFINES this on VestaRV: the hart resumes (resumeack sets) and then
# RE-HALTS with no further DMI write.  That ordering is the DMI-visible
# signature of the re-armed wire, and it is the only signature it has.
proc dm_resume_under_held_halt {h} {
    dmi_write $::DM_DMCONTROL [dm_dmcontrol $h [expr {(1 << 31) | (1 << 30)}]]
}
proc dm_setresethaltreq {h} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h [expr {1 << 3}]] }
proc dm_clrresethaltreq {h} { dmi_write $::DM_DMCONTROL [dm_dmcontrol $h [expr {1 << 2}]] }

# dmstatus field accessors (bit positions from debug_defines.h / d2_spec 3)
proc dms_allhalted   {s} { d2_fld $s 9 9 }
proc dms_anyhalted   {s} { d2_fld $s 8 8 }
proc dms_allrunning  {s} { d2_fld $s 11 11 }
proc dms_anyrunning  {s} { d2_fld $s 10 10 }
proc dms_allunavail  {s} { d2_fld $s 13 13 }
proc dms_anyunavail  {s} { d2_fld $s 12 12 }
proc dms_allnonexist {s} { d2_fld $s 15 15 }
proc dms_anynonexist {s} { d2_fld $s 14 14 }
proc dms_allresumeack {s} { d2_fld $s 17 17 }
proc dms_anyresumeack {s} { d2_fld $s 16 16 }
proc dms_version     {s} { d2_fld $s 3 0 }
proc dms_authenticated {s} { d2_fld $s 7 7 }
proc dms_hasresethaltreq {s} { d2_fld $s 5 5 }
proc dms_impebreak   {s} { d2_fld $s 22 22 }

proc acs_busy      {s} { d2_fld $s 12 12 }
proc acs_cmderr    {s} { d2_fld $s 10 8 }
proc acs_progbufsize {s} { d2_fld $s 28 24 }
proc acs_datacount {s} { d2_fld $s 3 0 }

# Poll dmstatus of hart h until PRED (a one-arg proc name) is true.  Bounded.
#
# `hold` IS LOAD-BEARING AND WAS A DEFECT WITHOUT IT (found 2026-08-06 while
# adding the re-arm leg).  Every round re-writes dmcontrol to keep hartsel
# right -- and the first draft wrote it with extra = 0, which CLEARED whatever
# level the caller was holding.  A caller that had just raised haltreq had it
# taken away by its own poll, one DMI transaction later, invisibly.  Callers
# now pass the bits they are HOLDING; the default 0 is correct only for a
# caller holding nothing.
proc dm_poll_status {h pred {budget 400} {hold 0}} {
    for {set i 0} {$i < $budget} {incr i} {
        dmi_write $::DM_DMCONTROL [dm_dmcontrol $h $hold]
        set s [dmi_read $::DM_DMSTATUS]
        if {[$pred $s]} { return $s }
        run 2 us
    }
    return -1
}

# Read-only dmstatus poll: writes NOTHING, so hartsel and every control bit
# stay exactly as the caller last left them.  This is what an assertion of the
# form "and then X happened with no further DMI write" has to use -- see the
# re-arm leg R3 in dbg_dmi.tcl.
proc dm_poll_status_ro {pred {budget 400}} {
    for {set i 0} {$i < $budget} {incr i} {
        set s [dmi_read $::DM_DMSTATUS]
        if {$s >= 0 && [$pred $s]} { return $s }
        run 2 us
    }
    return -1
}
proc dm_wait_notbusy {{budget 400}} {
    for {set i 0} {$i < $budget} {incr i} {
        set s [dmi_read $::DM_ABSTRACTCS]
        if {$s >= 0 && [acs_busy $s] == 0} { return $s }
        run 2 us
    }
    return -1
}

# ---------------------------------------------------------------------------
# abstract access-register command word (d2_spec 3: cmdtype 0, aarsize=2 only)
#   regno: GPRs 0x1000+n, CSRs 0x000-0xFFF
# ---------------------------------------------------------------------------
proc ac_cmd {regno {write 0} {transfer 1} {postexec 0} {aarsize 2}} {
    return [expr {(0 << 24) | ($aarsize << 20) | ($postexec << 18) |
                  ($transfer << 17) | ($write << 16) | ($regno & 0xFFFF)}]
}
# abstract read of one register -> data0.  Returns the value, or -1.
proc ac_read_reg {regno} {
    dmi_write $::DM_COMMAND [ac_cmd $regno 0 1 0]
    if {[dm_wait_notbusy] < 0} { return -1 }
    set acs [dmi_read $::DM_ABSTRACTCS]
    if {[acs_cmderr $acs] != 0} { return -1 }
    return [dmi_read $::DM_DATA0]
}
proc ac_write_reg {regno val} {
    dmi_write $::DM_DATA0 $val
    dmi_write $::DM_COMMAND [ac_cmd $regno 1 1 0]
    if {[dm_wait_notbusy] < 0} { return 0 }
    set acs [dmi_read $::DM_ABSTRACTCS]
    return [expr {[acs_cmderr $acs] == 0}]
}
proc ac_clear_cmderr {} { dmi_write $::DM_ABSTRACTCS [expr {7 << 8}] }

# ---------------------------------------------------------------------------
# the shared bulk-RAM window
# ---------------------------------------------------------------------------
proc d2_sh_cell {addr} {
    if {$addr < 0x10000 || $addr > 0x1FFFF} { return "" }
    set word [expr {($addr - 0x10000) >> 2}]
    set bank [expr {$word >> 12}]
    set idx  [expr {$word & 0xFFF}]
    return ":dut:shbank${bank}:RAM:mem($idx)"
}
proc sh_get {addr} {
    set c [d2_sh_cell $addr]
    if {$c eq ""} { return -1 }
    return [d2_int [d2_val $c]]
}
# sh_force: PIN a shared word.  Measured to hold across the bootrom's own
# zeroing; a deposit does not (see the header).  Used for the trampoline and
# for the harness -> in-band-code channel, never for a word the design writes.
proc sh_force {addr val} {
    set c [d2_sh_cell $addr]
    if {$c eq ""} { return 0 }
    return [expr {![catch {force $c "\"[d2_bits $val 32]\""}]}]
}
proc sh_release {addr} {
    set c [d2_sh_cell $addr]
    if {$c ne ""} { catch {release $c} }
}

# ---------------------------------------------------------------------------
# THE TRAMPOLINE PLANT -- the acceptance-side half of d2_spec 1's "built
# deliverable, planted by the TB".
#
# CONTRACT (this is the part the acceptance author owns and the implementer
# must satisfy; the instruction content is the implementer's):
#   FILE  $VESTA/software/dbg_trampoline/bin/dbg_trampoline.words
#   FORM  one line per 32-bit word, starting at DEBUG_ENTRY_ADDR (0x10780) and
#         ascending.  A line of exactly 32 '0'/'1' characters is a word to
#         plant.  ANY OTHER LINE (blank, '#' comment, or a run of '-') means
#         LEAVE THIS WORD WRITABLE -- that is how the implementer reserves the
#         abstract area and the progbuf backing words, whose contents the DM
#         itself writes and which must NOT be pinned.
#   LIMIT  at most 64 lines (the entry page 0x10780-0x1087F -- ENLARGED from
#         32 words by R-D2-2(3), because dbgstepmp's migrated stub is a
#         measured 60 words and the DM trampoline gains headroom).  A longer
#         file is a FATAL harness error, not a silent truncation.
#         NOTE the 0x10800-0x1087F half is OUTSIDE the bootrom zero range and
#         is CODE-ONLY: every word there must be written by its planter before
#         anything reads it.  Do not put a DM data word there.
#
# NO INSTRUMENT IN THIS SET READS THE TRAMPOLINE'S CONTENT OR DEPENDS ON ITS
# INTERNAL LAYOUT.  The FLAGS[] token protocol is implementer latitude
# (d2_spec 1) and appears nowhere in these harnesses: everything is checked
# through DMI responses and through architectural effects the victim itself
# reports.  This proc plants bytes it does not interpret, on purpose.
# ---------------------------------------------------------------------------
proc dbg_plant_trampoline {{path ""}} {
    if {$path eq ""} {
        set path "$::env(HOME)/vestarv/software/dbg_trampoline/bin/dbg_trampoline.words"
    }
    if {![file exists $path]} {
        puts "DMILOG TRAMPOLINE_ABSENT path=$path"
        puts "DMILOG   d2_spec 1 makes the trampoline a BUILT DELIVERABLE.  Without"
        puts "DMILOG   it a halted hart fetches whatever the shared RAM holds at"
        puts "DMILOG   DEBUG_ENTRY_ADDR, so resume and every abstract command are"
        puts "DMILOG   unreachable.  This is a MISSING-DELIVERABLE report, not a"
        puts "DMILOG   statement about the DM."
        flush stdout
        return 0
    }
    set f [open $path r]
    set lines [split [read $f] "\n"]
    close $f
    set n 0 ; set planted 0
    foreach ln $lines {
        set ln [string trim $ln]
        # Skip EVERY blank line, not just a leading one.  The first draft
        # skipped only a leading blank, so a file's TRAILING newline produced
        # one extra element and tripped the length guard: a trampoline of
        # exactly 64 words reported TOO_LONG and NOTHING was planted.
        # Measured 2026-08-06 against a 64-line deliverable -- an off-by-one
        # in this proc, wrongly attributable to the deliverable if it is not
        # written down.
        if {$ln eq ""} { continue }
        if {[string index $ln 0] eq "#"} { continue }
        if {$n >= 64} {
            puts "DMILOG TRAMPOLINE_TOO_LONG -- more than 64 words; the entry page is"
            puts "DMILOG   0x10780-0x1087F (d2_spec 1 as amended by R-D2-2(3)).  Refusing to plant past it."
            flush stdout
            return 0
        }
        if {[regexp {^[01]{32}$} $ln]} {
            set a [expr {$::DBG_ENTRY_ADDR + 4*$n}]
            set c [d2_sh_cell $a]
            if {[catch {force $c "\"$ln\""} e]} {
                puts "DMILOG TRAMPOLINE_FORCE_REFUSED word=$n err=$e"
                flush stdout
                return 0
            }
            incr planted
        }
        incr n
    }
    puts "DMILOG trampoline planted words=$planted of $n lines from $path"
    flush stdout
    return 1
}

# ---------------------------------------------------------------------------
# the test's own verdict -- a0 through a3 of hart 0, the D1 dbg_verdict shape
# ---------------------------------------------------------------------------
set ::D2_DEAD_Q "\"11011110101011011011111011101111\""
set ::D2_CAFE_Q "\"11001010111111101011101010111110\""
proc d2_run_to_verdict {{chunks 2400} {chunk "25 us"}} {
    set verdict TIMEOUT
    for {set i 0} {$i < $chunks} {incr i} {
        eval run $chunk
        set av [value :a0]
        if {$av eq $::D2_DEAD_Q} { set verdict FAILED; break }
        if {$av eq $::D2_CAFE_Q} { set verdict PASSED; break }
    }
    return $verdict
}
proc d2_report_verdict {tag verdict} {
    set out "DMILOG $tag VERDICT=$verdict"
    foreach {n idx} {a0 10 a1 11 a2 12 a3 13} {
        if {[catch {value :dut:hart0:core:datapath_inst:rf:registers($idx)} v]} {
            set v ERR
        } else { set v [d2_hex $v] }
        append out " $n=$v"
    }
    puts $out
    flush stdout
}
proc d2_state {h} {
    if {[catch {value ":dut:hart${h}:core:current_state"} v]} { return "ERR" }
    return [string map {\" ""} $v]
}
