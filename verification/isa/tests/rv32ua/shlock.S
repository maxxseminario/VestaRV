# See LICENSE for license details.

# VestaRV: advisory software locks for shared-peripheral sessions
# Register-level atomicity is free, since the arbiter grants whole transactions, but SESSION-level ownership is an ADVISORY LOCK WORD in shared RAM, taken with the LR/SC spin pattern using hartid-scaled backoff and a bounded retry. All harts contend for UART1 sessions at 0x4500: each hart commits 4 sessions, and a session acquires the lock, transmits a 4-byte message with the full per-byte UTCIF flag dance, journals every byte at a lock-protected global index, re-checks the owner and releases.
# THE TB HAS NO UART RECEIVER, SO ATOMICITY IS PROVEN VIA THE JOURNAL: hart 0 requires JIDX to end at 16*NHARTS and every 4-aligned journal group to be ONE hart's four consecutive bytes, with per-hart session counts of exactly 4. Any interleaved session shears a group or collides on the index.
# The journal machinery is parameterised in NHARTS rather than hard-coded for four harts: the target index is 16*NHARTS; the journal is 64*NHARTS bytes and sits ABOVE the boot ROM loader rows, which an 18-hart journal would otherwise collide with, and is write-before-read so no bootrom zeroing is needed; the per-hart session tally is an array rather than a packed 32-bit word; and the acquire budget scales as 4096*NHARTS, so more contenders simply wait longer.
# UART1's baud core is smclk-domain, so hart 0 writes SYS_CLK_CR = 0 FIRST, because the boot ROM parks SMCLK on LFXT, then configures BR and CR with readbacks before opening the gate. There is no token ring: the LOCK is the only serialiser and contention is the point.
# Shared words, with the control block below 0x10500 and the journal and counts above the loader rows: LOCK = 0x10240, 0 free or hartid + 1 held; OWNER = 0x10244, re-checked before release; GO = 0x10248; JIDX = 0x1024C; DONE[h] = 0x10250 + 4*h; JOURNAL = 0x11000, 16*NHARTS words, one per transmitted byte; COUNTS = 0x11800, NHARTS words.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_UART1   0x4500      /* +0 CR, +4 SR, +8 BR, +16 TX */
#define LOCK       0x10240
#define OWNER      0x10244
#define GO         0x10248
#define JIDX       0x1024C
#define DONE_BASE  0x10250
#define JOURNAL    0x11000
#define COUNTS     0x11800
#define GO_MAGIC   0x600D10CC
#define UART_BR    1
#define UART_CR_EN 0x20
#define ACQ_BUDGET (4096*NHARTS)   /* 16384 at N=4 (identical); scales for N */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all tiles into
    # tile_entry (mp_boot.h). They park on GO.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
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

    # ---- tiles: park until hart 0 has configured UART1 (reads only) --------
go_wait:
    lw   t0, 0(s3)
    li   t1, GO_MAGIC
    bne  t0, t1, go_wait
    j    sessions

    # ---- hart 0: SMCLK sanity + UART1 config, then open the gate -----------
hart0:
    li   t0, 0x4900            # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)           # SMCLK -> HFXT (UART baud core is smclk-domain)
    li   t0, UART_BR
    sw   t0, 8(s2)             # BR=1 with readback
    lw   t1, 8(s2)
    bne  t1, t0, shlock_fail
    li   t0, UART_CR_EN
    sw   t0, 0(s2)             # CR=EN with readback
    lw   t1, 0(s2)
    bne  t1, t0, shlock_fail
    li   t0, GO_MAGIC
    sw   t0, 0(s3)             # GO: all harts contend from here

    # ---- every hart: 4 lock-protected UART1 sessions ------------------------
sessions:
    .option push
    .option arch, +a
    li   s6, 4                 # sessions to commit
session_loop:
    li   t6, ACQ_BUDGET        # bounded acquire budget: a broken lock FAILS
                               # inside the tb's 100ms watchdog (M5a rule)
acquire:
    lr.w t0, (s7)
    bnez t0, acq_backoff       # held by someone
    sc.w t0, s11, (s7)         # claim: LOCK = hartid+1
    beqz t0, got_lock
acq_backoff:
    addi t6, t6, -1
    beqz t6, shlock_fail
    slli t1, s10, 3            # backoff = hartid*8 + 8 spins (M4c rule)
    addi t1, t1, 8
1:  addi t1, t1, -1
    bnez t1, 1b
    j    acquire
got_lock:
    sw   s11, 0(s8)            # OWNER = me
    lw   s1, 0(s5)             # JIDX (lock-protected — no atomics needed)
    slli t5, s1, 2
    add  t5, t5, s9            # journal write pointer
    li   t4, 0                 # byte index in this session
