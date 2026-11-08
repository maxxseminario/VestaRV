#!/usr/bin/env python3
"""Parallel scaling on the five-hart behavioral sim: ONE job (rt/par_kern.c) split across N harts.

  run_par.py one --kernel fir|box|hist --place shared|tcm --mask 0x1F [--isa common|native] [--stall 3]
  run_par.py sweep [--kernels fir box hist]   # placements x N = 1..5 (masks 0x02 0x06 0x0E 0x1E 0x1F) + hart 0 alone
  run_par.py report         # scaling table from results/par/*.json

Kernels (same int16 samples for all three): fir = 16-tap FIR (compute-bound: software multiply on the tiles),
box = 16-tap boxcar (same reuse, one add per tap: memory-bound when placed in shared RAM), hist = 64-bin histogram
with one amoadd per sample on shared bins (synchronization-bound), or private TCM bins merged by 64 amoadds.

Wall time is taken from perf_mon's global mclk stamps on the start/end print-window stores (first start -> last end),
so it is one clock for all harts; per-hart mcycle/minstret deltas give the aggregate IPC.
--isa common builds every hart for the tile ISA (rv32iac) so all harts execute identical instructions;
--isa native gives hart 0 its shipped M+B set (heterogeneous work per rank).
"""
import argparse
import glob
import json
import os
import random

import simlib
from simlib import HERE, MARCH_H0, MARCH_TILE
import run_bench as rb

NOUT, NTAP = 1200, 16
NIN = NOUT + NTAP
COEF = [-3, -7, -9, 0, 25, 70, 128, 180, 210, 180, 128, 70, 25, 0, -9, -7]   # 16-tap low-pass, integer
NBIN, BIN_SHIFT, BIN_OFS = 64, 6, 2048        # bin = (x + 2048) >> 6; samples stay inside [-2000, 2000]
KERNELS = {"fir": 0, "box": 1, "hist": 2}
TEXT_BASE = {"h0": 0x10900, "tile": 0x13A00}
SHIN, SHOUT = 0x14000, 0x16000
OPTS = ["-O2", "-std=gnu99", "-fno-common", "-fno-tree-loop-distribute-patterns", "-fno-builtin"]
RES = os.path.join(HERE, "results", "par")
SWEEP_MASKS = [0x02, 0x06, 0x0E, 0x1E, 0x1F]


def samples():
    r = random.Random(0xCA57)
    # 12-bit ADC codes around mid-scale: slow sine-ish drift + noise, signed int16
    out = []
    v = 0
    for i in range(NIN):
        v += r.randint(-40, 40)
        v = max(-1800, min(1800, v))
        out.append(v + r.randint(-200, 200))
    return out


def golden(kernel):
    x = samples()
    if kernel == "fir":
        return [sum(COEF[k] * x[i + k] for k in range(NTAP)) for i in range(NOUT)]
    if kernel == "box":
        return [sum(x[i:i + NTAP]) for i in range(NOUT)]
    b = [0] * NBIN
    for v in x[:NOUT]:
        b[(v + BIN_OFS) >> BIN_SHIFT] += 1
    return b


def checksum(ys):
    c = 0
    for y in ys:
        c = (((c << 5) | (c >> 27)) & 0xFFFFFFFF) ^ (y & 0xFFFFFFFF)
    return c


def write_header(path):
    x = samples()
    with open(path, "w") as f:
        f.write("#define NOUT %d\n#define NTAP %d\n#define NIN %d\n" % (NOUT, NTAP, NIN))
        f.write("#define NBIN %d\n#define BIN_SHIFT %d\n#define BIN_OFS %d\n" % (NBIN, BIN_SHIFT, BIN_OFS))
        assert all(0 <= (v + BIN_OFS) >> BIN_SHIFT < NBIN for v in x)
        f.write("#define COEF_INIT {%s}\n" % ", ".join(map(str, COEF)))
        f.write("#define X_INIT {%s}\n" % ", ".join(map(str, x)))


