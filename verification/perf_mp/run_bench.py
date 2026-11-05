#!/usr/bin/env python3
"""CoreMark and Dhrystone on the five-hart behavioral sim.

  run_bench.py one coremark --variant hot --mask 2 --iters 2 [--run perf|valid] [--stall 3] [--budget 1800]
  run_bench.py one dhrystone --variant tcmtext --mask 31
  run_bench.py plan coremark|dhrystone|all

--mask is the RUNMASK bit set of harts that execute the benchmark (bit 0 = hart 0, 2 = hart 1 alone, 0x1E = four tiles,
0x1F = all five). Benchmarks are unmodified; only linker placement changes between variants, and the memory map never does.
CoreMark source is fetched from the public EEMBC repo by fetch_coremark.sh into COREMARK_DIR.
"""
import argparse
import json
import os
import re
import sys

import simlib
from simlib import RUN, HERE, ROOT, MARCH_H0, MARCH_TILE, sh

IMG = os.path.join(RUN, "bimg")
CM = os.environ.get("COREMARK_DIR", os.path.join(RUN, "coremark-src"))
BM = os.path.join(ROOT, "verification/benchmarks")
ENV = os.path.join(ROOT, "verification/env")
MHZ = 24.0

CM_OPTS = ["-O2", "-std=gnu99", "-fno-common", "-fno-tree-loop-distribute-patterns"]
DH_OPTS = ["-O2", "-std=gnu99", "-ffast-math", "-fno-common", "-fno-builtin-printf", "-fdata-sections",
           "-fno-tree-loop-distribute-patterns", "-Wno-implicit-int", "-Wno-implicit-function-declaration",
           "-Wno-return-type", "-DPREALLOCATE=1"]
BASE = ["-mabi=ilp32", "-mcmodel=medany", "-static", "-nostdlib", "-nostartfiles"]

HOT_CM = ["core_list_join.o", "core_matrix.o", "core_state.o", "core_util.o"]

TEXT_BASE = {"h0": 0x10900, "tile": 0x13A00}     # CoreMark: one shared text copy per hart class
DH_ARR2 = 0x11800                                # + 0x2800*h, per-hart Arr_2_Glob
STAGE = 0x18000
STAGE_STEP = 0x1800


def ldscript(path, hot, rodata_hot_only, text_base, shbss=None, data_shared=None):
    """hot: list of file patterns whose .text (and .rodata) go to the TCM."""
    hot_t = "\n".join("    *%s(.text .text.* .rodata .rodata.* .srodata .srodata.*)" % h for h in hot)
    cold_ro = "*(.rodata .rodata.* .srodata .srodata.*)"
    s = """OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{{
  . = 0x8000;
  .tcm_text 0x8000 : {{
{hot_t}
    . = ALIGN(4);
  }}
  .tcm_ro : {{ {ro_tcm} . = ALIGN(4); }}
  .data : {{
    __global_pointer$ = . + 0x800;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4);
    __tcm_load_end = .;
  }}
  .shbss {shb} (NOLOAD) : {{
    __shbss_start = .;
    *(.bss.Arr_2_Glob)
    . = ALIGN(4);
    __shbss_end = .;
  }}
  .bss __tcm_load_end (NOLOAD) : {{
    __bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
    __tcm_end = .;
  }}
  ASSERT(__tcm_end <= 0x9F00, "TCM image leaves no stack")
  _stack_top = 0xA000;
  .text {tb:#x} : {{
    *crt_mp.o(.text.init)
    *(.text .text.*)
    {ro_sh}
    . = ALIGN(4);
    __text_end = .;
  }}
}}
""".format(hot_t=hot_t, ro_tcm="" if rodata_hot_only else cold_ro, shb=hex(shbss) if shbss else "0x1E800",
           tb=text_base, ro_sh=cold_ro if rodata_hot_only else "")
    open(path, "w").write(s)


def compile_objs(d, march, srcs, opts):
    os.makedirs(d, exist_ok=True)
    objs = []
    for s in srcs:
        o = os.path.join(d, os.path.basename(s).rsplit(".", 1)[0] + ".o")
        simlib.gcc(["-march=" + march] + BASE + opts + ["-c", s, "-o", o])
        objs.append(o)
    return objs


def link(elf, objs, ld, march):
    simlib.gcc(["-march=" + ("rv32imac_zicsr" if "zba" in march else march)] + BASE + ["-Wl,--no-warn-rwx-segments", "-T", ld, "-o", elf] + objs + ["-lgcc"])


def syms(elf):
    out = {}
    for ln in sh(["riscv-none-elf-nm", elf]).splitlines():
        p = ln.split()
        if len(p) == 3:
            out[p[2]] = int(p[0], 16)
    return out


