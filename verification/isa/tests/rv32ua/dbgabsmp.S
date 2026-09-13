# See LICENSE for license details.

# VestaRV: abstract-command architectural-effect test
# NEEDS A HARNESS: ./xrun_dbg.sh rv32ua-p-dbgabsmp dbg_abs.tcl. An abstract command has two observable faces and a DM can get one right while getting the other wrong: the DMI face, where data0 returns the right value with cmderr 0 and busy cleared, which dbg_abs.tcl checks, and the ARCHITECTURAL face, where the victim's registers and memory really changed and really did not change in any other way. THIS FILE IS THE ARCHITECTURAL FACE: the victim sets up known state, parks, is worked on by the debugger, resumes, reads back its own state with ordinary instructions and publishes what it found, and hart 0 grades it. Neither half can be forged by the other.
# Five things proved. (1) An abstract GPR READ of x9 must return GPR_MAGIC AND must not be destructive, which OBS_S1 catches if the DM's dscratch save and restore drops a register. (2) An abstract GPR WRITE of x18 must land in s2, which starts at 0. (3) An abstract CSR read and write of mscratch, chosen because it is architecturally inert. (4) A PROGBUF MEMORY ROUND TRIP, since there is no access-memory abstract command on this chip and cmdtype 2 returns NOT_SUPPORTED by design: the harness points a6 and a7 at MEM_SRC and MEM_DST by abstract writes, loads progbuf0 with lw and progbuf1 with sw, and issues a postexec, and the victim reads MEM_DST back in band so the word really landed in the RAM the hart sees. That also exercises impebreak, since progbufsize is 2 and the sequence needs a third word to return. (5) THE EXCEPTION cmderr: an abstract read of an unimplemented CSR must set cmderr EXCEPTION and leave the hart HALTED, and this file's contribution is that everything after it still works, so the exception leg is issued BEFORE the resume and a correct run still reaches DONE.
# THE VICTIM'S PARK NEEDS REGISTER DISCIPLINE. It spins reading the shared word REL, which the harness plants; the loop body recomputes its address with `li` every round and holds no live register, so the debugger's visits, which clobber t-registers, a6, a7 and whatever the DM's own sequence uses, cannot perturb it. IT TOUCHES NO s0, because the reference sequence saves s0 to dscratch0 and a victim that depended on s0 could not distinguish a save-and-restore failure from a clobber.
# Verdicts: a0 = 0xCAFEBABE means every abstract face landed architecturally. a1 = 0x0D220001 a shared word did not read back; 0x0D220002 base-ISA sanity failed; 0x0D220003 the victim never finished, with a2 = PROG naming how far it got (1 parked, 2 released), which is the expected result under a plain batch run and the finding under dbg_abs.tcl; 0x0D220004 the abstract GPR write did not land; 0x0D220005 the abstract CSR write did not land; 0x0D220006 the progbuf round trip did not move the word; 0x0D220007 an abstract read was DESTRUCTIVE, since s1 no longer holds GPR_MAGIC; 0x0D220008 MEM_SRC was corrupted, so the progbuf wrote the wrong way round.
# NEGATIVE CONTROL -DDBGABS_NC_SELF: the victim performs on itself exactly the architectural effects the debugger would have performed and releases itself instead of waiting for REL, so every publish, hart 0's assertion chain and the verdict path run for real. A pass on that arm proves the instrument is LIVE. It makes no claim about the DM and must never be quoted as a result.
# N-agnostic: one victim, hart 1, at any NHARTS, and no shared word is indexed by hartid. Shared words, in the D-series debug acceptance band 0x10050-0x1007C, reused with this file's meanings under the one-image-per-sim rule: 0x10050 READY, 0x10054 REL (the harness plants 1 to release the victim), 0x10058 DONE, 0x1005C OBS_S2, 0x10060 OBS_MSCR, 0x10064 MEM_SRC, 0x10068 MEM_DST, 0x1006C OBS_S1, 0x10070 PROG.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_READY     0x10050
#define SH_REL       0x10054
#define SH_DONE      0x10058
#define SH_OBS_S2    0x1005C
#define SH_OBS_MSCR  0x10060
#define SH_MEM_SRC   0x10064
#define SH_MEM_DST   0x10068
#define SH_OBS_S1    0x1006C
#define SH_PROG      0x10070

#define GPR_MAGIC    0x0AB50001
#define CSR_MAGIC    0x0AB50002
#define MEM_MAGIC    0x0AB50003
#define ABS_WR_MAGIC 0x0AB5FEED     /* the harness abstract-writes this to s2 */
#define CSR_WR_MAGIC 0x0AB5BEEF     /* ...and this to mscratch               */
#define DONE_MAGIC   0x0AB5D0E5