byte_loop:
    slli t2, s10, 4
    add  t2, t2, t4
    addi t2, t2, 0x40          # word = 0x40 + hartid*16 + i (nonzero)
    sw   t2, 0(t5)             # journal the byte...
    jal  ra, uart_send         # ...and transmit it (full UTCIF dance)
    addi t5, t5, 4
    addi t4, t4, 1
    li   t3, 4
    bne  t4, t3, byte_loop
    addi s1, s1, 4
    sw   s1, 0(s5)             # JIDX += 4 (still under the lock)
    lw   t3, 0(s8)             # OWNER still me? (direct mutex evidence)
    bne  t3, s11, shlock_fail
    sw   x0, 0(s7)             # release (plain store)
    addi s6, s6, -1
    bnez s6, session_loop
    .option pop

    beqz s10, check_journal

    # ---- tiles: report DONE, inline PASS, verify forever -------------------
    slli t0, s10, 2
    add  t0, t0, s4
    li   t1, 0x10CC0000
    add  t1, t1, s10
    sw   t1, 0(t0)             # DONE[h]
    li   a0, 0xCAFEBABE        # inline PASS (tb latches a0_1..a0_(N-1))
tile_verify:                   # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shlock_fail
    j    tile_verify

    # ---- hart 0: bounded-wait all DONEs, then adjudicate the journal -------
check_journal:
    li   s6, 1
dw_loop:
    slli t0, s6, 2
    add  t1, t0, s4            # DONE[h]
    li   t2, 0x10CC0000
    add  t2, t2, s6
    li   t6, 100000            # bounded (M12: covers serialized launch)
dw_poll:
    lw   t3, 0(t1)
    beq  t3, t2, dw_ok
    addi t6, t6, -1
    bnez t6, dw_poll
    j    shlock_fail
dw_ok:
    addi s6, s6, 1
    li   t0, NHARTS
    bltu s6, t0, dw_loop

    lw   t0, 0(s5)             # JIDX: NHARTS sessions-of-4 * 4 bytes, no shears
    li   t1, (16*NHARTS)
    bne  t0, t1, shlock_fail

    li   t0, COUNTS            # zero the per-hart session tally (NHARTS words)
    li   t1, NHARTS
cnt_zero:
    sw   zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, cnt_zero

    li   t5, (64*NHARTS)       # journal byte span = 16*NHARTS words * 4
    add  t5, t5, s9            # journal end pointer
    mv   t1, s9                # group pointer
grp_loop:
    lw   t2, 0(t1)             # first entry of the group
    addi t3, t2, -0x40
    andi t4, t3, 0xF
    bnez t4, shlock_fail       # group must START a session (i == 0)
    srli t4, t3, 4             # owning hart
    sltiu t3, t4, NHARTS
    beqz t3, shlock_fail       # hart in 0..NHARTS-1
    li   t6, COUNTS            # COUNTS[hart] += 1
    slli t3, t4, 2
    add  t6, t6, t3
    lw   t3, 0(t6)
    addi t3, t3, 1
    sw   t3, 0(t6)
    lw   t3, 4(t1)             # remaining 3 bytes: same hart, consecutive
    addi t4, t2, 1
    bne  t3, t4, shlock_fail
    lw   t3, 8(t1)
    addi t4, t2, 2
    bne  t3, t4, shlock_fail
    lw   t3, 12(t1)
    addi t4, t2, 3
    bne  t3, t4, shlock_fail
    addi t1, t1, 16
    bltu t1, t5, grp_loop
    li   t0, COUNTS            # every hart committed EXACTLY 4 sessions
    li   t1, NHARTS
cnt_check:
    lw   t2, 0(t0)
    li   t3, 4
    bne  t2, t3, shlock_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, cnt_check

    RVTEST_PASS                # a0 = 0xCAFEBABE, spin

shlock_fail:
    RVTEST_FAIL                # a0 = 0xDEADBEEF, spin

    # ---- uart_send: TX t2 on UART1 + full UTCIF flag dance (shperiph
    # ---- pattern; clobbers t3/t6, preserves t2/t4/t5). ----------------------
uart_send:
    sw   t2, 16(s2)            # TX = byte (starts the smclk-domain core)
    li   t6, 20000
utc_wait:
    lw   t3, 4(s2)            # SR
    andi t3, t3, 1           # UTCIF
    bnez t3, utc_set
    addi t6, t6, -1
    bnez t6, utc_wait
    j    shlock_fail
utc_set:
    li   t3, 1
    sw   t3, 4(s2)           # SR write bit0 -> clr_UTCIF pulse
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
