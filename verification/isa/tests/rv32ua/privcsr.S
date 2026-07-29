# See LICENSE for license details.

#*****************************************************************************
# privcsr.S   (P1 standard M-mode trap CSR file — WARL / readback sweep)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST. Proves the ten P1 CSRs implemented in csr_unit.vhd
# behave EXACTLY as frozen in ~/vesta_docs/priv_arch/p0_specs.md 2.1:
#
#   0x300 mstatus   MIE(3)/MPIE(7)/MPP(12:11 WARL {11}); every other bit reads 0
#   0x310 mstatush  legal, read-zero / write-ignore
#   0x305 mtvec     BASE(31:2) R/W; MODE(1:0) WARL {00}
#   0x304 mie       MSIE(3)/MTIE(7)/MEIE(11); every other bit reads 0
#   0x344 mip       READ-ONLY mirror of the msip/mtip/meip levels (writes ignored)
#   0x340 mscratch  full 32-bit R/W
#   0x341 mepc      bit0 always 0; bit1 writable iff ENABLE_COMPRESSED (C is ON
#                   in the default/ON Castalia config, so bit1 must HOLD)
#   0x342 mcause    Interrupt(31) + code(3:0) only; bits 30:4 read 0
#   0x343 mtval     full 32-bit R/W
#   0x7C0 mtrapctl  bit0 LEGACY, RESET '1'; bits 31:1 WARL 0
#
# This is the KICKOFF §3b CLASS-4 test (readback completeness): every CSR must
# read back what it wrote AND every reserved/WPRI field must read its spec
# value — a field that silently stores more than the spec allows is exactly the
# bug class this file exists to catch.
#
# BUILD-TIME DISPATCH (extjvt.S / extzfinx.S idiom — the X1 convention):
#   ON  (-DCORE_ENABLE_TRAPCSR appended to RISCV_GCC_OPTS when the trapCsr
#        config is staged): run the sweep -> RVTEST_PASS.
#   OFF (default build, macro unset): the ten addresses are UNKNOWN CSRs and
#        this core DEAD-ENDS an illegal instruction in the terminal TRAP_STATE,
#        so the sweep must not be assembled at all. The #else arm FAILs
#        immediately and loudly — privcsr is deliberately NOT in the default
#        behavioral_mp runner array, so this arm should never execute; if it
#        ever does, the ON/OFF staging discipline was violated.
#   The OFF polarity of these ten addresses is proven SEPARATELY by the P0
#   privprobe poisons (behavioral_mp_stripped/run_extoff.sh + trap_watch.tcl),
#   one poison per address — a dead-end trap can only ever prove one at a time.
#
# NOTE on `csrr` (UPDATED at P3-entry, 2026-07-29): csr_write_en now implements
# the spec's instruction-form rule — CSRRW/CSRRWI always write; CSRRS/CSRRC with
# rs1=x0 and CSRRSI/CSRRCI with uimm=0 do NOT write. A plain `csrr` therefore
# no longer asserts the write enable at all (CHECK 34 pins this via the mcycle
# write-precedence freeze). P3-entry also added mstatus.MPRV (CHECK 4/33) and
# the csr_addr_valid write-enable gate (CHECK 35).
#
# t4 carries the CHECK ID at every comparison, so a FAIL is localisable from a
# waveform / a0 post-mortem without re-running.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# =============================================================================
# P2 COMPATIBILITY (2026-07-28). Two mstatus fields differ between the two ON
# flavours, so this file must carry both expectations to stay a valid gate on
# BOTH (trapCsr-only, and trapCsr+umode):
#   MPP(12:11)  WARL {11}    without U-mode -> ANY written value stores 11
#               WARL {00,11} with    U-mode -> a written 00 STAYS 00
#               (01/10 still map to 11 — the frozen conservative direction)
#   TW(21)      does not exist without U-mode (reads 0); WARL {0,1} with it.
# P_MPP0  = the MPP field as it reads after writing 0 to mstatus.
# P_TWALL = the TW field as it reads after writing all-ones to mstatus.
# =============================================================================
#ifdef CORE_ENABLE_UMODE
#define P_MPP0  0x00000000
#define P_TWALL 0x00200000
#define P_MPRVALL 0x00020000
#else
#define P_MPP0  0x00001800
#define P_TWALL 0x00000000
#define P_MPRVALL 0x00000000
#endif
/* P_MPRVALL: mstatus.MPRV (17), P3-entry — WARL {0,1} with U-mode, read-only
   0 without it (priv spec: MPRV is read-only 0 when U is not supported). */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any CSR work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pcsr_fail

