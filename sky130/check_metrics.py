#!/usr/bin/env python3
# check_metrics.py -- signoff gate for the LibreLane sky130 flow.
#
# The flow's logs print mid-run STA at nom_tt only and "pretty" slack numbers
# that do not survive extraction (see config.yaml's timing recipe) -- signoff
# is verified HERE, from runs/<tag>/final/metrics.json, and nowhere else.
#
#   python3 check_metrics.py runs/<tag>/final/metrics.json
#
# Exit 0 only if every gate metric below is present and exactly zero. A missing
# key is a FAIL, not a skip: a metrics.json without a DRC count means the DRC
# step did not run, which is worse than a nonzero count.
# Python 3.6 compatible; no external deps.
from __future__ import print_function
import io
import json
import sys

# Metric -> what a nonzero value means. The six are the signoff definition from
# sky130/README.md ("magic DRC 0 / KLayout DRC 0 / LVS 0 / setup and hold clean
# at all 9 corners").
GATES = [
    ("magic__drc_error__count", "magic DRC errors"),
    ("klayout__drc_error__count", "KLayout DRC errors"),
    ("design__lvs_error__count", "netgen LVS errors"),
    ("route__antenna_violation__count", "antenna violations after repair"),
    ("timing__setup_vio__count", "setup-violating endpoints (all corners)"),
    ("timing__hold_vio__count", "hold-violating endpoints (all corners)"),
]

# Context printed when present; never gated. Worst slacks tell you HOW clean
# the timing is, instance/area tell you the run actually built the whole core.
INFO = [
    "timing__setup__ws",
    "timing__hold__ws",
    "design__instance__count",
    "design__die__area",
    "route__wirelength",
    "power__total",
]


def main(argv):
    if len(argv) != 2:
        print("usage: check_metrics.py <path/to/final/metrics.json>", file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with io.open(path, "r", encoding="utf-8") as f:
            metrics = json.load(f)
    except (IOError, OSError) as e:
        print("FAIL: cannot read %s: %s" % (path, e))
        return 1
    except ValueError as e:
        print("FAIL: %s does not parse as JSON: %s" % (path, e))
        return 1

    print("signoff gate : %s" % path)
    failures = 0
    for key, meaning in GATES:
        if key not in metrics:
            print("FAIL: %-36s MISSING (%s)" % (key, meaning))
            failures += 1
            continue
        value = metrics[key]
        if value == 0:
            print("OK  : %-36s = 0" % key)
        else:
            print("FAIL: %-36s = %s (%s)" % (key, value, meaning))
            failures += 1

    present = [k for k in INFO if k in metrics]
    if present:
        print("---- context (not gated) ----")
        for key in present:
            print("      %-36s = %s" % (key, metrics[key]))

    if failures:
        print("FAILED: %d signoff metric(s) violated or missing" % failures)
        return 1
    print("PASS: signoff clean (all %d gate metrics zero)" % len(GATES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
