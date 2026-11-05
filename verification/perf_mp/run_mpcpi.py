#!/usr/bin/env python3
"""Run the multi-hart CPI sweep and write results/mpcpi.json.

  run_mpcpi.py smoke                 one image, printed
  run_mpcpi.py sweep                 tile hart: nant 0..4 x hammer {lw,sw,fetch}; hart 0: nant 0,4; same-word AMO/LRSC
  run_mpcpi.py negctrl               seeded delays, see README
"""
import json
import os
import sys

import simlib
from simlib import RUN, HERE, PY, MARCH_H0, sh

IMG = os.path.join(RUN, "img")


def build(tag, **kw):
    os.makedirs(IMG, exist_ok=True)
    s, t = "%s/%s.S" % (IMG, tag), "%s/%s.json" % (IMG, tag)
    cmd = [PY, os.path.join(HERE, "gen_mpcpi.py"), "-o", s, "--table", t]
    for k, v in kw.items():
        cmd += ["--" + k.replace("_", "-"), str(v)]
    sh(cmd)
    simlib.gcc(["-march=" + MARCH_H0, "-mabi=ilp32", "-nostdlib", "-nostartfiles", "-static",
                "-T", os.path.join(HERE, "mpcpi.ld"), s, "-o", "%s/%s.elf" % (IMG, tag)])
    simlib.compose("%s/%s.rcf" % (IMG, tag), "%s/%s.elf" % (IMG, tag))
    return json.load(open(t))


def analyse(log, table):
    """-> {kernel: {cyc, ins, marg_cpo, marg_cpi, arb_txn, arb_wait_mean, arb_wait_max}}"""
    meas = table["meas"]
    base = 0x1F000 + 0x100 * meas
    w = simlib.parse_w(log)
    tags = [v for _, _, v in w.get(base, [])]
    cyc = [v for _, _, v in w.get(base + 4, [])]
    ins = [v for _, _, v in w.get(base + 8, [])]
    stats = []
    cur = {}
    for ln in open(log):
        if ln.startswith("S "):
            _, h, t, s, m = ln.split()
            cur[int(h)] = (int(t), int(s), int(m))
            if int(h) == 4:
                stats.append(cur)
                cur = {}
    res = {}
    k = table["kernels"]
    sc_fail = None
    for i, tg in enumerate(tags):
        if tg == 1000:
            sc_fail = cyc[i]
            continue
        e = k[str(tg)]
        res[e["name"]] = {"cyc": cyc[i], "ins": ins[i], "loc": e["loc"], "ops": e["ops"]}
        j = i - (1 if sc_fail is not None else 0)
        if j < len(stats):
            t, s, m = stats[j][meas]
            res[e["name"]].update(arb_txn=t, arb_wait_sum=s, arb_wait_max=m)
            res[e["name"]]["ant_txn"] = sum(stats[j][h][0] for h in table["ants"])
    if sc_fail is not None:
        res["lrscinc_common"]["sc_fail"] = sc_fail
    for n, r in res.items():
        if r["ops"]:
            b = res["empty" if r["loc"] == "t" else "f_empty"]
            r["cpo"] = (r["cyc"] - b["cyc"]) / r["ops"]
            di = r["ins"] - b["ins"]
            r["ipo"] = di / r["ops"]
            r["cpi"] = (r["cyc"] - b["cyc"]) / di if di else None
    return res


def job(tag, stall=0, budget=300, **kw):
    # A finished run is re-analysed, not re-simulated, unless FORCE=1: the log and the table pin what it measured.
    log = os.path.join(RUN, "runs", tag, "sim")
    tb = "%s/%s.json" % (IMG, tag)
    if not os.environ.get("FORCE") and os.path.exists(log + "/xmsim.log") and os.path.exists(tb) \
            and "TEST PASSED" in open(log + "/xmsim.log", errors="replace").read():
        t = json.load(open(tb))
        return tag, {"cfg": {k: t[k] for k in ("meas", "nant", "ants", "ham", "iters", "copies", "extra_nops")},
                     "stall": stall, "passed": True, "killed": False, "wall_s": None,
                     "k": analyse(log + "/perf_mon.log", t)}
    t = build(tag, **kw)
    r = simlib.sim(tag, "%s/%s.rcf" % (IMG, tag), stall=stall, budget_s=budget)
    out = {"cfg": {k: t[k] for k in ("meas", "nant", "ants", "ham", "iters", "copies", "extra_nops")},
           "stall": stall, "passed": r.passed, "killed": r.killed, "wall_s": round(r.wall, 1)}
    if r.passed:
        out["k"] = analyse(r.log, t)
    return tag, out


def show(res):
    for n, r in res["k"].items():
        if r["ops"]:
            print("  %-16s %-2s cyc/op %8.3f  ins/op %5.2f  cpi %s  wait %s/%s" % (
                n, r["loc"], r["cpo"], r["ipo"], "%.3f" % r["cpi"] if r["cpi"] else "-",
                r.get("arb_wait_sum"), r.get("arb_wait_max")))


def sweep():
    jobs = []
    for ham in ("lw", "sw", "fetch"):
        for n in range(0, 5):
            jobs.append((job, ("t1_%s_n%d" % (ham, n), 0, 1200), ))
            jobs[-1] = (lambda tag, ham=ham, n=n: job(tag, 0, 1200, meas=1, nant=n, ham=ham), ("t1_%s_n%d" % (ham, n),))
    for ham in ("amo", "lrsc"):
        for n in (1, 2, 3, 4):
            jobs.append((lambda tag, ham=ham, n=n: job(tag, 0, 1200, meas=1, nant=n, ham=ham), ("t1_%s_n%d" % (ham, n),)))
    for ham, n in (("lw", 0), ("lw", 1), ("lw", 3), ("lw", 4), ("sw", 4), ("fetch", 4)):
        jobs.append((lambda tag, ham=ham, n=n: job(tag, 0, 1200, meas=0, nant=n, ham=ham), ("h0_%s_n%d" % (ham, n),)))
    res = dict(simlib.pool(jobs))
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    json.dump(res, open(os.path.join(HERE, "results", "mpcpi.json"), "w"), indent=0, sort_keys=True)
    bad = [k for k, v in res.items() if not v["passed"]]
    print("runs", len(res), "failed", bad)


def main():
    c = sys.argv[1]
    if c == "setup":
        simlib.setup()
    elif c == "smoke":
        tag, r = job("smoke", meas=int(sys.argv[2]), nant=int(sys.argv[3]), ham=sys.argv[4])
        print(r["cfg"], r["passed"], r["killed"], r["wall_s"])
        if r["passed"]:
            show(r)
    elif c == "sweep":
        sweep()
    elif c == "negctrl":
        jobs = [(lambda: job("t1_lw_n0_d3", 3, 1200, meas=1, nant=0, ham="lw"), ()),
                (lambda: job("nc_nops", 0, 1200, meas=1, nant=0, ham="lw", extra_nops=5), ()),
                (lambda: job("t1_lw_n4_d3", 3, 1200, meas=1, nant=4, ham="lw"), ())]
        res = dict(simlib.pool(jobs))
        json.dump(res, open(os.path.join(HERE, "results", "negctrl.json"), "w"), indent=0, sort_keys=True)
        print({k: v["passed"] for k, v in res.items()})


if __name__ == "__main__":
    main()
