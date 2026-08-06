# See LICENSE for license details.

#*****************************************************************************
# dbghaltmp.S   (D-series, D1 -- THE HALT-REACHABILITY DETECTOR)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d1_spec.md sections 1-2, FROZEN 2026-08-05, by an agent
# that has not seen and will never see the D1 implementation.  Committed
# polarity: CORRECT RTL = PASS (R-K5-8).
#
# THIS TEST NEEDS A TESTBENCH HARNESS AND CANNOT RUN WITHOUT ONE.
#     ./xrun_dbg.sh rv32ua-p-dbghaltmp dbg_halt.tcl
# At D1 there is no debug module, so hdl/common/MCU.vhd leaves every tile's
# dbg_haltreq / dbg_resethaltreq / dbg_halted unconnected at their entity
# defaults.  The only way to raise a halt request in the MCU-level behavioral
# flow is a hierarchical FORCE, which needs `-access +rwc`; xrun_dbg.sh is that
# runner and dbg_halt.tcl is that harness.  Running this image under the
# ordinary xrun_batch.sh is a guaranteed FAIL with a1 = 0x0DB10001 -- no halt
# request is ever made, so no victim ever halts.  That is not a bug in the
# test; it is what "port-visible, not software-visible" means (d1_spec.md 5).
#
# THE THREE HALT-REACHABILITY CLASSES, one per victim
#   d1_spec.md scatters halt reachability across three clauses that are three
#   DIFFERENT pieces of RTL, and a build can get any one of them wrong on its
#   own.  Each victim parks in an ABSORBING state before the harness acts, so
#   the harness needs only a lower bound on when to fire -- there is no window
#   to calibrate and nothing to drift (method rule 7: find the edge where the
#   answer is structurally determined, do not tune a delay onto it).
#
#   hart 1  THE PARKED HART (F-D0P1-3, d1_spec.md 2 "Parked-hart ungate").
#           `extinguish` puts it in SLEEPING with its clk_cpu GATED OFF.  A
#           halt request must UNGATE it -- the `dbg_halt_pend` term joining
#           en_clk_cpu.  If that term is missing the hart is simply deaf: a
#           debugger can never reach a parked hart, which on this chip means
#           three of four harts are unreachable in the normal idle state.
#           This is the single most likely D1 omission, because the OFF build
#           folds the term away and every knob-OFF gate stays green.
#
#   hart 2  THE WEDGED HART (R-D0-3(6), d1_spec.md 2 "TRAP_STATE is
#           halt-reachable knob-ON").  It executes .word 0x0000007F -- an
#           opcode absent from maindec's valid_opcode list on EVERY build, the
#           same positive control rocsrw.S uses -- and lands in the TERMINAL
#           TRAP_STATE.  Knob-ON, a halt request must rescue it.  This is the
#           clause that makes a terminal state non-terminal, so it is also the
#           clause whose knob-OFF inertness matters most; the OFF side is
#           dbgdenymp.S's and the standing sweeps', not this file's.
#
#   hart 3  THE RUNNING HART.  It spins on a shared FLAG word.  This is the
#           ordinary case, and it is the ONLY victim whose dpc can be checked
#           against a structurally known address range -- which is why it, not
#           the other two, carries the dpc and the resume assertions.
#
# WHAT IS ASSERTED, AND WHAT IS ONLY PUBLISHED (method rule 9: do not fill a
# metric that cannot mean anything)
#   ASSERTED for all three victims: the debug stub RAN (so entry happened and
#   pc reached DEBUG_ENTRY_ADDR); dcsr.cause == 3 (haltreq); dcsr.prv == 3 (M,
#   the mode every victim was in); dcsr.xdebugver == 4 (d1_spec.md 1, RO).
#   ASSERTED for hart 3: dpc lies inside its spin loop, and after `dret` the
#   loop RESUMED and ran on -- the exit half of "haltreq entry/exit".
#   ASSERTED for hart 1 (R-D1-3(2), promoted 2026-08-05 from published): dpc is
#   the address after its `extinguish`, i.e. tile_h1_park -- derived from the
#   image's own symbol with `la`, never a calibrated constant.  See the note at
#   the assertion for why that value is the only reading of "interrupted pc"
#   for a hart in SLEEPING, and why it is robust to being halted one
#   instruction later.
#   PUBLISHED but NOT asserted: dpc for hart 2 ONLY.  d1_spec.md leaves the
#   interrupted pc of a hart wedged in the terminal TRAP_STATE undefined, and
#   unlike hart 1 there is no label to anchor one to -- the hart is not about
#   to execute anything.  Asserting there would be inventing a requirement and
#   then testing the invention (method rule 9).  DPC[2] is published at 0x10068
#   on every run; R-D1-3(2) revisits it at D2.
#
# THE STUB, and why it is copied rather than linked
#   Same construction as dbgdenymp.S: a position-independent block copied to
#   DEBUG_ENTRY_ADDR in the SHARED window, so no new link.ld section and
#   therefore no build/.imgset wipe.  No `la`, no `auipc`, no branch leaving
#   the block.  It reads mhartid, so ONE source serves all three victims.
#   It clobbers t0-t2 and a2-a5; hart 3's spin loop deliberately uses only
#   s2/s3, so the resumed loop is unaffected by the visit.
#   Only hart 3's stub sets FLAG.  That guard is load-bearing: if harts 1 and
#   2 set it too, hart 3's loop would exit BEFORE hart 3 was halted and its dpc
#   would no longer be inside the loop -- the assertion would then be measuring
#   the harness's arrival order instead of the RTL.
#
# DEBUG_ENTRY_ADDR = 0x10780 -- MIGRATED 2026-08-05 from TCM 0xBE00 under
#   R-DD3 / R-D2-1(3): a tile's TCM is unreachable from the shared bus (four
#   proofs in d2_probe P5), so a Debug Module can never place code at 0xBE00
#   and the debug entry page moved into the shared window.  The full argument
#   is in dbgdenymp.S's header; the mechanics here are unchanged -- an
#   ordinary store loop plants the stub, after boot, inside the bootrom's
#   zero range -- except that the page is now GLOBAL, so hart 0 plants it
#   ONCE before it launches anybody and the victims plant nothing.
#   This file's stub is 25 words and fits inside the 64-word entry page
#   0x10780-0x1087F (R-D2-2(3)).
#   If the ruling moves again: one #define below, one in dbgdenymp.S, one in
#   dbgstepmp.S and one `set DBG_ENTRY` in dbg_rst.tcl.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => all three classes of hart are halt-reachable,
# every entry reported cause = haltreq from M-mode, and `dret` resumed the
# running hart where it was interrupted.  a0 = 0xDEADBEEF with:
#   a1 = 0x0DB10001   NO VICTIM EVER HALTED (a2 = hart index still silent).
#                     Under xrun_batch.sh this is the expected result and means
#                     nothing; under dbg_halt.tcl it is THE finding -- read the
#                     harness's own HALTLOG lines to see whether dbg_halted
#                     ever rose.
#   a1 = 0x0DB1h002   HALT[h] carried the wrong magic (a2 = the value): the
#                     stub ran but not as itself -- suspect a partial copy
#   a1 = 0x0DB1h003   dcsr.cause != 3 on hart h (a2 = dcsr).  cause 1 = ebreak,
#                     4 = step, 5 = resethaltreq -- a wrong cause names the
#                     wrong entry path.
#   a1 = 0x0DB1h004   dcsr.prv != 3 on hart h (a2 = dcsr): the interrupted
#                     privilege was not recorded as M
#   a1 = 0x0DB1h005   dcsr.xdebugver != 4 on hart h (a2 = dcsr)
#   a1 = 0x0DB10006   hart 3's dpc is OUTSIDE its spin loop (a2 = dpc,
#                     a3 = loop start): entry did not record the interrupted pc
#   a1 = 0x0DB10007   hart 3 never RESUMED after `dret` (a2 = RESUMED).  Either
#                     dret did not return to dpc, or it did not leave debug
#                     mode, or the hart re-entered debug immediately.
#   a1 = 0x0DB1000A   hart 1's dpc is not the address after its `extinguish`
#                     (a2 = DPC[1], a3 = &tile_h1_park): the parked victim
#                     entered debug without recording its resume PC
#   a1 = 0x0DB10008   a shared word did not read back: shared-RAM setup break
#   a1 = 0x0DB10009   base-ISA sanity failed
# NO a0 AT ALL (tb watchdog): hart 0 wedged in its own preamble.
#
# NEGATIVE CONTROL -- how the non-debug half of this file was SEEN TO WORK
#   at unimplemented HEAD, where no port exists and nothing can halt:
#       -DDBGHALT_NC_SELFENTRY
#   Each victim JUMPS to its own planted stub instead of parking, and the stub
#   publishes CONSTANTS (a synthetic dcsr with xdebugver=4, cause=3, prv=3 and
#   a dpc taken from the return address) instead of reading 0x7B0/0x7B1, which
#   would trap on a tree with no debug CSRs.  Everything else -- the planting,
#   the copy, the hartid dispatch, the FLAG guard, the publish, hart 0's
#   bounded wait, every assertion and the whole verdict path -- executes
#   exactly as it will post-D1.  A PASS on that arm proves the instrument is
#   LIVE and that a later FAIL is about the RTL, not about the plumbing
#   (method rule 5: an expected-zero needs independent proof the instrument
#   was alive).  It is a CONTROL: it makes no claim about debug mode, it
#   cannot detect anything, and it must never be quoted as a D1 result.
#
# SHARED WORDS CLAIMED (all < 0x10500, inside the bootrom zero range) -- the
#   same 12-word D1 band 0x10050-0x1007C that dbgdenymp.S and dbgstepmp.S use,
#   with this file's meanings.  One image per sim: the three never coexist.
#     0x10050          RESUMED    hart 3's post-dret proof
#     0x10054/58/5C    HALT[1..3] = 0x10050 + 4*h   the stub's arrival magic
#     0x10060          FLAG       hart 3's spin-loop release (= DPC[0], unused)
#     0x10064/68/6C    DPC[1..3]  = 0x10060 + 4*h
#     0x10070          (unused, = DCSR[0])
#     0x10074/78/7C    DCSR[1..3] = 0x10070 + 4*h
#   N-agnostic: no word is indexed past hart 3, and exactly three victims are
#   launched at any NHARTS.  At N=4 the band is free (shlrsc's tile hammer tops
#   out at 0x1004C below, shcount's atomic counter is at 0x10080 above); at
#   N=18 it overlaps shlrsc's hammer, benign by the ledger's isolation rule.
#   Plus, since the 2026-08-05 migration, the SHARED DEBUG ENTRY PAGE at
#   0x10780 (d2_spec section 1), where hart 0 plants the 25-word stub.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_RESUMED   0x10050
#define SH_HALT_BASE 0x10050        /* HALT[h] = base + 4*h, h = 1..3 */
#define SH_FLAG      0x10060
#define SH_DPC_BASE  0x10060        /* DPC[h]  = base + 4*h */
#define SH_DCSR_BASE 0x10070        /* DCSR[h] = base + 4*h */