def size_report(elf):
    return sh(["riscv-none-elf-size", "-A", elf])


def build_coremark(tag, variant, iters, run, stackfill):
    d = os.path.join(IMG, tag)
    os.makedirs(d, exist_ok=True)
    flag = {"perf": "-DPERFORMANCE_RUN=1", "valid": "-DVALIDATION_RUN=1"}[run]
    res = {}
    for cls, march in (("h0", MARCH_H0), ("tile", MARCH_TILE)):
        flagstr = "-O2 -std=gnu99 -fno-common -fno-tree-loop-distribute-patterns -march=%s -mabi=ilp32 -mcmodel=medany" % march
        opts = CM_OPTS + (["-DSTACK_FILL"] if stackfill else []) + ["-I" + CM, "-I" + os.path.join(HERE, "coremark"), flag, "-DITERATIONS=%d" % iters,
                          '-DFLAGS_STR="%s"' % flagstr, "-DTOTAL_DATA_SIZE=2000"]
        srcs = [os.path.join(CM, f) for f in ("core_list_join.c", "core_main.c", "core_matrix.c", "core_state.c",
                                              "core_util.c")]
        srcs += [os.path.join(HERE, "coremark/core_portme.c"), os.path.join(HERE, "rt/port.c")]
        objs = compile_objs(os.path.join(d, cls), march, srcs, opts)
        objs += compile_objs(os.path.join(d, cls), march, [os.path.join(HERE, "rt/crt_mp.S")],
                             ["-DSTACK_FILL"] if stackfill else [])
        ld = os.path.join(d, cls + ".ld")
        if variant == "hot":
            ldscript(ld, HOT_CM + ["libgcc.a:"], True, TEXT_BASE[cls])
        else:
            ldscript(ld, [], False, TEXT_BASE[cls])
        elf = os.path.join(d, cls + ".elf")
        link(elf, objs, ld, march)
        res[cls] = elf
    return res


def build_dhrystone(tag, variant, stackfill, mask):
    d = os.path.join(IMG, tag)
    os.makedirs(d, exist_ok=True)
    res = {}
    for h in range(5):
        if not mask & (1 << h) and h != 0:
            continue
        cls = "h0" if h == 0 else "tile"
        march = MARCH_H0 if h == 0 else MARCH_TILE
        opts = DH_OPTS + ["-I" + ENV, "-I" + os.path.join(BM, "common"), "-I" + os.path.join(BM, "dhrystone")]
        srcs = [os.path.join(BM, "dhrystone/dhrystone.c"), os.path.join(HERE, "rt/dhry_port.c"),
                os.path.join(HERE, "rt/port.c")]
        objs = compile_objs(os.path.join(d, "h%d" % h), march, srcs, opts)
        # dhrystone.c's empty debug_printf is replaced for main only, so the final-value report outside the timed
        # window reaches the log and can be graded. The timed loop contains no debug_printf call.
        objs += compile_objs(os.path.join(d, "h%d" % h), march, [os.path.join(BM, "dhrystone/dhrystone_main.c")],
                             opts + ["-Ddebug_printf=dh_log"])
        objs += compile_objs(os.path.join(d, "h%d" % h), march, [os.path.join(HERE, "rt/crt_mp.S")],
                             ["-DSTACK_FILL"] if stackfill else [])
        ld = os.path.join(d, "h%d.ld" % h)
        hot = ["/port.o", "/dhry_port.o", "/dhrystone.o", "/dhrystone_main.o", "libgcc.a:"] if variant == "tcmtext" else []
        if variant == "tcmtext":
            # crt_mp.S names this hart's .shbss, so the cold text differs per hart and each needs its own copy.
            ldscript(ld, hot, True, 0x10900 if h == 0 else 0x10C00 + 0x1A0 * (h - 1), shbss=DH_ARR2 + 0x2800 * h)
        else:   # single-hart only: one Arr_2_Glob, text per class in shared
            ldscript(ld, hot, False, {"h0": 0x14800, "tile": 0x16800}[cls], shbss=DH_ARR2)
        elf = os.path.join(d, "h%d.elf" % h)
        link(elf, objs, ld, march)
        res[h] = elf
    return res