def ldscript(path, text_base):
    hot = "\n".join("    *%s(.text .text.* .rodata .rodata.* .srodata .srodata.*)" % h
                    for h in ("/port.o", "/par_kern.o", "libgcc.a:"))
    s = """OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{{
  .tcm_text 0x8000 : {{
{hot}
    . = ALIGN(4);
  }}
  .data : {{
    __global_pointer$ = . + 0x800;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4);
    __tcm_load_end = .;
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
    *(.rodata .rodata.* .srodata .srodata.*)
    . = ALIGN(4);
    __text_end = .;
  }}
  ASSERT(__text_end <= {lim:#x}, "shared text overruns the next region")
  .shin {shin:#x} : {{ *(.shin) . = ALIGN(4); __shin_end = .; }}
  ASSERT(__shin_end <= {shout:#x}, "input overruns output")
  .shout {shout:#x} (NOLOAD) : {{ *(.shout) . = ALIGN(4); __shout_end = .; }}
  ASSERT(__shout_end <= 0x18000, "output overruns the tile stage")
  __shbss_start = 0; __shbss_end = 0;
}}
""".format(hot=hot, tb=text_base, lim=0x13A00 if text_base < 0x13A00 else SHIN, shin=SHIN, shout=SHOUT)
    open(path, "w").write(s)


def build(tag, kernel, place, isa):
    d = os.path.join(rb.IMG, tag)
    os.makedirs(d, exist_ok=True)
    write_header(os.path.join(d, "par_data.h"))
    res = {}
    for cls in ("h0", "tile"):
        march = MARCH_H0 if (cls == "h0" and isa == "native") else MARCH_TILE
        opts = OPTS + ["-I" + d, "-DPLACE_TCM=%d" % (place == "tcm"), "-DKERNEL=%d" % KERNELS[kernel]]
        srcs = [os.path.join(HERE, "rt/par_kern.c"), os.path.join(HERE, "rt/port.c")]
        objs = rb.compile_objs(os.path.join(d, cls), march, srcs, opts)
        objs += rb.compile_objs(os.path.join(d, cls), march, [os.path.join(HERE, "rt/crt_mp.S")], [])
        ld = os.path.join(d, cls + ".ld")
        ldscript(ld, TEXT_BASE[cls])
        elf = os.path.join(d, cls + ".elf")
        rb.link(elf, objs, ld, march)
        res[cls] = elf
    return res


def parse(log, mask):
    w = simlib.parse_w(log)
    out, final = {}, None
    for h in rb.harts(mask):
        b = 0x1F000 + 0x100 * h
        rows = [(t[0], t[2], a[2], c[2]) for t, a, c in zip(w.get(b, []), w.get(b + 4, []), w.get(b + 8, []))]
        e = {}
        for cyc, tag, a, c in rows:
            if tag == 0x57A7:
                e["t_start"] = cyc
            elif tag == 0xE4D0:
                e["t_end"], e["cycles"], e["instret"] = cyc, a, c
            elif tag == 0xC5C5:
                e["checksum"], e["rank"], e["n"], e["lo"] = a, c & 0xFF, (c >> 8) & 0xFF, c >> 16
            elif tag == 0x4157:
                final = {"hart": h, "bins_checksum": a, "bins_total": c}
        out[h] = e
    stats, cur = [], {}
    for ln in open(log):
        if ln.startswith("S "):
            _, h, t, s, mx = ln.split()
            cur[int(h)] = [int(t), int(s), int(mx)]
            if int(h) == 4:
                stats.append(cur)
                cur = {}
    return out, stats, final


def tagname(kernel, place, isa, mask, stall):
    return "par%s_%s_%s_m%x_d%d" % (kernel, place, isa, mask, stall)


def job(a):
    tag = a.tag or tagname(a.kernel, a.place, a.isa, a.mask, a.stall)
    e = build(tag, a.kernel, a.place, a.isa)
    rcf = rb.compose_image(tag, e["h0"], {h: e["tile"] for h in (1, 2, 3, 4)}, a.mask)
    r = simlib.sim(tag, rcf, stall=a.stall, budget_s=a.budget)
    out = {"tag": tag, "kernel": a.kernel, "nout": NOUT, "ntap": NTAP, "place": a.place, "isa": a.isa, "mask": a.mask,
           "stall": a.stall, "passed": r.passed, "killed": r.killed, "wall_s": round(r.wall, 1)}
    if os.path.exists(r.log):
        p, st, final = parse(r.log, a.mask)
        g = golden(a.kernel)
        ok = True
        for h, v in p.items():
            if "checksum" in v:
                lo, n = v["lo"], NOUT // v["n"]
                v["checksum_ok"] = (v["checksum"] == 0) if a.kernel == "hist" else (v["checksum"] == checksum(g[lo:lo + n]))
            ok = ok and v.get("checksum_ok", False) and "cycles" in v
        if a.kernel == "hist":
            out["final"] = final
            ok = ok and final is not None and final["bins_checksum"] == checksum(g) and final["bins_total"] == NOUT
        out["harts"] = {str(k): v for k, v in p.items()}
        out["arb_run"] = {str(k): v for k, v in st[-1].items()} if len(st) >= 2 else None
        out["all_ok"] = ok and len(p) == bin(a.mask).count("1")
        if out["all_ok"]:
            t0 = min(v["t_start"] for v in p.values())
            t1 = max(v["t_end"] for v in p.values())
            ins = sum(v["instret"] for v in p.values())
            out["wall_cycles"] = t1 - t0
            out["sum_instret"] = ins
            out["agg_ipc"] = ins / (t1 - t0)
            out["agg_cpi"] = (t1 - t0) / ins
    os.makedirs(RES, exist_ok=True)
    json.dump(out, open(os.path.join(RES, tag + ".json"), "w"), indent=1, sort_keys=True)
    print(tag, "passed", r.passed, "ok", out.get("all_ok"), "wall_cyc", out.get("wall_cycles"),
          "aggIPC %.3f" % out["agg_ipc"] if "agg_ipc" in out else "", "sim %.0fs" % r.wall, flush=True)
    return out


