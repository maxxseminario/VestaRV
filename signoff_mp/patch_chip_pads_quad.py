#!/usr/bin/env python3
"""CQ6: bind the pinless IO-domain + analog supply/POC pad instances of
chip_top_quad to their named power rails in the saveNetlist LVS verilog
(in place, idempotent). NEW quad-named copy of patch_chip_pads.py (C0).

WHY (unchanged from C0): chip_top_quad.v instantiates the IO/analog-domain
supply pads pinless (`PVDD2DGZ_G PAD_vddpst_t ();`) -- they are ring-bus rails
by pad/filler abutment (Option A: continuous digital+analog buses, NO ring
cuts), NOT netlist-wired. saveNetlist emits them with an empty pin list; LVS
needs them bound to named nets so the layout ring matches a schematic net.
All of VDDPST/VSSPST/AVDD/AVSS are in the PVS deck POWER_NAME/GROUND_NAME lists
so they virtual-connect globally.

CQ DELTAS vs C0:
  * instance names differ (split TOP/BOTTOM IO supplies; per-quadrant analog).
  * 4x PVDD2ANA_G (PAD_avdd_0..3) + 4x PVSS2ANA_G (PAD_avss_0..3): C0 had ONE
    AVDD + ONE AVSS pad. Option A keeps the analog stretch's ring metal
    CONTINUOUS by abutment (no PRCUT), so all four AVDD pads sit on ONE AVDD
    ring net and all four AVSS on ONE AVSS ring net -- the "per-quadrant
    AVDD_h/AVSS_h" naming is a floorplan label, electrically one ring bus each.
    Bind all four of each to the single AVDD/AVSS global (the ring-bus reality;
    exactly C0's single pair scaled up).
  * core PVDD1DGZ_G/PVSS1DGZ_G (PAD_vdd_l/r, PAD_vss_l/r) carry VDD/VSS from the
    flow globalNetConnect (USE POWER/GROUND) -- left untouched, as in C0.

Usage: patch_chip_pads_quad.py <netlist.v>
"""
import re, sys

# instance-name -> (subckt-pin, net)
BIND = {
    "PAD_vddpst_t": ("VDDPST", "VDDPST"),
    "PAD_vddpst_b": ("VDDPST", "VDDPST"),
    "PAD_vsspst_t": ("VSSPST", "VSSPST"),
    "PAD_vsspst_b": ("VSSPST", "VSSPST"),
    "PAD_avdd_0":   ("AVDD",   "AVDD"),
    "PAD_avdd_1":   ("AVDD",   "AVDD"),
    "PAD_avdd_2":   ("AVDD",   "AVDD"),
    "PAD_avdd_3":   ("AVDD",   "AVDD"),
    "PAD_avss_0":   ("AVSS",   "AVSS"),
    "PAD_avss_1":   ("AVSS",   "AVSS"),
    "PAD_avss_2":   ("AVSS",   "AVSS"),
    "PAD_avss_3":   ("AVSS",   "AVSS"),
    "PAD_poc":      ("VDDPST", "VDDPST"),   # POC pad taps VDDPST (Myshkin precedent)
}

def main():
    path = sys.argv[1]
    txt = open(path).read()
    n = 0
    for inst, (pin, net) in BIND.items():
        pat = re.compile(r"(\b[A-Z0-9_]+\s+" + re.escape(inst) + r"\s*\(\s*)\)\s*;", re.M)
        def repl(m):
            return m.group(1) + f".{pin}({net}));"
        new, k = pat.subn(repl, txt)
        if k:
            txt = new; n += k
        elif f".{pin}({net})" in txt and inst in txt:
            pass  # already patched
    open(path, "w").write(txt)
    print(f"patch_chip_pads_quad: bound {n} IO/analog-supply pad(s) in {path}")

if __name__ == "__main__":
    main()