#define HALT_MAGIC   0x0DB60000     /* the stub adds mhartid */
#define RESUME_MAGIC 0x0DB6DEE0

#define DBG_ENTRY    0x10780
#define TILE_WORDS   1024
#define ARM_BUDGET   40000          /* ~ 40000 * 3 shared loads; see the note */
#define BADOP        0x0000007F     /* absent from valid_opcode on every build */
#define DRET_INSN    0x7B200073
#define CSRR_T0_7B1  0x7B1022F3     /* csrrs t0, dpc,  x0  -- debug mode only */
#define CSRR_T1_7B0  0x7B002373     /* csrrs t1, dcsr, x0  -- debug mode only */
#define CSRR_A4_F14  0xF1402773     /* csrrs a4, mhartid, x0 */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x0DB10008
    li   t0, SH_RESUMED
    li   t1, 12                     # 12 words: 0x10050 .. 0x1007C
dh_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dh_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dh_clr

    li   t0, 1234                   # base-ISA sanity
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0DB10009
    bne  t2, t3, dh_fail

    jal  ra, dh_plant               # THE plant: the page is shared, so this
                                    # one call covers every victim, and it
                                    # happens before any of them is launched

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for all three stubs to report.  The budget must trip
    # INSIDE the 100 ms tb watchdog: each round is 3 shared loads, ~15
    # mclk at 24 MHz, so 40000 rounds is roughly 25 ms -- comfortably
    # inside, and long enough to cover the harness's own settling.
    # ==================================================================
    li   s4, SH_HALT_BASE
    li   t6, ARM_BUDGET
