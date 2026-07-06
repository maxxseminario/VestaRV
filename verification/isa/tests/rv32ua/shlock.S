# See LICENSE for license details.

#*****************************************************************************
# shlock.S  (M7c — LOCKING: the advisory-lock signature test)
#-----------------------------------------------------------------------------
# ADVISORY SOFTWARE LOCKS for shared-peripheral SESSIONS. Register-level
# atomicity is free (whole-txn arbiter grant); session-level ownership is an
# ADVISORY LOCK WORD in shared RAM taken with the shspin LR/SC pattern
# (hartid-scaled backoff + bounded retry — M4c/M5a rules).
#
# ALL FOUR harts contend for UART1 (0x4500) sessions: each hart commits 4
# sessions, each session = acquire the lock, transmit a 4-byte message with
# the full per-byte UTCIF flag dance, journal every byte in shared RAM at a
# lock-protected global index (JIDX), re-check OWNER, release. The tb has no
# UART receiver, so ATOMICITY IS PROVEN VIA THE JOURNAL: hart 0 requires
# JIDX == 64 and every 4-aligned journal group to be ONE hart's 4 consecutive
# bytes (byte = 0x40 + hartid*16 + i), with per-hart group counts EXACTLY
# 4 each (packed-counter check == 0x04040404). Any interleaved session shears
# a group or collides on JIDX; a broken flag dance trips a bounded poll.
#
# UART1's baud core is smclk-domain => hart 0 writes SYS_CLK_CR=0 FIRST
# (bootrom parks SMCLK on LFXT — M6 rule), configures BR/CR with readbacks,
# then opens the starting gate (GO). No token ring here — the LOCK is the
# only serializer; contention is the point.
#
# Shared words (>= 0x10240, clear of all earlier tests' words):
#     LOCK     = 0x10240          0 free / hartid+1 held (advisory)
#     OWNER    = 0x10244          holder re-checks before release
#     GO       = 0x10248          0x600D10CC after hart 0's UART1 config
#     JIDX     = 0x1024C          journal entry index (must end 64)
#     DONE[h]  = 0x10250 + 4*h    0x10CC0000+h after hart h's 4 sessions
#     JOURNAL  = 0x10280..0x1037F 64 words, one per transmitted byte
# (next free shared word: 0x10380)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SH_UART1   0x4500      /* +0 CR, +4 SR, +8 BR, +16 TX */
#define LOCK       0x10240
#define OWNER      0x10244
#define GO         0x10248
#define JIDX       0x1024C
#define DONE_BASE  0x10250
#define JOURNAL    0x10280
#define GO_MAGIC   0x600D10CC
#define UART_BR    1
#define UART_CR_EN 0x20

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   sp, 0xBFF0             # private TCM top (IRQ_SV contract)

    li   s2, SH_UART1
    li   s3, GO
    li   s4, DONE_BASE
    li   s5, JIDX
    li   s7, LOCK
    li   s8, OWNER
    li   s9, JOURNAL
    addi s11, s10, 1            # my lock/owner marker (nonzero)

    beqz s10, hart0

    # ---- harts 1-3: park until hart 0 has configured UART1 (reads only) ----
go_wait:
    lw   t0, 0(s3)
    li   t1, GO_MAGIC
    bne  t0, t1, go_wait
    j    sessions

    # ---- hart 0: SMCLK sanity + UART1 config, then open the gate -----------
hart0:
    li   t0, 0x4900             # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)            # SMCLK -> HFXT (UART baud core is smclk-domain)
    li   t0, UART_BR
    sw   t0, 8(s2)              # BR=1 with readback
    lw   t1, 8(s2)
    bne  t1, t0, shlock_fail
    li   t0, UART_CR_EN
    sw   t0, 0(s2)              # CR=EN with readback
    lw   t1, 0(s2)
    bne  t1, t0, shlock_fail
    li   t0, GO_MAGIC
    sw   t0, 0(s3)              # GO: all four contend from here

    # ---- every hart: 4 lock-protected UART1 sessions ------------------------
sessions:
    .option push
    .option arch, +a
    li   s6, 4                  # sessions to commit
session_loop:
    li   t6, 16384              # bounded acquire budget: a broken lock FAILS
                                # inside the tb's 100ms watchdog (65536 would
                                # ride past it — M5a budget rule)
acquire:
    lr.w t0, (s7)
    bnez t0, acq_backoff        # held by someone
    sc.w t0, s11, (s7)          # claim: LOCK = hartid+1
    beqz t0, got_lock
