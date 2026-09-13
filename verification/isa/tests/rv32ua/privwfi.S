# See LICENSE for license details.

# VestaRV: WFI, off-polarity poison and on-polarity positive arm
# WFI is SYSTEM imm12 = 0x105, funct3 = 000, encoding 0x10500073, and this file carries both polarities in the extjvt.S ifdef shape. The encoding is emitted as a raw .word in BOTH arms, so no assembler -march question can change which bits the core sees. t4 carries the CHECK ID at every comparison in the positive arm.
# With CORE_ENABLE_TRAPCSR defined, WFI is LEGAL. It is TRAPCSR-scope rather than UMODE-scope, so this arm runs on a trapCsr-only build too, and it proves the standard wake rule: wake when (mip and mie) is nonzero REGARDLESS of mstatus.MIE, and when the interrupt is takeable vector, else resume at pc+4. The test arms mie.MSIE and raises CLINT msip[0] BEFORE the WFI, so the source is already pending and the WFI must fall straight through, while mstatus.MIE stays 0 so nothing may be delivered, which makes "resumed at WFI+4 with no trap" the exact observable and the whole arm bounded. Standard delivery is selected first, which pins the legacy irq_handler in IDLE; otherwise the msip raised here would vector through the legacy IVT slot 83, which a plain rv32ua image does not populate.
# Without it, the encoding is an ILLEGAL INSTRUCTION, since with ENABLE_TRAPCSR off the SYSTEM PRIV arm does not exist and every funct3 = 000 SYSTEM encoding falls to valid_funct = '0'. RUN THAT ARM ONLY UNDER THE TRAP-WATCHING HARNESS (behavioral_mp_stripped/run_extoff.sh with trap_watch.tcl), never in the default runner array, which would hang on the terminal TRAP_STATE. Surviving past the encoding means the gating is broken and is an explicit FAIL.
# BEWARE: a comment line whose first token after the hash is a preprocessor keyword IS a directive to cpp, and writing one here has cost a build before.
# WFI in U-mode with mstatus.TW set is proven separately, by privucsr's U-mode poison sweep.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # base-ISA sanity: prove the core runs before the WFI encoding
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pvwfi_fail

#ifdef CORE_ENABLE_TRAPCSR

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s1, 0                      # "a trap was delivered" witness (must stay 0)
    li   s3, 0                      # "resumed after WFI" witness
    li   s0, 0x00005000             # CLINT msip[hart 0]

    # =====================================================================
    # CHECK 1 -- arm mtvec. Nothing in this arm SHOULD trap; the handler
    # exists purely so that an unexpected trap (e.g. WFI still decoding
    # illegal) is a BOUNDED, localisable FAIL instead of a dead end.
    # =====================================================================
    li   t4, 1
    la   s2, pvwfi_handler
    csrw 0x305, s2
    csrr t2, 0x305
    bne  t2, s2, pvwfi_fail

    # ---- CHECK 2: mstatus.MIE = 0 (nothing may be DELIVERED), mie.MSIE = 1 ----
    li   t4, 2
    csrw 0x300, x0
    li   t1, 0x00000008
    csrw 0x304, t1
    csrr t2, 0x304
    li   t3, 0x00000008
    bne  t2, t3, pvwfi_fail

    # ---- CHECK 3: STANDARD delivery (also pins the legacy irq_handler) ----
    li   t4, 3
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pvwfi_fail

    # =====================================================================
    # CHECK 4 -- raise msip[0] and wait (BOUNDED) until mip.MSIP mirrors it.
    # The level crosses the registered tile boundary, so poll rather than
    # assume. 4096 iterations at mclk = 24 MHz is the ~1 ms class (shspin
    # uses 4096/20000) -- far inside the 100 ms tb watchdog.
    # =====================================================================
    li   t4, 4
    li   t1, 1
    sw   t1, 0(s0)
    li   t2, 4096
pvwfi_wait_mip:
    csrr t0, 0x344
    andi t0, t0, 0x8
    bnez t0, pvwfi_armed
    addi t2, t2, -1
    bnez t2, pvwfi_wait_mip
    j    pvwfi_fail                 # mip never mirrored msip
pvwfi_armed:

    # =====================================================================
    # THE WFI. (mip and mie) /= 0 already holds, so the standard wake rule
    # resumes IMMEDIATELY at WFI+4; mstatus.MIE = 0 means no trap is taken.
    # =====================================================================
    .word 0x10500073                # WFI -- legal from P2, must NOT trap
    li   s3, 0x000000C3             # execution MUST resume exactly here

    li   t4, 5                      # resumed at WFI+4
    li   t3, 0x000000C3
    bne  s3, t3, pvwfi_fail

    li   t4, 6                      # and NOTHING trapped: WFI really is legal
    bne  s1, x0, pvwfi_fail

    # =====================================================================
    # RESTORE, in the ONE safe order: clear the source FIRST (bounded wait
    # for mip to drop), then mie, and only THEN go back to LEGACY delivery --
    # re-enabling the legacy irq_handler while msip is still high would
    # vector through IVT slot 83, which this image does not populate.
    # =====================================================================
    li   t4, 7
    sw   x0, 0(s0)
    li   t2, 4096
pvwfi_wait_clr:
    csrr t0, 0x344
    andi t0, t0, 0x8
    beqz t0, pvwfi_quiet
    addi t2, t2, -1
    bnez t2, pvwfi_wait_clr
    j    pvwfi_fail                 # msip never cleared
pvwfi_quiet:
    csrw 0x304, x0                  # mie = 0
    csrw 0x300, x0                  # mstatus = 0
    li   t1, 0x00000001
    csrw 0x7C0, t1                  # back to LEGACY delivery

    li   t4, 8
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pvwfi_fail
    csrr t2, 0x304
    bne  t2, x0, pvwfi_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler. Placed AFTER the RVTEST_PASS spin loop, so it can
    # only be reached by a hardware trap. It records that a trap happened
    # and skips the faulting 4-byte instruction, so a regression is a
    # bounded compare-and-branch FAIL (CHECK 6) rather than a dead end.
    # =====================================================================
    .align 2
pvwfi_handler:
    li   s1, 0x0000DEAD
    csrr t5, 0x341
    addi t5, t5, 4
    csrw 0x341, t5
    mret

    .option pop

#else
    # OFF build: 0x10500073 must take the ILLEGAL-INSTRUCTION trap (terminal
    # TRAP_STATE). Run only under the trap-watching stripped harness.
    .word 0x10500073                # WFI -- MUST trap illegal
    j    pvwfi_fail                 # reached only if it did NOT trap -> FAIL
#endif

pvwfi_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