dh_wait:
    lw   t2, 4(s4)
    beqz t2, dh_wait_next
    lw   t3, 8(s4)
    beqz t3, dh_wait_next
    lw   t4, 12(s4)
    bnez t4, dh_armed
dh_wait_next:
    addi t6, t6, -1
    bnez t6, dh_wait

    # name the first silent victim
    li   a1, 0x0DB10001
    li   a2, 1
    lw   t2, 4(s4)
    beqz t2, dh_fail
    li   a2, 2
    lw   t2, 8(s4)
    beqz t2, dh_fail
    li   a2, 3
    j    dh_fail

dh_armed:
    # ==================================================================
    # per-victim checks, h = 1..3
    # ==================================================================
    li   s5, 1                      # h
dh_loop:
    slli s6, s5, 2                  # 4*h

    li   t0, SH_HALT_BASE
    add  t0, t0, s6
    lw   a2, 0(t0)                  # HALT[h]
    li   t1, HALT_MAGIC
    add  t1, t1, s5
    slli a1, s5, 8
    li   t2, 0x0DB10002
    add  a1, a1, t2
    bne  a2, t1, dh_fail            # the stub ran, but not as itself

    li   t0, SH_DCSR_BASE
    add  t0, t0, s6
    lw   a2, 0(t0)                  # DCSR[h]

    srli t3, a2, 6                  # dcsr.cause = bits 8:6
    andi t3, t3, 7
    li   t4, 3                      # 3 = haltreq
    slli a1, s5, 8
    li   t2, 0x0DB10003
    add  a1, a1, t2
    bne  t3, t4, dh_fail

    andi t3, a2, 3                  # dcsr.prv = bits 1:0
    li   t4, 3                      # 3 = M
    slli a1, s5, 8
    li   t2, 0x0DB10004
    add  a1, a1, t2
    bne  t3, t4, dh_fail

    srli t3, a2, 28                 # dcsr.xdebugver = bits 31:28
    li   t4, 4
    slli a1, s5, 8
    li   t2, 0x0DB10005
    add  a1, a1, t2
    bne  t3, t4, dh_fail

    addi s5, s5, 1
    li   t0, 4
    blt  s5, t0, dh_loop

    # ==================================================================
    # THE dpc ASSERTIONS.  Both expected values are derived from the
    # image's OWN SYMBOLS at run time -- `la` of a label, never a
    # constant anyone calibrated (method rule 7: find the edge where
    # the address is structurally determined).  hart 0 and the tiles run
    # the same image at the same addresses, so `la` here names exactly
    # the address the victim was executing at.
    #
    # hart 1, THE PARKED VICTIM (R-D1-3(2), promoted from published to
    # asserted).  It parks with `extinguish`, so its resume PC is the
    # address of the instruction AFTER the extinguish -- tile_h1_park.
    # d1_spec.md 2 says only "dpc <- interrupted pc"; for a hart in
    # SLEEPING the resume PC is the one address that statement can mean,
    # and it is anchored to a label rather than to a number.
    # THE ASSERTION IS ALSO INSENSITIVE TO A DETAIL IT SHOULD NOT DEPEND
    # ON: if the victim were halted one instruction later -- while
    # executing `tile_h1_park: j tile_h1_park` -- the resume PC would be
    # the jump target, which is tile_h1_park again.  Both readings give
    # the same answer, so this does not silently become a test of when
    # the harness happened to fire.
    li   t0, SH_DPC_BASE + 4
    lw   a2, 0(t0)                  # DPC[1]
    la   a3, tile_h1_park
    li   a1, 0x0DB1000A
    bne  a2, a3, dh_fail

    # hart 2, THE WEDGED VICTIM: STILL PUBLISHED, STILL NOT ASSERTED,
    # and the reason is not laziness.  d1_spec.md does not define the
    # interrupted pc of a hart sitting in the terminal TRAP_STATE, and
    # unlike hart 1 there is no structural anchor to derive one from:
    # the hart is not "about to execute" anything, so no label names its
    # resume address.  Asserting a value here would be inventing a
    # requirement and then testing the invention.  DPC[2] is published
    # at 0x10068 on every run for the D2 pass to read and for the spec
    # to rule on.  (R-D1-3(2): revisit at D2.)
    #
    # hart 3, THE RUNNING VICTIM: dpc inside the spin loop, plus the
    # dret resume -- the exit half of "haltreq entry/exit".
    # ==================================================================
    li   t0, SH_DPC_BASE + 12
    lw   a2, 0(t0)                  # DPC[3]
    la   a3, h3_loop
    la   t4, h3_loop_end
    li   a1, 0x0DB10006
    bltu a2, a3, dh_fail
    bgeu a2, t4, dh_fail

    li   t0, SH_RESUMED
    lw   a2, 0(t0)
    li   t1, RESUME_MAGIC
    li   a1, 0x0DB10007
    bne  a2, t1, dh_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

