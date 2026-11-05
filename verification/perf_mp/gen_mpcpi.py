#!/usr/bin/env python3
"""Emit one multi-hart CPI image: per-class kernels on hart MEAS while NANT other harts hammer the shared window.

  gen_mpcpi.py --meas 1 --nant 3 --ham lw --iters 32 -o build/x.S --table build/x.json

Method is verification/cpi's, moved onto the real five-hart fabric: a loop body of COPIES instructions against an empty
loop in the same memory, timed with mcycle/minstret on the measured hart itself. mcycle is on the free-running mclk
(csr_unit.vhd), so an arbiter stall counts; nothing here depends on the testbench except the print window.
Kernels are `.option norvc` unless named *16, so every 32-bit op is word-aligned and is charged no straddle cost.

Roles: antagonists start hammering and raise READY[h]; the measured hart waits for READY, runs the list, then ends the
run with a store to msip[0] (hart 0's slot-83 ISR sets a0 = PASS). Harts with no role stay parked in the boot ROM or, for
hart 0, in `extinguish`: an idle hart issues zero shared traffic, so "0 others" is a true zero and not "a slow poller".
"""
import argparse
import json

COPIES = 32
PRINT = 0x1F000
READY = 0x1E000       # + 4*h
COMMON = 0x1E080      # the one word every hart fights over in the same-word kernels
PRIVW = 0x1E100       # + 0x40*h, this hart's own shared word
TCMW = 0x9F00         # TCM scratch
NPUW = 0xC100         # NPU staging RAM (shared window, fifth slave)
ROMW = 0x0100         # boot ROM (shared window)
MTIME = 0x5020        # CLINT mtime lo at NHARTS=5
STAGE = 0x18000

# name -> (body text for one copy, location, hart-0-only)
# s0 TCM word, s2 own shared word, s3 NPU RAM, s8 COMMON, s9 ROM, a3 mtime address
K = [
    ("empty",     "",                                                     "t"),
    ("alu32",     "add a4, a1, a2",                                       "t"),
    ("alu16",     ".option rvc\n c.add a4, a1\n .option norvc",           "t"),
    ("shift",     "sll a4, a1, a2",                                       "t"),
    ("lw_tcm",    "lw a4, 0(s0)",                                         "t"),
    ("sw_tcm",    "sw a4, 0(s0)",                                         "t"),
    ("lb_tcm",    "lb a4, 0(s0)",                                         "t"),
    ("sb_tcm",    "sb a4, 0(s0)",                                         "t"),
    ("br_nt",     "bne a1, a1, 8f\n 8:",                                  "t"),
    ("br_t",      "beq a1, a1, 8f\n add a4, a1, a2\n 8:",                 "t"),
    ("jal",       "jal x0, 8f\n add a4, a1, a2\n 8:",                     "t"),
    ("jalr",      "auipc a5, 0\n jalr x0, 12(a5)\n add a4, a1, a2",       "t"),
    ("csrr",      "csrr a4, mcycle",                                      "t"),
    ("amoadd_tcm", "amoadd.w a4, a1, (s0)",                               "t"),
    ("amoswap_tcm", "amoswap.w a4, a1, (s0)",                             "t"),
    ("lrsc_tcm",  "lr.w a4, (s0)\n sc.w a5, a4, (s0)",                    "t"),
    ("lw_sh",     "lw a4, 0(s2)",                                         "t"),
    ("sw_sh",     "sw a4, 0(s2)",                                         "t"),
    ("lb_sh",     "lb a4, 0(s2)",                                         "t"),
    ("sb_sh",     "sb a4, 0(s2)",                                         "t"),
    ("lw_npu",    "lw a4, 0(s3)",                                         "t"),
    ("sw_npu",    "sw a4, 0(s3)",                                         "t"),
    ("lw_rom",    "lw a4, 0(s9)",                                         "t"),
    ("lw_clint",  "lw a4, 0(a3)",                                         "t"),
    ("amoadd_sh", "amoadd.w a4, a1, (s2)",                                "t"),
    ("amoswap_sh", "amoswap.w a4, a1, (s2)",                              "t"),
    ("lrsc_sh",   "lr.w a4, (s2)\n sc.w a5, a4, (s2)",                    "t"),
    ("amoadd_common", "amoadd.w a4, a1, (s8)",                            "t"),
    # Fixed attempts, never a retry loop: an unbounded loop cannot finish when SC is starved, and then measures nothing.
    # a6 counts failed SCs; the kernel reports it as a second row.
    ("lrscinc_common", "lr.w t2, (s8)\n addi t2, t2, 1\n sc.w t3, t2, (s8)\n add a6, a6, t3", "t"),
    ("f_empty",   "",                                                     "s"),
    ("f_alu32",   "add a4, a1, a2",                                       "s"),
    ("f_alu16",   ".option rvc\n c.add a4, a1\n .option norvc",           "s"),
    ("f_lw_tcm",  "lw a4, 0(s0)",                                         "s"),
    ("f_sw_tcm",  "sw a4, 0(s0)",                                         "s"),
    ("f_lw_sh",   "lw a4, 0(s2)",                                         "s"),
    ("f_br_t",    "beq a1, a1, 8f\n add a4, a1, a2\n 8:",                 "s"),
]
K0 = [
    ("mul",   "mul a4, a1, a2",   "t"),
    ("mulh",  "mulh a4, a1, a2",  "t"),
    ("div",   "div a4, a1, a2",   "t"),
    ("divu",  "divu a4, a1, a2",  "t"),
    ("rem",   "rem a4, a1, a2",   "t"),
    ("zbb",   "andn a4, a1, a2",  "t"),
]