def ns(kernel, place, mask, isa="common", stall=0, budget=1800):
    return argparse.Namespace(kernel=kernel, place=place, mask=mask, isa=isa, stall=stall, budget=budget, tag="")


def sweep(a):
    jobs = []
    for kernel in a.kernels:
        for place in a.places:
            for m in [0x01] + SWEEP_MASKS:
                f = os.path.join(RES, tagname(kernel, place, a.isa, m, 0) + ".json")
                if os.path.exists(f) and json.load(open(f)).get("all_ok") and not os.environ.get("FORCE"):
                    continue
                jobs.append((job, (ns(kernel, place, m, a.isa),)))
    simlib.pool(jobs)


def report(a):
    rows = {}
    for f in sorted(glob.glob(os.path.join(RES, "par*_d0.json"))):
        d = json.load(open(f))
        if d.get("all_ok"):
            rows[(d["kernel"], d["place"], d["isa"], d["mask"])] = d
    print("%-5s %-7s %-6s %-5s %2s %10s %8s %7s %7s %8s %9s  per-hart CPI" %
          ("kern", "place", "isa", "mask", "N", "wall_cyc", "speedup", "eff", "aggIPC", "aggCPI", "txn/hart"))
    order = {"fir": 0, "box": 1, "hist": 2}
    for (kernel, place, isa, m), d in sorted(rows.items(), key=lambda k: (order.get(k[0][0], 9), k[0][1], k[0][2],
                                                                           bin(k[0][3]).count("1"), k[0][3])):
        n = bin(m).count("1")
        base = rows.get((kernel, place, isa, 0x02))
        sp = base["wall_cycles"] / d["wall_cycles"] if base else float("nan")
        cpis = " ".join("h%s:%.2f" % (h, v["cycles"] / v["instret"]) for h, v in sorted(d["harts"].items()))
        arb = d.get("arb_run") or {}
        txn = [arb[h][0] for h in d["harts"] if h in arb]
        print("%-5s %-7s %-6s 0x%02x %3d %10d %8.3f %6.1f%% %7.3f %8.3f %9s  %s" %
              (kernel, place, isa, m, n, d["wall_cycles"], sp, 100 * sp / n, d["agg_ipc"], d["agg_cpi"],
               "%d" % (sum(txn) / len(txn)) if txn else "-", cpis))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["one", "sweep", "report", "build"])
    ap.add_argument("--kernel", default="fir", choices=sorted(KERNELS))
    ap.add_argument("--kernels", nargs="+", default=["fir", "box", "hist"])
    ap.add_argument("--place", default="shared", choices=["shared", "tcm"])
    ap.add_argument("--places", nargs="+", default=["shared", "tcm"])
    ap.add_argument("--mask", type=lambda s: int(s, 0), default=0x1F)
    ap.add_argument("--isa", default="common", choices=["common", "native"])
    ap.add_argument("--stall", type=int, default=0)
    ap.add_argument("--budget", type=int, default=1800)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    if a.cmd == "one":
        job(a)
    elif a.cmd == "build":
        e = build("par%s_build_%s" % (a.kernel, a.place), a.kernel, a.place, a.isa)
        for k, v in e.items():
            print(k, rb.size_report(v))
            print({n: hex(x) for n, x in rb.syms(v).items() if n.startswith("__") and "end" in n or n in ("xs", "ys", "fin_count", "main")})
    elif a.cmd == "sweep":
        sweep(a)
    else:
        report(a)


if __name__ == "__main__":
    main()