dh_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # dh_plant -- copy the debug stub to DEBUG_ENTRY_ADDR in the SHARED
    # window.  No arguments; clobbers t0-t3.  Called ONCE, by hart 0, before
    # any victim is launched (the page is global since the 2026-08-05
    # migration).
    # =====================================================================
dh_plant:
    la   t0, dh_stub_start
    la   t1, dh_stub_end
    li   t2, DBG_ENTRY
1:  lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    blt  t0, t1, 1b
    ret

    # ---- THE DEBUG STUB.  Copied verbatim to DEBUG_ENTRY_ADDR. ----------
    # Relocation rules: no `la`, no `auipc`, no branch or jump leaving the
    # block.  Its two internal branches are relocation-invariant.  No .align
    # (a silent no-op inside `.option norvc`, and every instruction is 4 bytes).
    # Clobbers t0-t2, a2-a5 only.
dh_stub_start:
    .word CSRR_A4_F14               # a4 = mhartid
    slli a3, a4, 2                  # a3 = 4*h
#ifdef DBGHALT_NC_SELFENTRY
    # CONTROL ARM: no debug CSRs exist on the tree this was authored against,
    # so publish CONSTANTS shaped exactly like the real thing --
    # dcsr = xdebugver 4, cause 3 (haltreq), prv 3 (M); dpc = the caller's ra,
    # which for hart 3 is inside its spin loop, exactly where the real dpc
    # must land.  Everything downstream is then exercised for real.
    mv   t0, ra                     # "dpc"
    li   t1, 0x400000C3             # "dcsr": ver=4, cause=3, prv=3