def compose_image(tag, h0_elf, tile_elfs, mask):
    """tile_elfs: {h: elf}. One staged TCM image per distinct ELF."""
    d = os.path.join(IMG, tag)
    specs = [h0_elf]
    words = []
    s0 = syms(h0_elf)
    words.append("--word=0x10640=%#x" % s0["_start"])
    words.append("--word=0x108F0=%#x" % mask)
    stage_of = {}
    for h in (1, 2, 3, 4):
        if not mask & (1 << h):
            continue
        e = tile_elfs[h]
        if e not in stage_of:
            stage_of[e] = STAGE + STAGE_STEP * len(stage_of)
            specs.append("%s@%#x:0x8000" % (e, stage_of[e]))
        s = syms(e)
        ln = (s["__tcm_load_end"] - 0x8000) // 4
        if len(stage_of) > 1:
            assert ln * 4 <= STAGE_STEP, "staged TCM image overflows its slot"
        row = 0x10500 + 0x10 * h
        words += ["--word=%#x=%#x" % (row, stage_of[e]), "--word=%#x=%#x" % (row + 4, ln),
                  "--word=%#x=%#x" % (row + 8, s["_start"])]
    rcf = os.path.join(d, "image.rcf")
    print(simlib.compose(rcf, *(specs + words)).strip())
    return rcf


def harts(mask):
    return [h for h in range(5) if mask & (1 << h)]


def text_log(w, h):
    return "".join(chr(v & 0xFF) for _, _, v in w.get(0x1F000 + 0x100 * h + 0x40, []))


def parse(log, mask, tagcode):
    w = simlib.parse_w(log)
    out = {}
    stats = []
    cur = {}
    for ln in open(log):
        if ln.startswith("S "):
            _, h, t, s, m = ln.split()
            cur[int(h)] = (int(t), int(s), int(m))
            if int(h) == 4:
                stats.append(cur)
                cur = {}
    for h in harts(mask):
        b = 0x1F000 + 0x100 * h
        rows = [(a[2], c[2], i[2]) for a, c, i in zip(w.get(b, []), w.get(b + 4, []), w.get(b + 8, []))]
        r = [x for x in rows if x[0] == tagcode]
        e = {"log": text_log(w, h)}
        sw = [x for x in rows if x[0] == 0x57AC]
        if sw:
            e["stack_low_water"], e["tcm_end"] = hex(sw[-1][1]), hex(sw[-1][2])
        if r:
            e["cycles"], e["instret"] = r[-1][1], r[-1][2]
            e["cpi"] = e["cycles"] / e["instret"]
        out[h] = e
    return out, stats


def job(a):
    tag = a.tag or "%s_%s_m%x_i%d_%s_d%d" % (a.bench, a.variant, a.mask, a.iters, a.run, a.stall)
    if a.bench == "coremark":
        e = build_coremark(tag, a.variant, a.iters, a.run, a.stackfill)
        tiles = {h: e["tile"] for h in (1, 2, 3, 4)}
        h0 = e["h0"]
    else:
        e = build_dhrystone(tag, a.variant, a.stackfill, a.mask)
        tiles = e
        h0 = e[0]
    rcf = compose_image(tag, h0, tiles, a.mask)
    sz = {k: size_report(v) for k, v in {"h0": h0, "tile": tiles.get(1, tiles.get(2, h0))}.items()}
    r = simlib.sim(tag, rcf, stall=a.stall, budget_s=a.budget)
    out = {"tag": tag, "bench": a.bench, "variant": a.variant, "mask": a.mask, "iters": a.iters, "run": a.run,
           "stall": a.stall, "passed": r.passed, "killed": r.killed, "wall_s": round(r.wall, 1), "sizes": sz}
    if os.path.exists(r.log):
        p, st = parse(r.log, a.mask, 0xC0DE if a.bench == "coremark" else 0xD401)
        out["harts"] = {str(k): v for k, v in p.items()}
        out["arb"] = [{str(k): list(v) for k, v in s.items()} for s in st]
        for h, v in p.items():
            if "cycles" in v:
                if a.bench == "coremark":
                    v["coremark_per_mhz"] = a.iters * 1e6 / v["cycles"]
                    v["crc_ok"] = "ERROR! " not in v["log"].replace("ERROR! Must execute for at least 10 secs", "")
                    v["seedcrc"] = re.findall(r"seedcrc\s*:\s*(0x[0-9a-f]+)", v["log"])
                    v["crcfinal"] = re.findall(r"\[0\]crcfinal\s*:\s*(0x[0-9a-f]+)", v["log"])
                else:
                    runs = 500
                    vals = re.findall(r"^(.*?:)\s+(-?\d+)\n\s+should be:\s+(-?\d+)$", v["log"], re.M)
                    v["dhry_checked"] = len(vals)
                    v["dhry_ok"] = bool(vals) and all(x[1] == x[2] for x in vals)
                    v["cyc_per_run"] = v["cycles"] / runs
                    v["dmips_per_mhz"] = 1e6 / (v["cycles"] / runs) / 1757
    res_dir = os.path.join(HERE, "results", "bench")
    os.makedirs(res_dir, exist_ok=True)
    json.dump(out, open(os.path.join(res_dir, tag + ".json"), "w"), indent=0, sort_keys=True)
    print(tag, "passed", r.passed, "killed", r.killed, "wall", round(r.wall, 1))
    for h, v in sorted(out.get("harts", {}).items()):
        print("  h%s" % h, {k: x for k, x in v.items() if k != "log"})
    return out


