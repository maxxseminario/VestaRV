# See LICENSE for license details.

# VestaRV: Zcb extension probe
# BUILD-TIME DISPATCH, not runtime misa dispatch, because Zcb HAS NO misa BIT, C being advertised already, and because this core DEAD-ENDS an illegal instruction in TRAP_STATE with the PC frozen and no software trap recovery, so a try-and-recover runtime probe is impossible. With CORE_ENABLE_ZCB defined every Zcb encoding executes and its architectural result is checked; without it the file does base-ISA sanity and passes, because the pass/fail runner cannot observe a dead-end trap as a pass and the default Zcb-off suite must stay green. The genuine "Zcb off means illegal-instruction trap" behaviour is proven separately by running THIS image built ON against Zcb-OFF RTL under trap_watch.tcl.
# THE MACRO IS PASSED DIRECTLY, NEVER THROUGH #include "MemoryMap.h": on the default rv32ua compile line that name resolves to the frozen Myshkin header, which includes <bits.h>, not on the ISA-test include path, and fails to preprocess. So the OFF build is the plain compile line and the ON build adds only -DCORE_ENABLE_ZCB, with the shared Makefile unmodified.
# All Zcb encodings are hand-emitted with .2byte, since gas 13.2 has no Zcb mnemonics and no `_zcb` march, so the file assembles under the suite base -march. Whole-file norvc keeps every other instruction 32-bit, and the only 16-bit words in the image are the probes below.

# The 16-bit encodings, transcribed from riscv-opcodes rv_zcb and the ratified Zc* v1.0
# spec and cross-checked by assembling the 32-bit base operations:
#   c.lbu  rd',u(rs1')   100 000 rs1' u6 u5 rd'  00   (uimm[1] = i5, uimm[0] = i6)
#   c.lhu  rd',u(rs1')   100 001 rs1'  0 u5 rd'  00   (uimm[1] = i5, uimm[0] = 0)
#   c.lh   rd',u(rs1')   100 001 rs1'  1 u5 rd'  00
#   c.sb   rs2',u(rs1')  100 010 rs1' u6 u5 rs2' 00
#   c.sh   rs2',u(rs1')  100 011 rs1'  0 u5 rs2' 00
#   c.zext.b rd'         100 111 rd'  11 000 01
#   c.sext.b rd'         100 111 rd'  11 001 01   (Zbb)
#   c.zext.h rd'         100 111 rd'  11 010 01   (Zbb)
#   c.sext.h rd'         100 111 rd'  11 011 01   (Zbb)
#   c.not    rd'         100 111 rd'  11 101 01
#   c.mul  rd',rs2'      100 111 rd'  10 rs2' 01  (Zmmul/M)
# Every register used is in x8-x15, the compressed rd'/rs1'/rs2' range: s0, a2, a3, a4, a5.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extzcb_fail

#ifdef CORE_ENABLE_ZCB
    # =====================================================================
    # FEATURE ON: execute the real Zcb encodings and CHECK results -> PASS.
    # =====================================================================

    # -------- loads: source word = 0xAABBCCDD (halves have bit15 set) -----
    la   s0, extzcb_src

    .2byte 0x8010                 # c.lbu a2,0(s0)  -> 0x000000DD
    li   a1, 0x000000DD
    bne  a2, a1, extzcb_fail
    .2byte 0x8070                 # c.lbu a2,3(s0)  -> 0x000000AA
    li   a1, 0x000000AA
    bne  a2, a1, extzcb_fail

    # c.lhu zero-extends; the loaded halfword 0xCCDD has bit15=1, so this
    # value DISTINGUISHES c.lhu (0x0000CCDD) from a (mis-seeded) c.lh
    # (0xFFFFCCDD) — the negative control relies on exactly this.
    .2byte 0x8410                 # c.lhu a2,0(s0)  -> 0x0000CCDD
    li   a1, 0x0000CCDD
    bne  a2, a1, extzcb_fail
    .2byte 0x8430                 # c.lhu a2,2(s0)  -> 0x0000AABB
    li   a1, 0x0000AABB
    bne  a2, a1, extzcb_fail
    # c.lh sign-extends: halfword 0xAABB has bit15=1 -> 0xFFFFAABB
    .2byte 0x8470                 # c.lh  a2,2(s0)  -> 0xFFFFAABB
    li   a1, 0xFFFFAABB
    bne  a2, a1, extzcb_fail

    # -------- stores: target word preset 0x11223344, guarded lanes -------
    la   s0, extzcb_dst
    li   a3, 0x000000EE
    .2byte 0x8854                 # c.sb a3,1(s0) -> byte1=EE -> 0x1122EE44
    lw   a1, 0(s0)
    li   t0, 0x1122EE44
    bne  a1, t0, extzcb_fail
    li   a4, 0x0000BEEF
    .2byte 0x8C38                 # c.sh a4,2(s0) -> hi half=BEEF -> 0xBEEFEE44
    lw   a1, 0(s0)
    li   t0, 0xBEEFEE44
    bne  a1, t0, extzcb_fail

    # -------- unary ops --------------------------------------------------
    li   a5, 0x12345678
    .2byte 0x9FE1                 # c.zext.b a5 -> 0x00000078
    li   a1, 0x00000078
    bne  a5, a1, extzcb_fail

    li   a5, 0x0F0F0F0F
    .2byte 0x9FF5                 # c.not a5 -> 0xF0F0F0F0
    li   a1, 0xF0F0F0F0
    bne  a5, a1, extzcb_fail

    # Zbb-gated forms (base op traps illegal when ENABLE_BITMANIP off)
    li   a5, 0x1234ABCD
    .2byte 0x9FE9                 # c.zext.h a5 -> 0x0000ABCD
    li   a1, 0x0000ABCD
    bne  a5, a1, extzcb_fail
    li   a5, 0x000000FF
    .2byte 0x9FE5                 # c.sext.b a5 -> 0xFFFFFFFF
    li   a1, 0xFFFFFFFF
    bne  a5, a1, extzcb_fail
    li   a5, 0x0000ABCD
    .2byte 0x9FED                 # c.sext.h a5 -> 0xFFFFABCD (bit15 set)
    li   a1, 0xFFFFABCD
    bne  a5, a1, extzcb_fail

    # MUL-gated form (base MUL traps illegal when ENABLE_MUL off)
    li   a4, 6
    li   a5, 7
    .2byte 0x9F5D                 # c.mul a4,a5 -> a4 = 42
    li   a1, 42
    bne  a4, a1, extzcb_fail

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF (default Zcb-off build): base ISA verified above. A Zcb
    # encoding here would dead-end in TRAP_STATE and could never report PASS,
    # so the pass/fail suite takes this non-trapping path. The off->illegal
    # trap is proven by running the ON image on the Zcb-off RTL (trap_watch).
    # =====================================================================
    RVTEST_PASS
#endif

extzcb_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
    .align 2
extzcb_src: .word 0xAABBCCDD
extzcb_dst: .word 0x11223344
RVTEST_DATA_END
