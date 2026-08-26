#!/usr/bin/env python3
"""chip_top_dp (G2, LQFP-100) variant of patch_chip_pads.py: bind the pinless
IO-domain supply/POC pads AND the ARSV0-7 analog-reserve pads' AIO terminals
in the saveNetlist LVS verilog (in place, idempotent). DP instance names are
the generator-emission names uniquified per side (PAD_VDDPST_0/1/2 etc.);
ARSV pads get distinct one-pin nets (both sides then carry the same floating
single-pin net). Core PVDD1DGZ_G/PVSS1DGZ_G stay untouched (gnc handles them).

Usage: patch_chip_pads_dp.py <netlist.v>
"""
import re, sys

BIND = {
    "PAD_VDDPST_0": ("VDDPST", "VDDPST"),
    "PAD_VSSPST_0": ("VSSPST", "VSSPST"),
    "PAD_VDDPST_1": ("VDDPST", "VDDPST"),
    "PAD_VSSPST_1": ("VSSPST", "VSSPST"),
    "PAD_VDDPST_2": ("VDDPST", "VDDPST"),
    "PAD_VSSPST_2": ("VSSPST", "VSSPST"),
    "PAD_AVDD":    ("AVDD",   "AVDD"),
    "PAD_AVSS":    ("AVSS",   "AVSS"),
    "PAD_POC":     ("VDDPST", "VDDPST"),
    "PAD_ARSV0":   ("AIO",    "ARSV0"),
    "PAD_ARSV1":   ("AIO",    "ARSV1"),
    "PAD_ARSV2":   ("AIO",    "ARSV2"),
    "PAD_ARSV3":   ("AIO",    "ARSV3"),
    "PAD_ARSV4":   ("AIO",    "ARSV4"),
    "PAD_ARSV5":   ("AIO",    "ARSV5"),
    "PAD_ARSV6":   ("AIO",    "ARSV6"),
    "PAD_ARSV7":   ("AIO",    "ARSV7"),
}

def main():
    path = sys.argv[1]
    txt = open(path).read()
    n = 0
    for inst, (pin, net) in BIND.items():
        # match "<CELL> <inst> (\n);"  (empty pin list) -> insert the binding.
        # idempotent: skip if already bound.
        pat = re.compile(r"(\b[A-Z0-9_]+\s+" + re.escape(inst) + r"\s*\(\s*)\)\s*;", re.M)
        def repl(m):
            return m.group(1) + f".{pin}({net}));"
        new, k = pat.subn(repl, txt)
        if k:
            txt = new; n += k
        elif f".{pin}({net})" in txt and inst in txt:
            pass  # already patched
    open(path, "w").write(txt)
    print(f"patch_chip_pads_dp: bound {n} IO-supply pad(s) in {path}")

if __name__ == "__main__":
    main()