#define TILE_WORDS   1024
#define ARM_BUDGET   40000

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
    li   a1, 0x0D220001
    li   t0, SH_READY
    li   t1, 12
da_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, da_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, da_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D220002
    bne  t2, t3, da_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for the victim's whole programme.  DONE is written LAST,
    # so one word means "released, read back and published".
    # ~40000 rounds of one shared load ~= 20 ms, inside the 100 ms watchdog.
    # ==================================================================
    li   s4, SH_DONE
    li   s5, DONE_MAGIC
    li   t6, ARM_BUDGET
da_wait:
    lw   t2, 0(s4)
    beq  t2, s5, da_check
    addi t6, t6, -1
    bnez t6, da_wait
    li   t0, SH_PROG
    lw   a2, 0(t0)
    li   a1, 0x0D220003
    j    da_fail

da_check:
    li   t0, SH_OBS_S2              # 2. the abstract GPR WRITE
    lw   a2, 0(t0)
    li   a3, ABS_WR_MAGIC
    li   a1, 0x0D220004
    bne  a2, a3, da_fail

    li   t0, SH_OBS_MSCR            # 3. the abstract CSR WRITE
    lw   a2, 0(t0)
    li   a3, CSR_WR_MAGIC
    li   a1, 0x0D220005
    bne  a2, a3, da_fail

    li   t0, SH_MEM_DST             # 4. the progbuf lw/sw round trip
    lw   a2, 0(t0)
    li   a3, MEM_MAGIC
    li   a1, 0x0D220006
    bne  a2, a3, da_fail

    li   t0, SH_OBS_S1              # 1. the abstract READ was NOT destructive
    lw   a2, 0(t0)
    li   a3, GPR_MAGIC
    li   a1, 0x0D220007
    bne  a2, a3, da_fail

    li   t0, SH_MEM_SRC             # ...and the copy went the right way
    lw   a2, 0(t0)
    li   a3, MEM_MAGIC
    li   a1, 0x0D220008
    bne  a2, a3, da_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

da_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # ---- the victim (hart 1) --------------------------------------------
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    bne  t3, t4, tile_park

    li   s1, GPR_MAGIC              # 1. the abstract read's subject
    li   s2, 0                      # 2. the abstract write's target
    .option push
    .option arch, +zicsr
    li   t0, CSR_MAGIC              # 3. the abstract CSR read's subject
    csrw mscratch, t0
    .option pop
    li   t0, SH_MEM_SRC             # 4. the progbuf copy's source
    li   t1, MEM_MAGIC
    sw   t1, 0(t0)
    li   t0, SH_MEM_DST
    sw   x0, 0(t0)

    li   t0, SH_PROG
    li   t1, 1
    sw   t1, 0(t0)
    li   t0, SH_READY
    li   t1, 1
    sw   t1, 0(t0)                  # publish LAST: READY means all of it

#ifdef DBGABS_NC_SELF
    # CONTROL ARM: no DM exists on the tree this was authored against, so the
    # victim performs the debugger's architectural effects on itself.  Nothing
    # here claims anything about abstract commands; it proves the publish,
    # the read-back and hart 0's whole assertion chain execute.
    li   s2, ABS_WR_MAGIC
    .option push
    .option arch, +zicsr
    li   t0, CSR_WR_MAGIC
    csrw mscratch, t0
    .option pop
    li   t0, SH_MEM_SRC
    lw   t1, 0(t0)
    li   t0, SH_MEM_DST
    sw   t1, 0(t0)
    li   t0, SH_REL                 # ...and release itself
    li   t1, 1
    sw   t1, 0(t0)
#endif

    # THE PARK.  The loop holds no live register: the address is recomputed
    # every round, so a debug visit that clobbers t0/t1 is invisible to it.
da_park:
    li   t0, SH_REL
    lw   t1, 0(t0)
    beqz t1, da_park

    li   t0, SH_PROG
    li   t1, 2
    sw   t1, 0(t0)

    # ---- read back what the debugger did, with ordinary instructions ----
    li   t0, SH_OBS_S2
    sw   s2, 0(t0)
    li   t0, SH_OBS_S1
    sw   s1, 0(t0)
    .option push
    .option arch, +zicsr
    csrr t1, mscratch
    .option pop
    li   t0, SH_OBS_MSCR
    sw   t1, 0(t0)

    li   t0, SH_PROG
    li   t1, 3
    sw   t1, 0(t0)
    li   t0, SH_DONE
    li   t1, DONE_MAGIC
    sw   t1, 0(t0)                  # publish LAST
tile_h1_park:
    j    tile_h1_park

tile_park:
    j    tile_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