#ifdef CORE_ENABLE_TRAPCSR

    .option push
    .option arch, +zicsr

    # =====================================================================
    # CHECK 1 — mtrapctl (0x7C0) RESET VALUE.
    # MUST be read FIRST, before anything else can touch it: LEGACY resets '1'
    # (D1: a P1 chip still delivers traps through the legacy irq_handler/IVT
    # path until software opts in), and bits 31:1 are WARL 0.
    # =====================================================================
    li   t4, 1
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pcsr_fail

    # ---- CHECK 2: mtrapctl holds a written 0 (bits 31:1 still read 0) ----
    li   t4, 2
    li   t1, 0xFFFFFFFE             # every bit EXCEPT LEGACY
    csrw 0x7C0, t1
    csrr t2, 0x7C0
    li   t3, 0x00000000
    bne  t2, t3, pcsr_fail

    # ---- CHECK 3: mtrapctl takes LEGACY back, reserved bits still 0 ----
    li   t4, 3
    li   t1, 0xFFFFFFFF
    csrw 0x7C0, t1
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pcsr_fail
    # LEGACY is restored to '1' here and is NEVER left 0 by this test (the
    # legacy IVT delivery path must survive intact for every other test).

    # =====================================================================
    # CHECK 4/5 — mstatus (0x300). MIE(3), MPIE(7), MPP(12:11) and — only on
    # a U-mode build — TW(21). See the P_MPP0/P_TWALL block at the top of the
    # file: a written 11 stores 11 on BOTH flavours, a written 00 stores 11
    # without U-mode and 00 with it.
    # all-ones  -> 0x1888 (MPP=11 | MPIE | MIE) [+ TW on a U-mode build]
    # all-zeros -> P_MPP0
    # =====================================================================
    li   t4, 4
    li   t1, 0xFFFFFFFF
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, (0x00001888|P_TWALL|P_MPRVALL)
    bne  t2, t3, pcsr_fail

    li   t4, 5
    li   t1, 0x00000000
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, P_MPP0
    bne  t2, t3, pcsr_fail

    # ---- CHECK 6: MIE and MPIE are independently writable ----
    li   t4, 6
    li   t1, 0x00000008             # MIE only
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, (P_MPP0|0x00000008)
    bne  t2, t3, pcsr_fail

    li   t4, 7
    li   t1, 0x00000080             # MPIE only
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, (P_MPP0|0x00000080)
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # CHECK 8 — mstatush (0x310): legal CSR, reads 0 even after a full write.
    # =====================================================================
    li   t4, 8
    li   t1, 0xFFFFFFFF
    csrw 0x310, t1
    csrr t2, 0x310
    bne  t2, x0, pcsr_fail

    # =====================================================================
    # CHECK 9/10/11 — mtvec (0x305): BASE(31:2) holds, MODE(1:0) WARL {00}.
    # =====================================================================
    li   t4, 9
    li   t1, 0xDEADBEEF             # MODE bits set -> must be dropped
    csrw 0x305, t1
    csrr t2, 0x305
    li   t3, 0xDEADBEEC
    bne  t2, t3, pcsr_fail

    li   t4, 10
    li   t1, 0x00008003             # a plausible handler base + MODE=11
    csrw 0x305, t1
    csrr t2, 0x305
    li   t3, 0x00008000
    bne  t2, t3, pcsr_fail

    li   t4, 11
    li   t1, 0xFFFFFFFF
    csrw 0x305, t1
    csrr t2, 0x305
    li   t3, 0xFFFFFFFC
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # CHECK 12/13 — mie (0x304): MSIE(3)/MTIE(7)/MEIE(11) only.
    # =====================================================================
    li   t4, 12
    li   t1, 0xFFFFFFFF
    csrw 0x304, t1
    csrr t2, 0x304
    li   t3, 0x00000888
    bne  t2, t3, pcsr_fail

    li   t4, 13
    li   t1, 0x00000080             # MTIE only
    csrw 0x304, t1
    csrr t2, 0x304
    li   t3, 0x00000080
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # CHECK 14/15 — mip (0x344): READ-ONLY mirror. No CLINT/router source is
    # armed at this point in the test, so all three levels are low and mip
    # must read 0 both before and after a full-width write.
    # =====================================================================
    li   t4, 14
    csrr t2, 0x344
    bne  t2, x0, pcsr_fail

    li   t4, 15
    li   t1, 0xFFFFFFFF
    csrw 0x344, t1
    csrr t2, 0x344
    bne  t2, x0, pcsr_fail

    # =====================================================================
    # CHECK 16/17/18 — mscratch (0x340): all 32 bits R/W.
    # =====================================================================
    li   t4, 16
    li   t1, 0xA5A5A5A5
    csrw 0x340, t1
    csrr t2, 0x340
    bne  t2, t1, pcsr_fail

    li   t4, 17
    li   t1, 0x5A5A5A5A
    csrw 0x340, t1
    csrr t2, 0x340
    bne  t2, t1, pcsr_fail

    li   t4, 18
    li   t1, 0xFFFFFFFF
    csrw 0x340, t1
    csrr t2, 0x340
    bne  t2, t1, pcsr_fail

    # =====================================================================
    # CHECK 19/20/21 — mepc (0x341): bit0 ALWAYS 0; bit1 HOLDS (C is on).
    # =====================================================================
    li   t4, 19
    li   t1, 0xDEADBEEF             # bit0=1, bit1=1
    csrw 0x341, t1
    csrr t2, 0x341
    li   t3, 0xDEADBEEE             # bit0 cleared, bit1 kept
    bne  t2, t3, pcsr_fail

    li   t4, 20
    li   t1, 0x00008001             # bit0 only
    csrw 0x341, t1
    csrr t2, 0x341
    li   t3, 0x00008000
    bne  t2, t3, pcsr_fail

    li   t4, 21
    li   t1, 0x00008002             # bit1 only — must SURVIVE on a C build
    csrw 0x341, t1
    csrr t2, 0x341
    li   t3, 0x00008002
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # CHECK 22/23/24 — mcause (0x342): Interrupt(31) + code(3:0) ONLY.
    # =====================================================================
    li   t4, 22
    li   t1, 0xFFFFFFFF
    csrw 0x342, t1
    csrr t2, 0x342
    li   t3, 0x8000000F
    bne  t2, t3, pcsr_fail

    li   t4, 23
    li   t1, 0x7FFFFFF0             # nothing implemented set
    csrw 0x342, t1
    csrr t2, 0x342
    bne  t2, x0, pcsr_fail

    li   t4, 24
    li   t1, 0x8000000B             # machine external interrupt encoding
    csrw 0x342, t1
    csrr t2, 0x342
    li   t3, 0x8000000B
    bne  t2, t3, pcsr_fail

    li   t4, 25
    li   t1, 0x0000000B             # ECALL-from-M exception encoding (cause 11)
    csrw 0x342, t1
    csrr t2, 0x342
    li   t3, 0x0000000B
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # CHECK 26/27/28 — mtval (0x343): all 32 bits R/W.
    # =====================================================================
    li   t4, 26
    li   t1, 0xCAFEBABE
    csrw 0x343, t1
    csrr t2, 0x343
    bne  t2, t1, pcsr_fail

    li   t4, 27
    li   t1, 0xFFFFFFFF
    csrw 0x343, t1
    csrr t2, 0x343
    bne  t2, t1, pcsr_fail

    li   t4, 28
    li   t1, 0x00000000
    csrw 0x343, t1
    csrr t2, 0x343
    bne  t2, x0, pcsr_fail

    # =====================================================================
    # CHECK 29 — CSRRS / CSRRC set/clear semantics on a full-width CSR, and
    # the CSRRW old-value return. Uses mscratch (no WARL masking to confuse
    # the arithmetic).
    # =====================================================================
    li   t4, 29
    li   t1, 0x0000FFFF
    csrw 0x340, t1
    li   t1, 0xFFFF0000
    csrs 0x340, t1                  # set the high half
    csrr t2, 0x340
    li   t3, 0xFFFFFFFF
    bne  t2, t3, pcsr_fail

    li   t4, 30
    li   t1, 0x0F0F0F0F
    csrc 0x340, t1                  # clear those bits
    csrr t2, 0x340
    li   t3, 0xF0F0F0F0
    bne  t2, t3, pcsr_fail

    li   t4, 31
    li   t1, 0x12345678
    csrrw t2, 0x340, t1             # t2 must receive the OLD value
    li   t3, 0xF0F0F0F0
    bne  t2, t3, pcsr_fail
    csrr t2, 0x340
    li   t3, 0x12345678
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # CHECK 33 — mstatus.MPRV (17), P3-entry item 1: WARL {0,1} on a U-mode
    # build, read-only 0 without one. CHECK 4 already proved the all-ones
    # write stores it; this pins the ISOLATED bit and clears it again.
    # (The MRET-to-U clears-MPRV rule is privumode CHECK 25 — it needs a
    # privilege round trip this file deliberately does not perform.)
    # =====================================================================
    li   t4, 33
    li   t1, 0x00020000
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, (P_MPP0|P_MPRVALL)
    bne  t2, t3, pcsr_fail
    csrw 0x300, x0                  # MPRV back to 0

    # =====================================================================
    # CHECK 34 — P3-entry item 3 (the csr_write_en FORM rule): a plain
    # `csrr` (CSRRS rd, csr, x0) must NOT assert the CSR write enable.
    # OBSERVABLE: the mcycle write-precedence. A CSR write to mcycle beats
    # the same-cycle increment, so a read form that (wrongly) writes back
    # FREEZES mcycle for every cycle it presents its decode. Two windows,
    # instruction-identical except the rs1 FIELD of the seven middle reads:
    #   window A: csrrs t1, mcycle, x5 with x5 = 0 — rs1 /= x0, a REAL
    #             write-back form under BOTH old and new rules (value 0
    #             stores back the read value = the freeze, in both);
    #   window B: csrr t1, mcycle — rs1 = x0, must not write when fixed.
    # Bug present: deltaB == deltaA exactly (identical timing, both
    # freeze). Fixed: mcycle keeps counting through window B's reads, so
    # deltaB > deltaA. Negative control p3e_csrform re-runs this check.
    # =====================================================================
    li   t4, 34
    li   x5, 0
    csrrs s2, 0xB00, x5             # window A start (write-back form)
    csrrs t1, 0xB00, x5
    csrrs t1, 0xB00, x5
    csrrs t1, 0xB00, x5
    csrrs t1, 0xB00, x5
    csrrs t1, 0xB00, x5
    csrrs t1, 0xB00, x5
    csrrs t1, 0xB00, x5
    csrrs s3, 0xB00, x5             # window A end
    sub  s2, s3, s2                 # deltaA
    csrrs s4, 0xB00, x5             # window B start (same write-back form)
    csrr t1, 0xB00
    csrr t1, 0xB00
    csrr t1, 0xB00
    csrr t1, 0xB00
    csrr t1, 0xB00
    csrr t1, 0xB00
    csrr t1, 0xB00
    csrrs s5, 0xB00, x5             # window B end
    sub  s4, s5, s4                 # deltaB
    bgeu s2, s4, pcsr_fail          # FAIL iff deltaA >= deltaB

    # =====================================================================
    # CHECK 35 — P3-entry item 2 (csr_valid AND csr_addr_valid): a WRITE to
    # an UNKNOWN CSR address (0x345 — adjacent to the implemented
    # mscratch/mepc/mcause/mtval/mip block) takes the illegal-instruction
    # trap and commits NOTHING. Needs standard mode (in legacy an illegal
    # dead-ends in TRAP_STATE): mtvec -> the +4 skip handler, LEGACY=0 for
    # exactly the faulting instruction, LEGACY restored immediately after.
    # mscratch carries a sentinel across the trap (hardware never writes
    # mscratch); mcause must read 2 back in M. Negative control
    # p3e_addrvalid re-runs this check (see the repro for its P3 scope).
    # =====================================================================
    li   t4, 35
    la   t1, pcsr_skip
    csrw 0x305, t1                  # mtvec = the +4 skip handler
    li   t1, 0x5AFEC0DE
    csrw 0x340, t1                  # mscratch sentinel
    csrw 0x300, x0                  # MIE = 0: nothing async in the window
    li   s5, 0
    csrw 0x7C0, x0                  # LEGACY = 0 — standard delivery ON
    csrw 0x345, t1                  # UNKNOWN CSR: traps, handler skips +4
    li   s5, 1                      # reached only via the handler resume
    li   t1, 1
    csrw 0x7C0, t1                  # LEGACY back to 1 IMMEDIATELY
    li   t3, 1
    bne  s5, t3, pcsr_fail          # the trap resumed at +4
    csrr t2, 0x342                  # mcause == 2 (illegal instruction)
    li   t3, 2
    bne  t2, t3, pcsr_fail
    csrr t2, 0x340                  # the sentinel survived: NO commit
    li   t3, 0x5AFEC0DE
    bne  t2, t3, pcsr_fail

    # =====================================================================
    # RESTORE the architectural state this test perturbed, so an ON build
    # running the rest of the suite is unaffected:
    #   mtrapctl.LEGACY = 1 (already restored at CHECK 35 — re-assert),
    #   mstatus.MIE/MPIE = 0, mie = 0.
    # =====================================================================
    li   t4, 36
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0
    csrw 0x304, x0
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pcsr_fail
    csrr t2, 0x304
    bne  t2, x0, pcsr_fail

    .option pop

    RVTEST_PASS

    # ---- CHECK 35's mtvec target: skip the faulting instruction (+4).
    # Reached only through the standard-mode trap; never by fall-through
    # (RVTEST_PASS above is a spin loop).
    .align 2
pcsr_skip:
    .option push
    .option arch, +zicsr
    csrr t2, 0x341                  # mepc = the faulting csrw
    addi t2, t2, 4                  # norvc build: always +4
    csrw 0x341, t2
    mret
    .option pop

#else
    # OFF build: the ten P1 addresses are unknown CSRs (illegal instruction,
    # terminal TRAP_STATE). privcsr must only ever be run on a staged
    # -DCORE_ENABLE_TRAPCSR build; reaching here means it was not.
    li   t4, 0
    j    pcsr_fail
#endif

pcsr_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
