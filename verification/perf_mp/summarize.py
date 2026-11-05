#!/usr/bin/env python3
"""Print the report tables from results/*.json.  summarize.py [cpi|amo|irq|bench|negctrl]"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(HERE, "results")


def load(n):
    return json.load(open(os.path.join(R, n)))


def cpo(run, k):
    v = run.get("k", {}).get(k)
    return None if v is None or "cpo" not in v else v["cpo"]


def cpi():
    d = load("mpcpi.json")
    print("failed:", [k for k, v in d.items() if not v["passed"]])
    rows = ["alu32", "alu16", "lw_tcm", "sw_tcm", "br_t", "br_nt", "jal", "csrr", "lw_sh", "sw_sh", "lb_sh", "sb_sh",
            "lw_npu", "lw_rom", "lw_clint", "f_alu32", "f_alu16", "f_lw_tcm", "f_sw_tcm", "f_lw_sh", "f_br_t"]
    for ham in ("lw", "sw", "fetch"):
        print("\nhammer", ham, "| cycles per op, n other harts = 0 1 2 3 4")
        for k in rows:
            vals = [cpo(d.get("t1_%s_n%d" % (ham, n), {}), k) for n in range(5)]
            print("  %-10s" % k + " ".join("%8.2f" % v if v is not None else "       -" for v in vals))
    print("\narbiter wait per transaction (mean, max) for lw_sh under lw hammer")
    for n in range(5):
        r = d.get("t1_lw_n%d" % n, {}).get("k", {}).get("lw_sh", {})
        if r:
            print("  n=%d txn %d mean %.2f max %d ant_txn %d" % (n, r["arb_txn"], r["arb_wait_sum"] / r["arb_txn"], r["arb_wait_max"], r["ant_txn"]))
    print("\nhart 0 measured")
    for t in ("h0_lw_n0", "h0_lw_n1", "h0_lw_n3", "h0_lw_n4", "h0_sw_n4", "h0_fetch_n4"):
        r = d.get(t, {})
        print("  %-12s" % t + " ".join("%s=%.2f" % (k, cpo(r, k)) for k in ("alu32", "lw_tcm", "lw_sh", "sw_sh", "f_alu32", "mul", "div", "rem", "zbb", "amoadd_sh") if cpo(r, k) is not None))


def amo():
    d = load("mpcpi.json")
    ks = ["amoadd_tcm", "amoswap_tcm", "lrsc_tcm", "amoadd_sh", "amoswap_sh", "lrsc_sh", "amoadd_common", "lrscinc_common"]
    for ham in ("lw", "sw", "fetch", "amo", "lrsc"):
        print("hammer", ham)
        for k in ks:
            out = []
            for n in range(5):
                t = d.get("t1_%s_n%d" % (ham, n))
                v = cpo(t, k) if t else None
                f = t["k"][k].get("sc_fail") if t and t.get("k") and k in t["k"] else None
                out.append("%7.1f" % v + ("/%d" % f if f is not None else "") if v is not None else "      -")
            print("  %-15s" % k + " ".join(out))


def irq():
    d = load("irqlat.json")
    print("failed:", [k for k, v in d.items() if not v["passed"]])
    for t in sorted(d):
        r = d[t]
        if not r["passed"]:
            continue
        print(t)
        for n, s in r["v"].items():
            print("  %-12s n=%3d min %3d med %3d mean %6.1f p99 %3d max %3d entry %d..%d tail %d..%d" % (
                n, s["n"], s["min"], s["median"], s["mean"], s["p99"], s["max"], s["rec_min"], s["rec_max"], s["tail_min"], s["tail_max"]))


def bench():
    for f in sorted(glob.glob(os.path.join(R, "bench", "*.json"))):
        d = json.load(open(f))
        print(d["tag"], "passed", d["passed"], "killed", d["killed"], "wall", d["wall_s"])
        for h, v in sorted(d.get("harts", {}).items()):
            print("   h%s" % h, {k: (round(x, 4) if isinstance(x, float) else x) for k, x in v.items() if k != "log"})
        if d.get("arb") and len(d["arb"]) >= 2:
            print("   arb(window)", d["arb"][1])


def negctrl():
    d = load("negctrl.json")
    base = load("mpcpi.json")
    for tag, ref in (("t1_lw_n0_d3", "t1_lw_n0"), ("nc_nops", "t1_lw_n0"), ("t1_lw_n4_d3", "t1_lw_n4")):
        print(tag, "vs", ref)
        for k in ("alu32", "lw_tcm", "lw_sh", "sw_sh", "lw_npu", "lw_rom", "f_alu32", "f_alu16", "f_lw_sh", "amoadd_sh", "lrsc_sh"):
            a, b = cpo(base[ref], k), cpo(d[tag], k)
            print("  %-10s %8.3f -> %8.3f  delta %+.3f" % (k, a, b, b - a))


{"cpi": cpi, "amo": amo, "irq": irq, "bench": bench, "negctrl": negctrl}[sys.argv[1]]()