# (bench, variant, mask, iters, run, stall, estimated mclk cycles). Estimates come from the first smoke runs:
# hot 0.83M cycles/iteration/hart, shared text about 7x that alone and fetch-bound on the arbiter when concurrent, 4M
# boot+load, and a measured 20k cycles/s of wall time, so the budget below is 4x the estimate.
PLAN = [
    ("coremark", "hot", 0x02, 10, "perf", 0, 12e6),
    ("coremark", "hot", 0x01, 10, "perf", 0, 12e6),
    ("coremark", "hot", 0x1E, 10, "perf", 0, 12e6),
    ("coremark", "hot", 0x1F, 10, "perf", 0, 12e6),
    ("coremark", "hot", 0x1F, 2, "valid", 0, 6e6),
    ("coremark", "shtext", 0x02, 2, "perf", 0, 16e6),
    ("coremark", "shtext", 0x01, 2, "perf", 0, 16e6),
    ("coremark", "shtext", 0x1E, 1, "perf", 0, 40e6),
    ("coremark", "shtext", 0x1F, 1, "perf", 0, 50e6),
    ("dhrystone", "tcmtext", 0x02, 1, "perf", 0, 2e6),
    ("dhrystone", "tcmtext", 0x01, 1, "perf", 0, 2e6),
    ("dhrystone", "tcmtext", 0x1E, 1, "perf", 0, 3e6),
    ("dhrystone", "tcmtext", 0x1F, 1, "perf", 0, 3e6),
    ("dhrystone", "shtext", 0x02, 1, "perf", 0, 6e6),
    ("dhrystone", "shtext", 0x01, 1, "perf", 0, 6e6),
    # negative controls: same images, a known 3-cycle stall per shared-RAM transaction
    ("coremark", "hot", 0x02, 1, "perf", 3, 6e6),
    ("coremark", "hot", 0x02, 1, "perf", 0, 6e6),
    ("coremark", "shtext", 0x02, 1, "perf", 3, 12e6),
    ("coremark", "shtext", 0x02, 1, "perf", 0, 12e6),
    ("dhrystone", "tcmtext", 0x02, 1, "perf", 3, 2e6),
]


def plan(a):
    jobs = []
    for b, v, m, it, run, st, est in PLAN:
        if a.bench not in (None, "all", b):
            continue
        n = argparse.Namespace(bench=b, variant=v, mask=m, iters=it, run=run, stall=st, stackfill=False, tag="",
                               budget=int(est / 20000 * 4) + 300)
        f = os.path.join(HERE, "results", "bench", "%s_%s_m%x_i%d_%s_d%d.json" % (b, v, m, it, run, st))
        if os.path.exists(f) and json.load(open(f))["passed"] and not os.environ.get("FORCE"):
            continue
        jobs.append((job, (n,)))
    simlib.pool(jobs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("bench", nargs="?")
    ap.add_argument("--variant", default="hot")
    ap.add_argument("--mask", type=lambda s: int(s, 0), default=2)
    ap.add_argument("--iters", type=int, default=1)
    ap.add_argument("--run", default="perf")
    ap.add_argument("--stall", type=int, default=0)
    ap.add_argument("--budget", type=int, default=1800)
    ap.add_argument("--stackfill", action="store_true")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    if a.cmd == "one":
        job(a)
    elif a.cmd == "plan":
        plan(a)
    elif a.cmd == "sizes":
        keys = ("__tcm_end", "__tcm_load_end", "__text_end")
        try:
            e = build_coremark("sizes_" + a.variant, a.variant, 1, "perf", True) if a.bench == "coremark" else \
                {"h0": build_dhrystone("sizes_" + a.variant, a.variant, True, 31)[0],
                 "tile": build_dhrystone("sizes_" + a.variant, a.variant, True, 31)[1]}
        except Exception as x:
            print(getattr(x, "output", x))
            raise
        for k, v in e.items():
            print(k, size_report(v))
            print({n: hex(x) for n, x in syms(v).items() if n in keys})


if __name__ == "__main__":
    main()
