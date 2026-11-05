#!/usr/bin/env python3
"""Gate: compare a measured run against expected_mp.json. Exact on the deterministic rows.

  check_results.py results/mpcpi.json t1_lw_n0       -> rc 0 on match, rc 1 with a per-row diff
  check_results.py --pin results/mpcpi.json t1_lw_n0 writes the pin (owner action, like re-recording expected.json)

Pins only the uncontended runs: with no other master every cycle count is a pure function of the RTL, so any difference
is a change. Contended rows depend on round-robin phase and are reported, not gated. The seeded fault is the 3-cycle
arbiter stall in perf_mon (STALL_D): run the same image on snapshot perf_d3 and this must fail on exactly the rows that
touch the shared bulk RAM.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PIN = os.path.join(HERE, "expected_mp.json")


def rows(run):
    return {k: (v["cyc"], v["ins"]) for k, v in run["k"].items()}


def main():
    a = sys.argv[1:]
    pin = a and a[0] == "--pin"
    if pin:
        a = a[1:]
    src, tag = a[0], a[1]
    run = json.load(open(src))[tag]
    if not run.get("passed"):
        print("run did not pass")
        return 1
    if pin:
        d = json.load(open(PIN)) if os.path.exists(PIN) else {}
        d[tag.split("_d")[0]] = rows(run)
        json.dump(d, open(PIN, "w"), indent=0, sort_keys=True)
        return 0
    exp = json.load(open(PIN))[tag.split("_d")[0]]
    got = rows(run)
    bad = 0
    for k in sorted(exp):
        e, g = exp[k], list(got.get(k, (None, None)))
        if list(e) != g:
            print("%-16s expected %s measured %s delta %s" % (k, e, g, g[0] - e[0] if g[0] is not None else "-"))
            bad += 1
    print("%d/%d rows match" % (len(exp) - bad, len(exp)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
