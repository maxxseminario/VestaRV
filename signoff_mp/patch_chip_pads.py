#!/usr/bin/env python3
"""Connect the chip-top IO-domain supply/POC pad instances to their named
power rails in the saveNetlist LVS verilog (in place, idempotent).

WHY: chip_top.v instantiates the IO-domain supply pads pinless
(`PVDD2DGZ_G PAD_vddio_0 ();`) -- they are ring-bus rails by pad/filler
abutment, NOT netlist-wired (see chip_top.v comment + the Innovus
verifyConnectivity contract). saveNetlist therefore emits them with an empty
pin list. LVS needs them bound to named nets so the layout ring (which the
flattened GDS DOES carry as metal) matches a schematic net. Following the
Myshkin vesta_chip padded-chip schematic (XPadVDDPST->VDDPST,
XPadVSSPST->VSSPST, XPadPOC->VDDPST, XPadAVDD->AVDD/TAVDD, XPadAVSS->AVSS),
each pad's single power pin binds to the same-named global rail; all of
VDDPST/VSSPST/AVDD/AVSS are in the PVS deck POWER_NAME/GROUND_NAME lists so
they virtual-connect globally. Core-domain PVDD1DGZ_G/PVSS1DGZ_G already
carry VDD/VSS from the flow globalNetConnect -- left untouched.

Usage: patch_chip_pads.py <netlist.v>
"""
import re, sys

# instance-name -> (subckt-pin, net)
BIND = {
    "PAD_vddio_0": ("VDDPST", "VDDPST"),
    "PAD_vddio_1": ("VDDPST", "VDDPST"),
    "PAD_vssio_0": ("VSSPST", "VSSPST"),
    "PAD_vssio_1": ("VSSPST", "VSSPST"),
    "PAD_avdd":    ("AVDD",   "AVDD"),
    "PAD_avss":    ("AVSS",   "AVSS"),
    "PAD_poc":     ("VDDPST", "VDDPST"),   # POC pad taps VDDPST (Myshkin precedent)
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
    print(f"patch_chip_pads: bound {n} IO-supply pad(s) in {path}")

if __name__ == "__main__":
    main()
