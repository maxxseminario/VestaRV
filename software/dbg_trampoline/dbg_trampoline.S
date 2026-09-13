# VestaRV: debug entry trampoline
# 40 words at DEBUG_ENTRY_ADDR = 0x00010780, the head of the 64-word shared debug entry page. A halted hart executes them in debug mode, fetching from the shared window through mp_arbiter, so `.option norvc` is mandatory: compressed or misaligned execution from shared memory is untested.
# The page cannot be read-only memory: 24 of its 64 words are written by the Debug Module at runtime. The DM plants these 40 itself from the constant table TRAMP in hdl/common/debug_module.vhd, once when dmactive rises and again before it consumes a newly-halted hart's TOK_HALTED, which is what makes a damaged page self-repairing.
# REGISTER CONTRACT: a halted hart's architectural state belongs to the debugger, so dscratch0 and dscratch1 are the SINGLE HOME of {s0, s1} for the whole halt. The DM's abstract body may use the pair freely with no save of its own, an abstract read of s0 or s1 is serviced out of the dscratch copy, and the epilogue restores the pair before its terminating ebreak. A program-buffer program's s0/s1 results are ADOPTED into dscratch when it returns, so the pair can change within one halted session and an abstract read after a postexec command returns what the program buffer computed.
# BUILD: make -C software/dbg_trampoline. Output bin/dbg_trampoline.words, one line per 32-bit word from 0x10780 ascending: 32 '0'/'1' characters means plant this word, any other line means LEAVE THIS WORD WRITABLE, because the DM writes the abstract body and the epilogue there.
# AFTER ANY CHANGE: copy the new words into debug_module.vhd's TRAMP table and prove `python3 tools/cosim/check_dbg_trampoline.py` exits 0. Changing the LENGTH moves both the `jal x0, _start + 160` below and the DM's W_ABST = W_ENTRY + TRAMP_WORDS, so the two must move together.

    .option norvc
    .option push
    .option arch, +zicsr

    .equ  O_FLAGS,   0x700          # FLAGS[h] = 0x10000 + 4h + 0x700
    .equ  O_MIRROR0, 0x6F0          # 0x106F0, addressed from a clean 0x10000
    .equ  O_MIRROR1, 0x6F4          # 0x106F4
# THE HANDSHAKE. FLAGS[h] at 0x10700 + 4h is the one word the DM and the hart share,
# single-writer-per-state: the hart writes 1 = HALTED ("parked and listening") and
# 12 = DONE ("the sequence reached its epilogue") or 8 = PBDONE ("a program-buffer
# sequence finished"); the DM writes 4 = GO ("run the abstract body") and 2 = RESUME
# ("dret"). The values are implementer latitude and no instrument encodes them. They are
# chosen so that REPAIR THE PAIR FROM THE MIRROR is exactly "FLAGS has bit 2 set": GO (an
# exception before the epilogue) and DONE both set it, so both discard whatever s0/s1 the
# re-entering code left; a first entry finds 0 or RESUME, and neither does. PBDONE is
# bit-2-clear ON PURPOSE, because a program-buffer return must ADOPT the debugger's s0/s1,
# which is what letting the tentative save at words 0..1 stand already does. Read the
# `andi` below as "should I DISCARD s0/s1?", not as "is this a re-entry?".
#
# SHARED WORDS THIS FILE OWNS, inside the 0x10690-0x106FC band reserved for DM use:
#     0x106F0  MIRROR0   the session's saved s0, written at each dispatch
#     0x106F4  MIRROR1   the session's saved s1
# The DM writes the pair in exactly one other place, an abstract WRITE to s0 or s1, where
# it is itself the author of the new dscratch value; without that the mirror captured at
# dispatch would revert the debugger's register write on the next re-entry repair. Both
# are below 0x10800, inside the bootrom's zero range, and a mirror is only read on the
# re-entry path, which is only reachable after a dispatch has written it.
# KNOWN LIMIT: at halt-on-reset the bootrom has not yet zeroed the shared window, so
# FLAGS[h] is whatever the RAM holds and may send this code down either path. The DM
# cannot close it, since FLAGS[h] is a data word it deliberately does not initialise.
# SECOND KNOWN LIMIT: hart_tile holds a shared access's ack while the address and lane
# strobes are unchanged, so a hart that halts into a page whose FIRST word is corrupt
# re-enters, asks for that same word, and spins on the stale value however often the DM
# re-plants. Corruption of any later word is self-healing; of word 0 it is not, and the
# only recovery is a tile reset.
    .equ  TOK_HALTED, 1
    .equ  TOK_RESUME, 2
    .equ  TOK_GO,     4
    .equ  REENTRY_BIT, 4            # set in GO(4) and DONE(12), clear in 0/2

    .section .text
    .globl _start
