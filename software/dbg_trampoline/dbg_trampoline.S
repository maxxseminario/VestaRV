# =============================================================================
# dbg_trampoline.S  (D2)
# =============================================================================
# THE DEBUG ENTRY TRAMPOLINE -- the disclosed D4-ROM stand-in.
#
# WHAT IT IS.  d2_spec 1 makes this a BUILT DELIVERABLE that the TESTBENCH
# plants (tcl `force`, R-D2-2(1)) at DEBUG_ENTRY_ADDR = 0x00010780, the first
# 40 words of the 64-word shared debug entry page.  The Debug Module never
# writes it and could not: a forced word is read-only memory, which is exactly
# what a ROM stand-in should be.  At D4 this same code moves into a real
# shared-window debug ROM and the plant disappears; nothing else changes.
#
# WHERE IT RUNS.  On a HALTED hart, in debug mode, fetching from the SHARED
# window through mp_arbiter (execute-from-shared is the M10 shexec proof, and
# `.option norvc` is mandatory -- compressed/misaligned execution from shared
# is UNTESTED, CLAUDE.md's shexec constraint).
#
# THE REGISTER CONTRACT, and it is the whole design.  A halted hart's
# architectural state belongs to the debugger, so the trampoline may not
# clobber it.  It has exactly two places to hide things -- dscratch0 and
# dscratch1 -- so it saves s0/s1 there ONCE PER HALTED SESSION and owns them
# for the whole session.  Everything downstream inherits that:
#   * the DM's synthesized abstract body may use s0 and s1 freely, with no
#     save/restore of its own (Spike's sequence saves s0 per command; ours
#     does not need to);
#   * an abstract read of s0 or s1 THEMSELVES is serviced out of the dscratch
#     copy, so the debugger sees the interrupted value and not the
#     trampoline's working value -- the DM synthesizes that case explicitly;
#   * the epilogue restores the pair before its terminating ebreak, so the
#     NORMAL re-entry re-saves the SAME values and is idempotent.
#
# ONCE PER SESSION, NOT ONCE PER ENTRY -- and that distinction is a MEASURED
# DEFECT FIX, not a refinement (2026-08-06, J3's A10, confirm-before-fix).
#   The first version of this file saved the pair UNCONDITIONALLY at word 0 and
#   argued that re-entry was idempotent because the epilogue restores first.
#   That argument covers the SUCCESSFUL re-entry and is FALSE for the one the
#   F-D2-0 rider created: a synchronous exception inside the abstract body (or
#   inside debugger-supplied program-buffer code) re-enters HERE without ever
#   reaching the epilogue, with s0/s1 holding whatever the faulting code left.
#   Measured on the real DM: after an abstract read of an unimplemented CSR,
#   hart 1's dscratch0/dscratch1 read 0x00010004 / 0x00000000 -- this file's
#   own dispatch values -- instead of the debugger's saved pair, so the very
#   next abstract command returned garbage and the resumed hart came back with
#   s1 destroyed (dbg_abs.tcl A10; dbgabsmp's a1 = 0x0D220007).
#   THE FIX, and why it has this shape.  No scheme that depends on knowing
#   s0/s1 at the fault can work: program-buffer code is the DEBUGGER's and can
#   fault with any register state.  So the saved pair is MIRRORED into two
#   shared words at the moment a command is dispatched (dbg_go, below), and the
#   entry path asks FLAGS[h] whether this is a re-entry and, if it is, puts the
#   mirror back.  ONE mirror pair suffices for any number of harts because the
#   DM runs ONE abstract command at a time -- other halted harts are parked in
#   the poll loop below and never re-enter.
#
# THE HANDSHAKE.  FLAGS[h] at 0x10700 + 4h is the one word the DM and the hart
# share, single-writer-per-state:
#     hart writes  1 = HALTED    "I am parked and listening"
#     DM   writes  4 = GO        "run the abstract body"
#     DM   writes  2 = RESUME    "dret"
#     hart writes 12 = DONE      "the sequence reached its epilogue"
# The token VALUES are implementer latitude (d2_spec 1) and NO instrument
# encodes them -- everything is graded through DMI responses and through
# architectural effects the victim itself reports.  They are chosen so that
#     RE-ENTRY  <=>  FLAGS has bit 2 set
# because the only values FLAGS can hold when the hart re-enters are GO (an
# exception before the epilogue) and DONE (the epilogue's own ebreak), while
# the only values it can hold at a FIRST entry are 0 (the bootrom zeroes
# 0x10000-0x107FF) and RESUME (left by the previous session's resume -- the
# hart cannot leave debug mode by any other route).  One `andi`, no second
# scratch register.
#
# WHY THE POLL IS BACKED OFF.  A halted hart polling a shared word is a master
# on the same round-robin arbiter as every RUNNING hart.  The D2 headline
# instrument halts one hart and requires the others not to stall, so an
# unthrottled poll would be measuring the wrong thing.  64 iterations of a
# register decrement between shared reads costs the bus almost nothing and
# still reacts within a couple of microseconds.
#
# SHARED WORDS THIS FILE OWNS, inside "0x10690-0x106FC reserved for DM use":
#     0x106F0  MIRROR0   the session's saved s0, written at each dispatch
#     0x106F4  MIRROR1   the session's saved s1
# Both are BELOW 0x10800, i.e. inside the bootrom's zero range, so the
# write-before-read contract holds with no initialisation: a mirror is only
# ever READ on the re-entry path, which can only be reached after a dispatch
# has WRITTEN it.
# KNOWN LIMIT, stated rather than left to be found: at HALT-ON-RESET the
# bootrom has not yet zeroed the shared window, so FLAGS[h] is whatever the RAM
# holds.  The behavioural model zero-fills, so it reads 0 = first entry.  On a
# real chip an uninitialised FLAGS[h] could send this code down the repair or
# the dispatch path; that is the same uninitialised-shared-RAM hazard the poll
# loop already had, it is not new here, and D4's real debug ROM (which owns its
# own state) is where it goes away.
#
# BUILD:  make -C software/dbg_trampoline
# OUTPUT: bin/dbg_trampoline.words -- one line per 32-bit word from 0x10780
#         ascending; 32 '0'/'1' chars = plant this word; any other line = LEAVE
#         THIS WORD WRITABLE (the DM writes the abstract body and the epilogue
#         there, and a forced word could not be written).
# =============================================================================

    .option norvc
    .option push
    .option arch, +zicsr

    .equ  O_FLAGS,   0x700          # FLAGS[h] = 0x10000 + 4h + 0x700
    .equ  O_MIRROR0, 0x6F0          # 0x106F0, addressed from a clean 0x10000
    .equ  O_MIRROR1, 0x6F4          # 0x106F4
    .equ  TOK_HALTED, 1
    .equ  TOK_RESUME, 2
    .equ  TOK_GO,     4
    .equ  REENTRY_BIT, 4            # set in GO(4) and DONE(12), clear in 0/2

    .section .text
    .globl _start
