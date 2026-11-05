#!/usr/bin/env python3
"""Interrupt-latency matrix -> results/irqlat.json.  run_irqlat.py smoke | matrix"""
import json
import os
import sys

import simlib
from simlib import RUN, HERE, PY, MARCH_H0, sh

IMG = os.path.join(RUN, "img")


def build(tag, **kw):
    os.makedirs(IMG, exist_ok=True)
    s, t = "%s/%s.S" % (IMG, tag), "%s/%s.json" % (IMG, tag)
    cmd = [PY, os.path.join(HERE, "gen_irqlat.py"), "-o", s, "--table", t]
    for k, v in kw.items():
        cmd += ["--" + k, str(v)]
    sh(cmd)
    simlib.gcc(["-march=" + MARCH_H0, "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
                "-T", os.path.join(HERE, "irqlat.ld"), s, "-o", "%s/%s.elf" % (IMG, tag)])
    simlib.compose("%s/%s.rcf" % (IMG, tag), "%s/%s.elf" % (IMG, tag))
    return json.load(open(t))


def analyse(log, tb):
    meas = tb["meas"]
    base = 0x1F000 + 0x100 * meas
    marks = [(c, v) for c, _, v in simlib.parse_w(log).get(base, [])]
    groups = {}
    for ln in open(log):
        if ln.startswith("L "):
            _, h, tl, te, ti, pc, src = ln.split()
            if int(h) != meas or src != "t":
                continue
            tl, te, ti = int(tl), int(te), int(ti)
            v = None
            for c, tag in marks:
                if c <= tl:
                    v = tag
            if v is None:
                continue
            groups.setdefault(tb["victims"][v - 1], []).append((ti - tl, te - tl, ti - te, pc))
    out = {}
    for name, rows in groups.items():
        lat = sorted(r[0] for r in rows)
        rec = sorted(r[1] for r in rows)
        n = len(lat)
        worst = max(rows, key=lambda r: r[0])
        out[name] = {"n": n, "min": lat[0], "median": lat[n // 2], "mean": round(sum(lat) / n, 2),
                     "p99": lat[min(n - 1, int(n * 0.99))], "max": lat[-1],
                     "rec_min": rec[0], "rec_max": rec[-1],
                     "tail_min": min(r[2] for r in rows), "tail_max": max(r[2] for r in rows),
                     "worst_pc": worst[3]}
    return out


def job(tag, stall=0, budget=900, **kw):
    t = build(tag, **kw)
    r = simlib.sim(tag, "%s/%s.rcf" % (IMG, tag), stall=stall, budget_s=budget)
    res = {"cfg": t, "stall": stall, "passed": r.passed, "killed": r.killed, "wall_s": round(r.wall, 1)}
    if r.passed:
        res["v"] = analyse(r.log, t)
    return tag, res


def show(r):
    for n, s in r["v"].items():
        print("  %-12s n=%3d min %3d med %3d mean %6.1f p99 %3d max %3d | entry %d..%d tail %d..%d pc %s" % (
            n, s["n"], s["min"], s["median"], s["mean"], s["p99"], s["max"], s["rec_min"], s["rec_max"],
            s["tail_min"], s["tail_max"], s["worst_pc"]))


def matrix():
    jobs = []
    for mode in ("legacy", "std"):
        for meas in (1, 0):
            for ham, n in (("lw", 0), ("lw", 4), ("sw", 4), ("amo", 4), ("fetch", 4)):
                tag = "irq_%s_h%d_%s_n%d" % (mode, meas, ham, n)
                jobs.append((lambda tag=tag, mode=mode, meas=meas, ham=ham, n=n:
                             job(tag, mode=mode, meas=meas, ham=ham, nant=n, trials=256), ()))
        # the legacy push goes through the arbiter when sp is in the shared window
    for meas in (1, 0):
        for ham, n in (("lw", 0), ("amo", 4)):
            tag = "irq_legacysp_h%d_%s_n%d" % (meas, ham, n)
            jobs.append((lambda tag=tag, meas=meas, ham=ham, n=n:
                         job(tag, mode="legacy", meas=meas, ham=ham, nant=n, trials=256, stack="sh"), ()))
    res = dict(simlib.pool(jobs))
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    json.dump(res, open(os.path.join(HERE, "results", "irqlat.json"), "w"), indent=0, sort_keys=True)
    print("runs", len(res), "failed", [k for k, v in res.items() if not v["passed"]])


def main():
    if sys.argv[1] == "smoke":
        tag, r = job("irqsmoke", meas=sys.argv[2], mode=sys.argv[3], nant=sys.argv[4], ham=sys.argv[5], trials=64)
        print(r["passed"], r["killed"], r["wall_s"])
        if r["passed"]:
            show(r)
    elif sys.argv[1] == "negctrl":
        tag, r = job("irq_nc_d3", stall=3, mode="legacy", meas=1, ham="lw", nant=0, trials=256)
        json.dump({tag: r}, open(os.path.join(HERE, "results", "irq_negctrl.json"), "w"), indent=0, sort_keys=True)
        show(r)
    else:
        matrix()


if __name__ == "__main__":
    main()