_start:
# 0..1  save the scratch pair (TENTATIVE: repaired below on a re-entry)
    csrw  0x7b2, s0            # dscratch0 <- s0
    csrw  0x7b3, s1            # dscratch1 <- s1

# 2..5  s0 = 0x10000 + 4*mhartid, the FLAGS[] row base.
# lui gives 0x10000, so every DM word below 0x10800 is reachable with a 12-bit unsigned
# load/store displacement. That is why the whole claimed band sits under 0x10800.
    csrr  s1, 0xf14            # mhartid
    slli  s1, s1, 2
    lui   s0, 0x10
    add   s0, s0, s1

# 6..8  first entry or re-entry?
    lw    s1, O_FLAGS(s0)
    andi  s1, s1, REENTRY_BIT
    beq   s1, x0, halted       # clear -> FIRST entry; the save above stands

# 9..14  RE-ENTRY: the save above overwrote the session's pair; undo it
    lui   s1, 0x10
    lw    s1, O_MIRROR0(s1)
    csrw  0x7b2, s1
    lui   s1, 0x10
    lw    s1, O_MIRROR1(s1)
    csrw  0x7b3, s1

# 15..16  report HALTED
halted:
    addi  s1, x0, TOK_HALTED
    sw    s1, O_FLAGS(s0)

# 17..25  the dispatch poll. A halted hart polling a shared word is a master on the same
# round-robin arbiter as every running hart, so the poll is backed off: 64 iterations of a
# register decrement between shared reads costs the bus almost nothing and still reacts
# within a couple of microseconds.
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

# 26..31  GO: mirror the session pair, then run the DM's abstract body.
# The mirror is what makes an exception inside the body survivable: it is written HERE,
# while dscratch0/1 still hold the debugger's registers, and read back by the re-entry
# path above. s0 is dead from this point; the body builds its own base.
dbg_go:
    lui   s1, 0x10
    csrr  s0, 0x7b2
    sw    s0, O_MIRROR0(s1)
    csrr  s0, 0x7b3
    sw    s0, O_MIRROR1(s1)
    jal   x0, _start + 160     # 0x10780 + 40*4 = 0x10820, the abstract body

# 32..34  RESUME: restore the pair and leave debug mode
dbg_resume:
    csrr  s1, 0x7b3            # dscratch1 -> s1
    csrr  s0, 0x7b2            # dscratch0 -> s0
    .4byte 0x7b200073          # dret

# 35..39  pad: the trampoline occupies words 0..39
    nop
    nop
    nop
    nop
    nop
    .option pop

# PLANT CONSISTENCY. This file is one of two spellings of these 40 words; the other is the
# constant table TRAMP in hdl/common/debug_module.vhd, which is what the DM streams into
# the page. This file is the original and the VHDL is the copy, so the two are checked by
# tools/cosim/check_dbg_trampoline.py: rc 0 they agree, rc 1 they differ (naming the word
# index and both values), rc 2 an input is missing or unparseable, never a silent skip.
