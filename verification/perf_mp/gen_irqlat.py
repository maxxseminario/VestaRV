#!/usr/bin/env python3
"""Emit one interrupt-latency image: hart MEAS runs each victim in turn while its own mtimecmp fires at a swept phase.

The interrupt source is the hart's own CLINT mtimecmp. mtime ticks on mclk, so adding k to the compare value moves the
assertion by exactly k cycles relative to the victim loop: K trials sweep every phase of the victim, which is what puts
the level inside each state of an uninterruptible sequence. Hart software never times anything here; perf_mon.vhd takes
t_level at the hart's port and t_isr at the retire of the instruction at ISR_ADDR (0x9100), and prints one L record per
interrupt. The print-window marker before each victim group lets the parser attribute records.

Register contract: s11 = trial-done flag set by the ISR, t5 = this hart's mtimecmp hi address, t6 = -1. The ISR touches
nothing else, so its first instruction can be the flag write with no save sequence in front of it. Delivery:
  legacy: IVT slot 84 holds `jal zero, 0x9100`; hardware pushes the PC at sp-4; ISR ends in iret (ignite first, so a
          sleeping victim resumes rather than re-sleeping)
  std:    mtrapctl.LEGACY=0, mtvec=0x9100 (direct is the only mode), mie.MTIE, mstatus.MIE; ISR ends in mret
"""
import argparse
import json

from gen_mpcpi import HAMMERS, PRINT, READY, COMMON, PRIVW, TCMW, NPUW, ROMW, MTIME, STAGE

MTIMECMP0 = 0x5030    # CLINT at NHARTS=5: mtime 0x5020, mtimecmp[h] = 0x5030 + 8*h
DELAY = 200           # > worst contended store, so the compare is armed before the level is due
COPIES = 8

