# See LICENSE for license details.

#*****************************************************************************
# shcmt.S  (X3 Zcmt — compressed table jump + jvt CSR directed functional test)
#-----------------------------------------------------------------------------
# Build-time dispatch on CORE_ENABLE_ZCMT (explicit -DCORE_ENABLE_ZCMT at ON).
# Hart 0 only (tiles park).
#
#   OFF (#else): base sanity + PASS. cm.jt/cm.jalt and the jvt CSR are illegal
#       here; the stub emits none of them (image bit-identical to a base build).
#
#   ON  (#ifdef): build a jump-vector table in TCM, set jvt via csrw, fence.i,
#       then:
#         * cm.jt index=3   (index<32, no link) -> control reaches entry[3]'s
#           target AND ra is UNCHANGED.
#         * cm.jalt index=40 (index>=32, links) -> control reaches entry[40]'s
#           target AND ra == the return site (cm.jalt address + 2).
#
# gas 13.2 has no cm.* mnemonics nor a jvt CSR name; cm.jt/jalt are raw 16-bit
# `.short's (C2 op=10, funct3=101, 12:10=000, index at bits 9:2) and jvt is
# csrw to the numeric address 0x017.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, cmt_pass            # single-hart test

#ifdef CORE_ENABLE_ZCMT
    # base sanity
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cmt_fail

    # ---- build the jump-vector table (entries are 32-bit target addresses) ----
    la   t0, jvt_table           # 64-byte aligned (.align 6)
    la   t1, jt_target
    sw   t1, 12(t0)              # entry[3]  (index 3 * 4)
    la   t1, jalt_target
    sw   t1, 160(t0)            # entry[40] (index 40 * 4)
    # boundary entries: index 31 (highest cm.jt, no link) and 32 (lowest cm.jalt, link)
    la   t1, jt31_target
    sw   t1, 124(t0)            # entry[31] (31 * 4)
    la   t1, jalt32_target
    sw   t1, 128(t0)            # entry[32] (32 * 4)

    # ---- jvt WARL base-mask (Zcmt): a deliberately UNALIGNED write must be
    #      forced to the 64B-aligned base by the hardware (mode[5:0]=0, base low
    #      6 bits masked). t0 is already 64B-aligned (.align 6), so ORing 0x3f in
    #      and reading back MUST yield the aligned t0 again. With the base-mask
    #      dropped (negctrl x3_zcmt_jvtmask) the readback keeps the low bits ->
    #      != t0 -> this bne fires (bounded FAIL). ----
    .option push
    .option arch, +zicsr
    ori  t3, t0, 0x3f           # a base with the low 6 bits deliberately set
    csrw 0x017, t3
    csrr t2, 0x017
    bne  t2, t0, cmt_fail        # HW must have WARL-masked [5:0] back to the aligned base
    # program the aligned base for the actual jumps (the masked value == t0)
    csrw 0x017, t0
    csrr t2, 0x017
    .option pop
    bne  t2, t0, cmt_fail        # jvt readback must equal the aligned base

    .option push
    .option arch, +zifencei
    fence.i
    .option pop                      # ordering between the JVT write and the jump

    # ---- cm.jt index=3 (no link): ra must be UNCHANGED ----
    li   ra, 0x7777AAAA          # ra sentinel
    .short 0xA00E                # cm.jt 3 -> mem[jvt+12] = jt_target
    j    cmt_fail                # must not fall through
jt_target:
    li   t2, 0x7777AAAA
    bne  ra, t2, cmt_fail        # cm.jt must NOT write ra

    # ---- cm.jalt index=40 (link): ra must be the return site (addr+2) ----
    li   ra, 0xDEAD
jalt_site:
    .short 0xA0A2                # cm.jalt 40 -> mem[jvt+160]=jalt_target; ra=jalt_site+2
    j    cmt_fail
jalt_target:
    la   t2, jalt_site
    addi t2, t2, 2               # the 16-bit cm.jalt is 2 bytes
    bne  ra, t2, cmt_fail        # ra must be the return site

    # ---- BOUNDARY (X3 Stage-D red-team D2): the index value ALONE picks the
    #      mnemonic — index<32 = cm.jt (no link), index>=32 = cm.jalt (links ra).
    #      shcmt formerly tested only index=3 and index=40, so a seed that moves
    #      the link threshold by one (>=32 -> >=31 or >=33) slipped through. These
    #      two cases pin the exact 31/32 boundary. ----
    # cm.jt index=31 (highest no-link): ra must be UNCHANGED
    li   ra, 0x31313131
    .short 0xA07E              # cm.jt 31 -> mem[jvt+124] = jt31_target
    j    cmt_fail
jt31_target:
    li   t2, 0x31313131
    bne  ra, t2, cmt_fail        # index=31 (<32) must NOT link ra
    # cm.jalt index=32 (lowest link): ra must be the return site (addr+2)
    li   ra, 0x32320000
jalt32_site:
    .short 0xA082              # cm.jalt 32 -> mem[jvt+128]=jalt32_target; ra=jalt32_site+2
    j    cmt_fail
jalt32_target:
    la   t2, jalt32_site
    addi t2, t2, 2
    bne  ra, t2, cmt_fail        # index=32 (>=32) must link ra=site+2

    j    cmt_pass

#else
    # FEATURE OFF: cm.jt/jalt + jvt illegal — trivial pass, bit-identical image.
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cmt_fail
    j    cmt_pass
#endif

cmt_pass:
    RVTEST_PASS
cmt_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 6                       # 64-byte aligned jvt base
jvt_table: .fill 64, 4, 0        # 64 entries (covers index 40)
RVTEST_DATA_END