#else
    .word CSRR_T0_7B1               # t0 = dpc
    .word CSRR_T1_7B0               # t1 = dcsr
#endif
    li   a5, SH_DPC_BASE
    add  a5, a5, a3
    sw   t0, 0(a5)
    li   a5, SH_DCSR_BASE
    add  a5, a5, a3
    sw   t1, 0(a5)
    # ONLY hart 3 releases the spin loop -- see the header.
    li   a2, 3
    bne  a4, a2, 2f
    li   a5, SH_FLAG
    li   t2, 1
    sw   t2, 0(a5)
2:  li   a5, SH_HALT_BASE
    add  a5, a5, a3
    li   t2, HALT_MAGIC
    add  t2, t2, a4
    sw   t2, 0(a5)                  # publish LAST: HALT[h] means "all of it"
#ifdef DBGHALT_NC_SELFENTRY
    ret                             # CONTROL ARM: an ordinary return
#else
    .word DRET_INSN
#endif
dh_stub_end:

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
tile_entry:
    li   sp, 0xBFF0
    # No plant here since the migration: hart 0 planted the SHARED entry page
    # before this hart existed.
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, tile_h1
    li   t4, 2
    beq  t3, t4, tile_h2
    li   t4, 3
    beq  t3, t4, tile_h3
tile_park:
    j    tile_park

    # ---- hart 1: THE PARKED HART (clk_cpu gated off in SLEEPING) --------
tile_h1:
#ifdef DBGHALT_NC_SELFENTRY
    li   t0, DBG_ENTRY
    jalr ra, t0, 0
tile_h1_park:
    j    tile_h1_park
#else
    extinguish                      # -> SLEEPING, clk_cpu GATED.  ABSORBING.
tile_h1_park:
    j    tile_h1_park
#endif

    # ---- hart 2: THE WEDGED HART (terminal TRAP_STATE) ------------------
tile_h2:
#ifdef DBGHALT_NC_SELFENTRY
    li   t0, DBG_ENTRY
    jalr ra, t0, 0
tile_h2_park:
    j    tile_h2_park
#else
    .word BADOP                     # -> TRAP_STATE, terminal.  ABSORBING.
tile_h2_park:
    j    tile_h2_park
#endif

    # ---- hart 3: THE RUNNING HART ---------------------------------------
    # The loop body recomputes the FLAG address every round with `li`, so it
    # holds NO live register the stub could clobber.  dpc must land inside
    # [h3_loop, h3_loop_end) -- four words, structurally determined, nothing
    # calibrated.
tile_h3:
#ifdef DBGHALT_NC_SELFENTRY
    li   t0, DBG_ENTRY
    jalr ra, t0, 0
#endif
h3_loop:
    li   s3, SH_FLAG
    lw   s2, 0(s3)
    beqz s2, h3_loop
h3_loop_end:
    li   s3, SH_RESUMED
    li   s2, RESUME_MAGIC
    sw   s2, 0(s3)
tile_h3_park:
    j    tile_h3_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every path above ends in a spin or an unconditional jump.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