# name -> (body, location, hart-0-only)
V = [
    ("alu",        "add a4, a1, a2",                       "t", False),
    ("lw_tcm",     "lw a4, 0(s0)",                         "t", False),
    ("sw_tcm",     "sw a4, 0(s0)",                         "t", False),
    ("br_t",       "beq a1, a1, 8f\n add a4, a1, a2\n 8:", "t", False),
    ("lw_sh",      "lw a4, 0(s2)",                         "t", False),
    ("sw_sh",      "sw a4, 0(s2)",                         "t", False),
    ("amoadd_tcm", "amoadd.w a4, a1, (s0)",                "t", False),
    ("amoadd_sh",  "amoadd.w a4, a1, (s2)",                "t", False),
    ("lrsc_sh",    "lr.w a4, (s2)\n sc.w a5, a4, (s2)",    "t", False),
    ("f_alu",      "add a4, a1, a2",                       "s", False),
    ("f_lw_sh",    "lw a4, 0(s2)",                         "s", False),
    ("f_amoadd_sh", "amoadd.w a4, a1, (s2)",               "s", False),
    ("sleep",      None,                                   "t", False),
    ("mul",        "mul a4, a1, a2",                       "t", True),
    ("div",        "div a4, a1, a2",                       "t", True),
    ("rem",        "rem a4, a1, a2",                       "t", True),
    ("f_div",      "div a4, a1, a2",                       "s", True),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--meas", type=int, default=1)
    ap.add_argument("--mode", default="legacy", choices=["legacy", "std"])
    ap.add_argument("--nant", type=int, default=0)
    ap.add_argument("--ham", default="lw")
    ap.add_argument("--trials", type=int, default=256)
    ap.add_argument("--stack", default="tcm", choices=["tcm", "sh"])
    ap.add_argument("--only", default="")
    ap.add_argument("-o", required=True)
    ap.add_argument("--table", required=True)
    a = ap.parse_args()
    others = [h for h in (2, 3, 4, 0, 1) if h != a.meas]
    ants = others[:a.nant]

    tcm, sh, names = [], [], []
    vl = [v for v in V if (a.meas == 0 or not v[3]) and (not a.only or v[0] in a.only.split(","))]
    for tag, (name, body, loc, _) in enumerate(vl, 1):
        names.append(name)
        lab = "v_" + name
        if body is None:
            code = [lab + ":", " .p2align 2", "1:"]
            code += [" wfi" if a.mode == "std" else " .insn r 0x0b, 1, 0, x0, x0, x0"]
            code += [" beqz s11, 1b", " ret"]
        else:
            code = [lab + ":", " .p2align 2", "1:", " .rept %d" % COPIES, " " + body, " .endr",
                    " beqz s11, 1b", " ret"]
        (tcm if loc == "t" else sh).extend(code)
    drive = []
    for tag, name in enumerate(names, 1):
        drive += [" li t1, %d" % tag, " jal ra, mark", " li s7, 0",
                  "2:", " jal ra, arm", " la t0, v_%s" % name, " jalr ra, t0",
                  " addi s7, s7, 1", " li t0, %d" % a.trials, " blt s7, t0, 2b"]

    launch = []
    for h in sorted(set(ants + [a.meas]) - {0}):
        launch += [
            " li t0, 0x10500 + 0x10*%d" % h, " li t1, %d" % STAGE, " sw t1, 0(t0)",
            " li t1, 2048", " sw t1, 4(t0)", " la t1, tile_entry", " sw t1, 8(t0)",
            " li t0, 0x5000 + 4*%d" % h, " li t1, 1", " sw t1, 0(t0)"]
    wait_ready = []
    for h in ants:
        wait_ready += ["1: li t0, %d" % (READY + 4 * h), " lw t1, 0(t0)", " beqz t1, 1b"]
    finish = (" li a0, 0xCAFEBABE\n j .\n" if a.meas == 0
              else " li t0, 0x5000\n li t1, 1\n sw t1, 0(t0)\n1: j 1b\n")
    if a.mode == "std":
        arm_mode = (" li t0, 0x9100\n csrw 0x305, t0\n li t0, 0x80\n csrw 0x304, t0\n"
                    " li t0, 8\n csrw 0x300, t0\n csrw 0x7C0, x0\n")
        isr_tail = " mret"
    else:
        arm_mode = ""
        isr_tail = " .insn r 0x0b, 1, 1, x0, x0, x0\n .insn r 0x0b, 0, 0, x0, x0, x0"
    set_sp = (" li sp, 0x9FF0" if a.stack == "tcm"
              else " slli sp, s10, 6\n li t0, 0x1E400\n add sp, sp, t0\n addi sp, sp, 0x3C")

    src = """/* generated by gen_irqlat.py: meas={meas} mode={mode} nant={nant} ants={ants} ham={ham} trials={trials} stack={stack} */
 .option norvc
 .option norelax
 .section .ivt, "ax"
 .org 0x14C
 jal zero, msip_isr
 jal zero, 0x9100
 .section .text.init, "ax"
 .globl _start
_start:
 csrr s10, mhartid
 bnez s10, tile_entry
 li sp, 0x9FF0
 li t0, {ready}
 li t1, {ready} + 32
1: sw zero, 0(t0)
 addi t0, t0, 4
 bltu t0, t1, 1b
 li t0, 0x8000
 li t1, {stage}
 li t2, 2048
1: lw t3, 0(t0)
 sw t3, 0(t1)
 addi t0, t0, 4
 addi t1, t1, 4
 addi t2, t2, -1
 bnez t2, 1b
{launch}
 j role
tile_entry:
 csrr s10, mhartid
 li sp, 0x9FF0
role:
 li s0, {tcmw}
 slli s2, s10, 6
 li t0, {privw}
 add s2, s2, t0
 li s3, {npuw}
 li s8, {common}
 li s9, {romw}
 li a3, {mtime}
 li a1, 3
 li a2, 5
 li a4, 0
 li t0, {meas}
 beq s10, t0, measure
{antcheck}
idle:
 .insn r 0x0b, 1, 0, x0, x0, x0
 j idle
antagonist:
 slli t0, s10, 2
 li t1, {ready}
 add t0, t0, t1
 li t1, 1
 sw t1, 0(t0)
 li t1, 0
{hammer}
measure:
{wait_ready}
{set_sp}
 slli t5, s10, 3
 li t0, {cmp0}+4
 add t5, t5, t0
 li t6, -1
 sw t6, 0(t5)
{arm_mode}
{drive}
{finish}
arm:
 li s11, 0
 lw t0, 0(a3)
 addi t0, t0, {delay}
 add t0, t0, s7
 sw t0, -4(t5)
 sw zero, 0(t5)
 ret
mark:
 slli t0, s10, 8
 li t2, {print}
 add t0, t0, t2
 sw t1, 0(t0)
 ret
msip_isr:
 li a0, 0xCAFEBABE
 j msip_isr
{tcm}
 .section .isr, "ax"
 .globl isr_entry
isr_entry:
 li s11, 1
 sw t6, 0(t5)
{isr_tail}
 .section .text_sh, "ax"
 .p2align 2
ham_fetch:
 .rept 64
 add t0, t0, t1
 .endr
 j ham_fetch
{sh}
""".format(meas=a.meas, mode=a.mode, nant=a.nant, ants=ants, ham=a.ham, trials=a.trials, stack=a.stack, ready=READY,
           stage=STAGE, launch="\n".join(launch), tcmw=TCMW, privw=PRIVW, npuw=NPUW, common=COMMON, romw=ROMW,
           mtime=MTIME, antcheck="\n".join(" li t0, %d\n beq s10, t0, antagonist" % h for h in ants),
           hammer=HAMMERS[a.ham], wait_ready="\n".join(wait_ready), set_sp=set_sp, cmp0=MTIMECMP0, arm_mode=arm_mode,
           drive="\n".join(drive), finish=finish, delay=DELAY, print=PRINT, tcm="\n".join(tcm), isr_tail=isr_tail,
           sh="\n".join(sh))
    open(a.o, "w").write(src)
    json.dump({"meas": a.meas, "mode": a.mode, "nant": a.nant, "ants": ants, "ham": a.ham, "trials": a.trials,
               "stack": a.stack, "victims": names}, open(a.table, "w"), indent=1)


if __name__ == "__main__":
    main()
