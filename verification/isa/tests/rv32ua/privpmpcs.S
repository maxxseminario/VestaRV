# See LICENSE for license details.

#*****************************************************************************
# privpmpcs.S   (P3 PMP CSR bank — WARL / readback / LOCK sweep)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST. Proves the twenty P3 CSRs implemented in csr_unit.vhd
# behave EXACTLY as frozen in ~/vesta_docs/priv_arch/p0_specs.md 4 / 4.1:
#
#   0x3A0-0x3A3 pmpcfg0-3    four packed entry cfg BYTES each
#                            (entry 4n+j = bits 8j+7 downto 8j)
#                            R(0) W(1) X(2) A(4:3) L(7); bits 6:5 WARL 0;
#                            W PINNED 0 when R=0; A in {OFF,TOR,NA4,NAPOT}
#   0x3B0-0x3BF pmpaddr0-15  bits 29:0 stored (= physical address 31:2);
#                            bits 31:30 WARL 0
#
#   LOCK (L=1): that entry's cfg byte AND its pmpaddr are write-ignored until
#   RESET. An entry i locked with A=TOR ALSO write-locks pmpaddr[i-1] (that is
#   its region BASE). Lock filtering is PER BYTE inside a pmpcfg word write, so
#   an unlocked byte of the same word still takes the write.
#
# This is the KICKOFF 3b CLASS-4 test (readback completeness) for the PMP bank:
# every reserved bit must read its spec value, and every lock must actually
# hold — a bank that stores more than the spec allows, or that lets a locked
# entry be reprogrammed, is exactly the bug class this file exists to catch.
#
# NAME (flagged decision, 2026-07-29): the runner contract makes the rcf
# basename EXACTLY 22 characters ("../rcf/" + 22 = the fixed 29-char
# riscv_tb TEST_FILE generic), so an rv32ua test name may be at most 9
# characters. "privpmpcsr" would produce a 23-char rcf that xrun.sh rejects
# outright; this file is therefore privpmpcs (-> rv32ua-p-privpmpcs.rcf, 22).
#
# SCOPE (2026-07-29): the PMP CHECK INTEGRATION (pre-issue fetch/load/store
# suppression, access-fault causes 1/5/7) is the vesta half of P3 and is NOT
# present on the build this file gates. Every check here is therefore a CSR
# write/readback — this test deliberately performs NO fenced load, store or
# fetch. Enforcement coverage belongs to privpmp / privpmpmtx.
#
# ENTRY BUDGET (documented so a later privpmp can coexist in one sim): PMP
# locks are released ONLY by hardware reset, so a locked entry stays locked for
# the rest of the simulation. This file therefore confines EVERY lock check to
# the HIGH entries 12-15 (pmpcfg3), and leaves entries 0-11 unlocked with
# pmpcfg0/1/2 written back to zero at the end. A later PMP test sharing the
# same image may use entries 0-11 freely; it must NOT expect 12-15 to be
# reprogrammable.
#
# BUILD-TIME DISPATCH (privcsr / privucsr idiom):
#   ON  (-DCORE_ENABLE_TRAPCSR -DCORE_ENABLE_UMODE -DCORE_ENABLE_PMP appended
#        to RISCV_GCC_OPTS when the pmp config is staged): run the sweep.
#   OFF (default build, macros unset): the twenty addresses are UNKNOWN CSRs and
#        this core DEAD-ENDS an illegal instruction in the terminal TRAP_STATE,
#        so the sweep must not be assembled at all. The #else arm FAILs
#        immediately and loudly — privpmpcs is deliberately NOT in the default
#        behavioral_mp runner array, so this arm should never execute.
#
# t4 carries the CHECK ID at every comparison, so a FAIL is localisable from a
# waveform / a0 post-mortem without re-running.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# =============================================================================
# Entry-count compatibility. The PMP CSR ADDRESS map is the 16-entry superset
# regardless of PMP_ENTRIES; with PMP_ENTRIES=8 the upper half (pmpcfg2/3,
# pmpaddr8-15) is still LEGAL but has no storage and reads WARL zero. The
# staged P3 configuration uses the default 16 entries; guard the upper-entry
# sections so this file stays a valid gate on an 8-entry build too.
# =============================================================================
#ifndef CORE_PMP_ENTRIES
#define CORE_PMP_ENTRIES 16
#endif

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any CSR work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ppmp_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    # =====================================================================
    # CHECK 1-4 — RESET VALUE of all four pmpcfg words. Spec-required: the
    # bank resets ALL ZERO (A=OFF, L=0) so no region exists and no entry is
    # locked out of software's reach at boot. Read FIRST, before anything
    # can perturb the bank.
    # =====================================================================
    li   t4, 1
    csrr t2, 0x3A0
    bne  t2, x0, ppmp_fail
    li   t4, 2
    csrr t2, 0x3A1
    bne  t2, x0, ppmp_fail
    li   t4, 3
    csrr t2, 0x3A2
    bne  t2, x0, ppmp_fail
    li   t4, 4
    csrr t2, 0x3A3
    bne  t2, x0, ppmp_fail

    # ---- CHECK 5-9: pmpaddr reset value, sampled across the whole bank ----
    li   t4, 5
    csrr t2, 0x3B0
    bne  t2, x0, ppmp_fail
    li   t4, 6
    csrr t2, 0x3B1
    bne  t2, x0, ppmp_fail
    li   t4, 7
    csrr t2, 0x3B7
    bne  t2, x0, ppmp_fail
    li   t4, 8
    csrr t2, 0x3B8
    bne  t2, x0, ppmp_fail
    li   t4, 9
    csrr t2, 0x3BF
    bne  t2, x0, ppmp_fail

    # =====================================================================
    # CHECK 10-12 — pmpaddr0 WARL: bits 31:30 are NOT stored (they would name
    # physical address bits 33:32, which this 32-bit fabric does not have).
    # =====================================================================
    li   t4, 10
    li   t1, 0xFFFFFFFF
    csrw 0x3B0, t1
    csrr t2, 0x3B0
    li   t3, 0x3FFFFFFF
    bne  t2, t3, ppmp_fail

    li   t4, 11
    li   t1, 0xDEADBEEF             # top two bits set -> must be dropped
    csrw 0x3B0, t1
    csrr t2, 0x3B0
    li   t3, 0x1EADBEEF
    bne  t2, t3, ppmp_fail

    li   t4, 12
    csrw 0x3B0, x0
    csrr t2, 0x3B0
    bne  t2, x0, ppmp_fail

    # =====================================================================
    # CHECK 13-17 — pmpcfg0 byte WARL. NOTE every pattern below leaves L=0:
    # writing L=1 to entries 0-3 would lock them for the rest of the sim (see
    # the ENTRY BUDGET note at the top). The lock checks live at the END of
    # this file and use entries 12-15 only.
    #   0x7F -> 0x1F : bits 6:5 are reserved and pinned 0; R/W/X/A all take
    #   0x60 -> 0x00 : bits 6:5 ALONE store nothing
    #   0x02 -> 0x00 : W is PINNED 0 when R=0 (the reserved combo WARL rule)
    #   0x03 -> 0x03 : with R=1 the same W bit stores
    # =====================================================================
    li   t4, 13
    li   t1, 0x7F7F7F7F
    csrw 0x3A0, t1
    csrr t2, 0x3A0
    li   t3, 0x1F1F1F1F
    bne  t2, t3, ppmp_fail

    li   t4, 14
    li   t1, 0x60606060
    csrw 0x3A0, t1
    csrr t2, 0x3A0
    bne  t2, x0, ppmp_fail

    li   t4, 15
    li   t1, 0x02020202             # W=1, R=0 on every entry
    csrw 0x3A0, t1
    csrr t2, 0x3A0
    bne  t2, x0, ppmp_fail

    li   t4, 16
    li   t1, 0x03030303             # R=1, W=1
    csrw 0x3A0, t1
    csrr t2, 0x3A0
    li   t3, 0x03030303
    bne  t2, t3, ppmp_fail

    # ---- CHECK 17: the four bytes of ONE word are independent entries ----
    #   e0 = 0x18 NAPOT ---   e1 = 0x1B NAPOT RW
    #   e2 = 0x19 NAPOT R-    e3 = 0x1F NAPOT RWX
    li   t4, 17
    li   t1, 0x1F191B18
    csrw 0x3A0, t1
    csrr t2, 0x3A0
    li   t3, 0x1F191B18
    bne  t2, t3, ppmp_fail

    # ---- CHECK 18: an UNLOCKED entry clears again (no sticky bits) ----
    li   t4, 18
    csrw 0x3A0, x0
    csrr t2, 0x3A0
    bne  t2, x0, ppmp_fail

    # =====================================================================
    # CHECK 19-22 — pmpaddr0-3 are four INDEPENDENT registers (a shared or
    # aliased decode would show up as the last write winning everywhere).
    # =====================================================================
    li   t4, 19
    li   t1, 0x11111111
    csrw 0x3B0, t1
    li   t1, 0x22222222
    csrw 0x3B1, t1
    li   t1, 0x03333333
    csrw 0x3B2, t1
    li   t1, 0x04444444
    csrw 0x3B3, t1
    csrr t2, 0x3B0
    li   t3, 0x11111111
    bne  t2, t3, ppmp_fail

    li   t4, 20
    csrr t2, 0x3B1
    li   t3, 0x22222222
    bne  t2, t3, ppmp_fail

    li   t4, 21
    csrr t2, 0x3B2
    li   t3, 0x03333333
    bne  t2, t3, ppmp_fail

    li   t4, 22
    csrr t2, 0x3B3
    li   t3, 0x04444444
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 23-25 — pmpcfg1 / pmpaddr4-7 (entries 4-7): the SECOND cfg word
    # is a distinct register with its own four entries.
    #   e4 = 0x0F TOR RWX   e5 = 0x19 NAPOT R-
    #   e6 = 0x1B NAPOT RW  e7 = 0x7F -> 0x1F NAPOT RWX
    # =====================================================================
    li   t4, 23
    li   t1, 0x7F1B190F
    csrw 0x3A1, t1
    csrr t2, 0x3A1
    li   t3, 0x1F1B190F
    bne  t2, t3, ppmp_fail

    li   t4, 24
    li   t1, 0xFFFFFFFF
    csrw 0x3B4, t1
    csrr t2, 0x3B4
    li   t3, 0x3FFFFFFF
    bne  t2, t3, ppmp_fail

    li   t4, 25
    li   t1, 0x05555555
    csrw 0x3B7, t1
    csrr t2, 0x3B7
    li   t3, 0x05555555
    bne  t2, t3, ppmp_fail