acq_backoff:
    addi t6, t6, -1
    beqz t6, shlock_fail
    slli t1, s10, 3             # backoff = hartid*8 + 8 spins (M4c rule)
    addi t1, t1, 8
1:  addi t1, t1, -1
    bnez t1, 1b
    j    acquire
got_lock:
    sw   s11, 0(s8)             # OWNER = me
    lw   s1, 0(s5)              # JIDX (lock-protected — no atomics needed)
    slli t5, s1, 2
    add  t5, t5, s9             # journal write pointer
    li   t4, 0                  # byte index in this session
byte_loop:
    slli t2, s10, 4
    add  t2, t2, t4
    addi t2, t2, 0x40           # byte = 0x40 + hartid*16 + i (nonzero)
    sw   t2, 0(t5)              # journal the byte...
    jal  ra, uart_send          # ...and transmit it (full UTCIF dance)
    addi t5, t5, 4
    addi t4, t4, 1
    li   t3, 4
    bne  t4, t3, byte_loop
    addi s1, s1, 4
    sw   s1, 0(s5)              # JIDX += 4 (still under the lock)
    lw   t3, 0(s8)              # OWNER still me? (direct mutex evidence)
    bne  t3, s11, shlock_fail
    sw   x0, 0(s7)              # release (plain store)
    addi s6, s6, -1
    bnez s6, session_loop
    .option pop

    beqz s10, check_journal

    # ---- harts 1-3: report DONE, inline PASS, verify forever ---------------
    slli t0, s10, 2
    add  t0, t0, s4
    li   t1, 0x10CC0000
    add  t1, t1, s10
    sw   t1, 0(t0)              # DONE[h]
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shlock_fail
    j    tile_verify

    # ---- hart 0: bounded-wait all DONEs, then adjudicate the journal -------
check_journal:
    li   s6, 1
dw_loop:
    slli t0, s6, 2
    add  t1, t0, s4             # DONE[h]
    li   t2, 0x10CC0000
    add  t2, t2, s6
    li   t6, 20000              # bounded (fits the 100ms watchdog)
dw_poll:
    lw   t3, 0(t1)
    beq  t3, t2, dw_ok
    addi t6, t6, -1
    bnez t6, dw_poll
    j    shlock_fail
dw_ok:
    addi s6, s6, 1
    li   t0, 4
    bne  s6, t0, dw_loop

    lw   t0, 0(s5)              # JIDX: 16 sessions * 4 bytes, no collisions
    li   t1, 64
    bne  t0, t1, shlock_fail

    mv   t1, s9                 # group pointer
    addi t0, s9, 256            # end of journal
    li   t5, 0                  # packed per-hart group counters
grp_loop:
    lw   t2, 0(t1)              # first entry of the group
    addi t3, t2, -0x40
    andi t4, t3, 0xF
    bnez t4, shlock_fail        # group must START a session (i == 0)
    srli t4, t3, 4              # owning hart
    sltiu t3, t4, 4
    beqz t3, shlock_fail        # hart in 0..3
    slli t3, t4, 3
    li   t6, 1
    sll  t6, t6, t3
    add  t5, t5, t6             # counts += 1 << (8*hart)
    lw   t3, 4(t1)              # remaining 3 bytes: same hart, consecutive
    addi t6, t2, 1
    bne  t3, t6, shlock_fail
    lw   t3, 8(t1)
    addi t6, t2, 2
    bne  t3, t6, shlock_fail
    lw   t3, 12(t1)
    addi t6, t2, 3
    bne  t3, t6, shlock_fail
    addi t1, t1, 16
    bne  t1, t0, grp_loop
    li   t6, 0x04040404         # every hart committed EXACTLY 4 sessions
    bne  t5, t6, shlock_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shlock_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- uart_send: TX t2 on UART1 + full UTCIF flag dance (shperiph
    # ---- pattern; clobbers t3/t6, preserves t2/t4/t5). ----------------------
uart_send:
    sw   t2, 16(s2)             # TX = byte (starts the smclk-domain core)
    li   t6, 20000
utc_wait:
    lw   t3, 4(s2)              # SR
    andi t3, t3, 1              # UTCIF
    bnez t3, utc_set
    addi t6, t6, -1
    bnez t6, utc_wait
    j    shlock_fail
utc_set:
    li   t3, 1
    sw   t3, 4(s2)              # SR write bit0 -> clr_UTCIF pulse
    li   t6, 20000
utc_clr_wait:
    lw   t3, 4(s2)
    andi t3, t3, 1
    beqz t3, utc_clear
    addi t6, t6, -1
    bnez t6, utc_clr_wait
    j    shlock_fail
utc_clear:
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