HAMMERS = {
    "lw": "ham: \n .rept 16\n lw t0, 0(s2)\n .endr\n j ham",
    "sw": "ham: \n .rept 16\n sw t0, 0(s2)\n .endr\n j ham",
    "fetch": "ham: la t0, ham_fetch\n jr t0",
    "amo": "ham: \n .rept 16\n amoadd.w t0, a1, (s8)\n .endr\n j ham",
    "lrsc": ("ham: lr.w t2, (s8)\n addi t2, t2, 1\n sc.w t3, t2, (s8)\n beqz t3, ham\n"
             " slli t2, s10, 3\n addi t2, t2, 8\n1: addi t2, t2, -1\n bnez t2, 1b\n j ham"),
}


def kernel(name, body, iters, tag, copies):
    r = [" li s1, %d" % iters, " csrr s4, mcycle", " csrr s5, minstret", " .p2align 2", "1:"]
    if body:
        r += [" .rept %d" % copies, " " + body, " .endr"]
    r += [" addi s1, s1, -1", " bne s1, x0, 1b", " csrr s6, mcycle", " csrr s7, minstret"]
    r += [" li t1, %d" % tag, " jal ra, report"]
    if name == "lrscinc_common":
        r += [" li s4, 0", " mv s6, a6", " li s5, 0", " li s7, 0", " li t1, 1000", " jal ra, report"]
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--meas", type=int, default=1)
    ap.add_argument("--nant", type=int, default=0)
    ap.add_argument("--ham", default="lw", choices=sorted(HAMMERS))
    ap.add_argument("--iters", type=int, default=32)
    ap.add_argument("--only", default="")
    ap.add_argument("--extra-nops", type=int, default=0,
                    help="negative control: add N nops to every lw_sh copy; the marginal must rise by exactly N")
    ap.add_argument("-o", required=True)
    ap.add_argument("--table", required=True)
    a = ap.parse_args()

    others = [h for h in (2, 3, 4, 0, 1) if h != a.meas]
    ants = others[:a.nant]
    # Hart 0's extra M/B kernels must fit the same TCM, so it skips rows the tile run already covers.
    drop0 = {"shift", "lb_tcm", "sb_tcm", "lb_sh", "sb_sh", "jalr", "lw_clint", "lw_rom"}
    kl = list(K) + K0 if a.meas == 0 else list(K)
    if a.meas == 0:
        kl = [k for k in kl if k[0] not in drop0]
    if a.only:
        keep = set(a.only.split(",")) | {"empty", "f_empty"}
        kl = [k for k in kl if k[0] in keep]

    tcm, sh, table = [], [], {}
    for tag, (name, body, loc) in enumerate(kl, 1):
        if a.extra_nops and name == "lw_sh":
            body = body + "".join("\n nop" for _ in range(a.extra_nops))
        table[tag] = {"name": name, "loc": loc, "ops": COPIES * a.iters if body else 0}
        k = kernel(name, body, a.iters, tag, COPIES)
        if loc == "t":
            tcm += k
        else:
            sh += ["k_%s:" % name, " mv s11, ra"] + k + [" mv ra, s11", " ret"]
            tcm += [" la t0, k_%s" % name, " jalr ra, t0"]

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

    src = """/* generated by gen_mpcpi.py: meas={meas} nant={nant} ants={ants} ham={ham} iters={iters} */
 .option norvc
 .option norelax
 .section .ivt, "ax"
 .org 0x14C
 jal zero, msip_isr
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
 li t0, 0x40
 mul_free_placeholder:
 mv t1, s10
 li s2, {privw}
2: beqz t1, 3f
 add s2, s2, t0
 addi t1, t1, -1
 j 2b
3: li s3, {npuw}
 li s8, {common}
 li s9, {romw}
 li a3, {mtime}
 li a1, 3
 li a2, 5
 li a4, 0
 li a6, 0
 li s11, 0
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
{tcm}
 li t0, 0x1FFFC
 sw zero, 0(t0)
{finish}
report:
 slli t0, s10, 8
 li t2, {print}
 add t0, t0, t2
 sub t2, s6, s4
 sw t1, 0(t0)
 sw t2, 4(t0)
 sub t2, s7, s5
 sw t2, 8(t0)
 li t0, 0x1FFFC
 sw zero, 0(t0)
 ret
msip_isr:
 li a0, 0xCAFEBABE
 j msip_isr
 .section .text_sh, "ax"
 .p2align 2
ham_fetch:
 .rept 64
 add t0, t0, t1
 .endr
 j ham_fetch
{sh}
""".format(meas=a.meas, nant=a.nant, ants=ants, ham=a.ham, iters=a.iters, ready=READY, stage=STAGE,
           launch="\n".join(launch), tcmw=TCMW, privw=PRIVW, npuw=NPUW, common=COMMON, romw=ROMW, mtime=MTIME,
           antcheck="\n".join(" li t0, %d\n beq s10, t0, antagonist" % h for h in ants),
           hammer=HAMMERS[a.ham], wait_ready="\n".join(wait_ready), tcm="\n".join(tcm), finish=finish,
           print=PRINT, sh="\n".join(sh))
    src = src.replace(" mul_free_placeholder:\n", "")
    open(a.o, "w").write(src)
    json.dump({"meas": a.meas, "nant": a.nant, "ants": ants, "ham": a.ham, "iters": a.iters, "copies": COPIES,
               "extra_nops": a.extra_nops, "kernels": table}, open(a.table, "w"), indent=1)


if __name__ == "__main__":
    main()