#if CORE_PMP_ENTRIES >= 16
    # =====================================================================
    # CHECK 26-29 — pmpcfg2 / pmpaddr8-11 (entries 8-11). On a PMP_ENTRIES=8
    # build these addresses are still LEGAL but have no storage (WARL zero),
    # so the section is compiled out there.
    #   e8 = 0x07 OFF RWX (A=OFF: permissions stored, region never matches)
    #   e9 = 0x08 TOR ---   e10 = 0x10 NA4 ---   e11 = 0x13 NA4 RW
    # =====================================================================
    li   t4, 26
    li   t1, 0x13100807
    csrw 0x3A2, t1
    csrr t2, 0x3A2
    li   t3, 0x13100807
    bne  t2, t3, ppmp_fail

    li   t4, 27
    li   t1, 0xFFFFFFFF
    csrw 0x3B8, t1
    csrr t2, 0x3B8
    li   t3, 0x3FFFFFFF
    bne  t2, t3, ppmp_fail

    li   t4, 28
    li   t1, 0x0ABCDEF0
    csrw 0x3BB, t1
    csrr t2, 0x3BB
    li   t3, 0x0ABCDEF0
    bne  t2, t3, ppmp_fail

    # ---- CHECK 29: the LAST entry's address register is live ----
    li   t4, 29
    li   t1, 0x2AAAAAAA
    csrw 0x3BF, t1
    csrr t2, 0x3BF
    li   t3, 0x2AAAAAAA
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 30-32 — CSRRS / CSRRC read-modify-write forms reach the bank and
    # obey the same WARL mask (a set/clear that bypassed the mask would store
    # reserved bits). The masks deliberately EXCLUDE bit 7: setting L on entry
    # 8 here would lock a LOW entry for the rest of the simulation.
    # =====================================================================
    li   t4, 30
    csrw 0x3A2, x0
    li   t1, 0x0000007F             # every bit of entry 8's byte EXCEPT L
    csrs 0x3A2, t1
    csrr t2, 0x3A2
    li   t3, 0x0000001F             # A=NAPOT|X|W|R ; bits 6:5 dropped
    bne  t2, t3, ppmp_fail

    li   t4, 31
    li   t1, 0x00000018             # clear entry 8's A field -> A=OFF
    csrc 0x3A2, t1
    csrr t2, 0x3A2
    li   t3, 0x00000007
    bne  t2, t3, ppmp_fail

    li   t4, 32
    csrw 0x3A2, x0
    csrr t2, 0x3A2
    bne  t2, x0, ppmp_fail

    # =====================================================================
    # ===================  LOCK SECTION — ALWAYS LAST  ====================
    # Everything below sets L bits, and a PMP lock is released ONLY by
    # hardware reset. Confined to entries 12-15 (pmpcfg3) so entries 0-11
    # stay reprogrammable for any later PMP test in the same image.
    # =====================================================================

    # ---- CHECK 33-36: seed the four addresses BEFORE anything is locked ----
    li   t4, 33
    li   t1, 0x00000111
    csrw 0x3BC, t1
    csrr t2, 0x3BC
    li   t3, 0x00000111
    bne  t2, t3, ppmp_fail

    li   t4, 34
    li   t1, 0x00000222
    csrw 0x3BD, t1
    csrr t2, 0x3BD
    li   t3, 0x00000222
    bne  t2, t3, ppmp_fail

    li   t4, 35
    li   t1, 0x00000333
    csrw 0x3BE, t1
    csrr t2, 0x3BE
    li   t3, 0x00000333
    bne  t2, t3, ppmp_fail

    li   t4, 36
    li   t1, 0x00000444
    csrw 0x3BF, t1
    csrr t2, 0x3BF
    li   t3, 0x00000444
    bne  t2, t3, ppmp_fail

    # ---- CHECK 37: arm the locks in ONE pmpcfg3 write ----
    #   e12 = 0x9B  L=1, A=NAPOT, W|R   -> locks cfg12 + pmpaddr12
    #                                      (A is NOT TOR, so pmpaddr11 is FREE)
    #   e13 = 0x0B  L=0, A=TOR,   W|R   -> stays writable
    #   e14 = 0x89  L=1, A=TOR,   R     -> locks cfg14 + pmpaddr14
    #                                      AND write-locks pmpaddr13
    #   e15 = 0x00  OFF, unlocked
    li   t4, 37
    li   t1, 0x00890B9B
    csrw 0x3A3, t1
    csrr t2, 0x3A3
    li   t3, 0x00890B9B
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 38 — PER-BYTE LOCK FILTERING inside ONE pmpcfg word write.
    # Writing all-zeros to pmpcfg3 must clear ONLY the unlocked bytes:
    #   e12 (locked) keeps 0x9B, e13 -> 0x00, e14 (locked) keeps 0x89,
    #   e15 -> 0x00.
    # A whole-word lock (any byte locked => the word is immutable) would read
    # 0x00890B9B here; a missing lock would read 0x00000000.
    # =====================================================================
    li   t4, 38
    csrw 0x3A3, x0
    csrr t2, 0x3A3
    li   t3, 0x0089009B
    bne  t2, t3, ppmp_fail

    # ---- CHECK 39: unlocked bytes still take a NEW value in the same word ---
    #   0x7F7F7F7F -> e12 keeps 0x9B, e13 = 0x1F, e14 keeps 0x89, e15 = 0x1F
    li   t4, 39
    li   t1, 0x7F7F7F7F
    csrw 0x3A3, t1
    csrr t2, 0x3A3
    li   t3, 0x1F891F9B
    bne  t2, t3, ppmp_fail

    # ---- CHECK 40: a locked cfg byte resists the read-modify-write forms ---
    #   csrc of the L bit in every byte: e12/e14 ignore it, e13/e15 clear it.
    li   t4, 40
    li   t1, 0x80808080
    csrc 0x3A3, t1
    csrr t2, 0x3A3
    li   t3, 0x1F891F9B             # unchanged: e13/e15 already had L=0
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 41 — pmpaddr12 is IMMUTABLE (entry 12's own L bit).
    # =====================================================================
    li   t4, 41
    li   t1, 0xFFFFFFFF
    csrw 0x3BC, t1
    csrr t2, 0x3BC
    li   t3, 0x00000111
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 42 — pmpaddr13 is TOR-LOCKED BY ENTRY 14 even though entry 13
    # itself is unlocked: entry 14 is L=1 with A=TOR, and pmpaddr13 is that
    # region's BASE. This is the rule a naive "only my own L bit" lock misses.
    # =====================================================================
    li   t4, 42
    li   t1, 0xFFFFFFFF
    csrw 0x3BD, t1
    csrr t2, 0x3BD
    li   t3, 0x00000222
    bne  t2, t3, ppmp_fail

    # ---- CHECK 43: pmpaddr14 immutable (entry 14's own L bit) ----
    li   t4, 43
    li   t1, 0xFFFFFFFF
    csrw 0x3BE, t1
    csrr t2, 0x3BE
    li   t3, 0x00000333
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 44 — THE DISCRIMINATOR for the TOR clause: entry 12 is LOCKED but
    # its A is NAPOT, not TOR, so pmpaddr11 must remain FREELY WRITABLE. An
    # implementation that write-locked the predecessor of EVERY locked entry
    # (ignoring the A=TOR condition) fails right here.
    # =====================================================================
    li   t4, 44
    li   t1, 0x01234567
    csrw 0x3BB, t1
    csrr t2, 0x3BB
    li   t3, 0x01234567
    bne  t2, t3, ppmp_fail

    # =====================================================================
    # CHECK 45/46 — A WRITTEN-BUT-UNLOCKED ENTRY CAN STILL BE CHANGED.
    # entry 15 is unlocked and has no successor, so nothing can TOR-lock it:
    # its address takes a new value (WARL-masked) and then goes back.
    # =====================================================================
    li   t4, 45
    li   t1, 0xFFFFFFFF
    csrw 0x3BF, t1
    csrr t2, 0x3BF
    li   t3, 0x3FFFFFFF
    bne  t2, t3, ppmp_fail

    li   t4, 46
    li   t1, 0x00000444
    csrw 0x3BF, t1
    csrr t2, 0x3BF
    li   t3, 0x00000444
    bne  t2, t3, ppmp_fail

    # ---- CHECK 47: and the unlocked CFG byte of entry 13 changes too ----
    #   0x00000300 -> e12 keeps 0x9B, e13 = 0x03, e14 keeps 0x89, e15 = 0x00
    #   (the byte lanes are entry 4n+j at bits 8j+7:8j, so entry 13 is 15:8)
    li   t4, 47
    li   t1, 0x00000300
    csrw 0x3A3, t1
    csrr t2, 0x3A3
    li   t3, 0x0089039B
    bne  t2, t3, ppmp_fail
#endif  /* CORE_PMP_ENTRIES >= 16 */

    # =====================================================================
    # RESTORE what CAN be restored, so a later PMP test in the same image
    # starts from a clean LOW half: pmpcfg0/1/2 back to zero (every entry
    # 0-11 is unlocked, so all three really clear) and the low addresses
    # zeroed. Entries 12-15 keep their locks — by design; PMP locks survive
    # until hardware reset, which is exactly why the lock checks live here at
    # the end and nowhere else.
    # =====================================================================
    li   t4, 48
    csrw 0x3A0, x0
    csrw 0x3A1, x0
#if CORE_PMP_ENTRIES >= 16
    csrw 0x3A2, x0
#endif
    csrw 0x3B0, x0
    csrw 0x3B1, x0
    csrw 0x3B2, x0
    csrw 0x3B3, x0
    csrr t2, 0x3A0
    bne  t2, x0, ppmp_fail
    csrr t2, 0x3A1
    bne  t2, x0, ppmp_fail
    csrr t2, 0x3B0
    bne  t2, x0, ppmp_fail

    # =====================================================================
    # CHECK 49 — THE 0x3A4 LANDMINE PIN (p3e_entry_seeds.repro.txt item 3).
    # 0x3A4 is pmpcfg4 on RV64 and DOES NOT EXIST on RV32 — an UNKNOWN CSR
    # address ADJACENT to the live pmpcfg bank. A write to it must take the
    # illegal-instruction trap (cause 2) and commit NOTHING: pmpcfg0 keeps
    # its sentinel. This is the scenario the P3-entry
    # `csr_valid AND csr_addr_valid` gate exists for: with the gate seeded
    # away AND a cfg write arm decoded wider than its exact address
    # (p3e_widearm_demo.patch models that slip), the trapping write LANDS in
    # entry 0 and this check fires — the two-part demonstration in the
    # repro. Standard mode for exactly the faulting instruction (a legacy
    # illegal dead-ends in TRAP_STATE).
    # =====================================================================
    li   t4, 49
    li   t1, 0x00000019             # entry 0 sentinel: NAPOT | R (unlocked)
    csrw 0x3A0, t1
    la   t1, ppmp_skip
    csrw 0x305, t1                  # mtvec = the +4 skip handler
    csrw 0x300, x0                  # MIE = 0: nothing async in the window
    li   s5, 0
    csrw 0x7C0, x0                  # LEGACY = 0 — standard delivery ON
    li   t1, 0xBADC0DE5
    csrw 0x3A4, t1                  # UNKNOWN CSR: traps, handler skips +4
    li   s5, 1                      # reached only via the handler resume
    li   t1, 1
    csrw 0x7C0, t1                  # LEGACY back to 1 IMMEDIATELY
    li   t3, 1
    bne  s5, t3, ppmp_fail          # the trap resumed at +4
    csrr t2, 0x342                  # mcause == 2 (illegal instruction)
    li   t3, 2
    bne  t2, t3, ppmp_fail
    csrr t2, 0x3A0                  # the sentinel survived: NO commit
    li   t3, 0x00000019
    bne  t2, t3, ppmp_fail
    csrw 0x3A0, x0                  # restore entry 0 + a quiet mstatus
    csrw 0x300, x0
    csrr t2, 0x3A0
    bne  t2, x0, ppmp_fail

    .option pop

    RVTEST_PASS

    # ---- CHECK 49's mtvec target: skip the faulting instruction (+4).
    # Reached only through the standard-mode trap; never by fall-through
    # (RVTEST_PASS above is a spin loop).
    .align 2
ppmp_skip:
    .option push
    .option arch, +zicsr
    csrr t2, 0x341                  # mepc = the faulting csrw
    addi t2, t2, 4                  # norvc build: always +4
    csrw 0x341, t2
    mret
    .option pop

#else
    # OFF build: the twenty P3 addresses are unknown CSRs (illegal instruction,
    # terminal TRAP_STATE). privpmpcs must only ever be run on a staged
    # -DCORE_ENABLE_PMP build; reaching here means it was not.
    li   t4, 0
    j    ppmp_fail
#endif

ppmp_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