_start:
# --- 0..1  save the scratch pair (TENTATIVE: repaired below on a re-entry) ----
    csrw  0x7b2, s0            # dscratch0 <- s0
    csrw  0x7b3, s1            # dscratch1 <- s1

# --- 2..5  s0 = 0x10000 + 4*mhartid  (the FLAGS[] row base) ------------------
# lui gives 0x10000; every DM word below 0x10800 is then reachable with a
# 12-bit unsigned load/store displacement, which is why the whole claimed band
# was placed under 0x10800 in the first place.
    csrr  s1, 0xf14            # mhartid
    slli  s1, s1, 2
    lui   s0, 0x10
    add   s0, s0, s1

# --- 6..8  first entry or re-entry? ------------------------------------------
    lw    s1, O_FLAGS(s0)
    andi  s1, s1, REENTRY_BIT
    beq   s1, x0, halted       # clear -> FIRST entry; the save above stands

# --- 9..14  RE-ENTRY: the save above overwrote the session's pair; undo it ---
    lui   s1, 0x10
    lw    s1, O_MIRROR0(s1)
    csrw  0x7b2, s1
    lui   s1, 0x10
    lw    s1, O_MIRROR1(s1)
    csrw  0x7b3, s1

# --- 15..16  report HALTED ---------------------------------------------------
halted:
    addi  s1, x0, TOK_HALTED
    sw    s1, O_FLAGS(s0)

# --- 17..25  the dispatch poll -----------------------------------------------
poll:
    lw    s1, O_FLAGS(s0)
    addi  s1, s1, -TOK_GO      # == TOK_GO ?
    beq   s1, x0, dbg_go
    addi  s1, s1, TOK_GO-TOK_RESUME
    beq   s1, x0, dbg_resume   # was TOK_RESUME ?
    addi  s1, x0, 64           # backoff
backoff:
    addi  s1, s1, -1
    bne   s1, x0, backoff
    jal   x0, poll

# --- 26..31  GO: mirror the session pair, then run the DM's abstract body ----
# The mirror is what makes an exception inside the body survivable: it is
# written HERE, while dscratch0/1 still hold the debugger's registers, and read
# back by the re-entry path above.  s0 is dead from this point -- the body
# builds its own base.
dbg_go:
    lui   s1, 0x10
    csrr  s0, 0x7b2
    sw    s0, O_MIRROR0(s1)
    csrr  s0, 0x7b3
    sw    s0, O_MIRROR1(s1)
    jal   x0, _start + 160     # 0x10780 + 40*4 = 0x10820, the abstract body

# --- 32..34  RESUME: restore the pair and leave debug mode -------------------
dbg_resume:
    csrr  s1, 0x7b3            # dscratch1 -> s1
    csrr  s0, 0x7b2            # dscratch0 -> s0
    .4byte 0x7b200073          # dret

# --- 35..39  pad: the trampoline occupies words 0..39 ------------------------
    nop
    nop
    nop
    nop
    nop
    .option pop
