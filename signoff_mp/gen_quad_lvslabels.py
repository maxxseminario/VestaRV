#!/usr/bin/env python3
"""CQ6: generate pvs/chip_top_quad.lvslabels from pvs/hart_tile.lvslabels.
NEW quad-named copy of gen_mcu_lvslabels.py (C0/PG4), with the CQ 4-corner,
2-axis-mirrored tile placements (cq_architecture.md SS2 + tcl/chip_top_quad.
innovus.tcl). mcu0 sits at chip (0,0) (assembly fills the interior), so MCU
coords == chip coords -- no extra offset.

Placements (bbox-LL, orient) from the CQ3a table:
  hart0 top-left     R0    x0=20   y0=1638
  hart1 top-right    MY    x0=2009 y0=1638
  hart2 bottom-left  MX    x0=20   y0=1
  hart3 bottom-right R180  x0=2009 y0=1
  tile W=660 H=1050

Tile-relative point (x,y) -> chip coords under orientation:
  R0   : (x0 + x,       y0 + y)
  MY   : (x0 + W - x,   y0 + y)          # mirror about Y (flip x)
  MX   : (x0 + x,       y0 + H - y)      # mirror about X (flip y)
  R180 : (x0 + W - x,   y0 + H - y)      # flip both

NAMING (PG4 rule, unchanged): each tile's switched rail is a SEPARATE schematic
net after Pegasus flattening, so the four tiles get DISTINCT text names
(VDD_SW_H<h>); a shared name would virtual-connect the rails ACROSS tiles into
one layout net and manufacture a 4-net short. Binding to the schematic is done
by lvs_cpoint VDD_SW_H<h> "Xmcu0/Xhart<h>/VDD_SW" in pvs/lvs_chip_quad_ctl --
keep names + cpoints in sync. The substrate-merged grounds are NEVER labeled
(POWER-LABEL TRAP): they reduce via deck CONNECT / global names, not texts.

Usage: gen_quad_lvslabels.py [tile_labels] [out]
"""
import sys

TILE_W = 660.0
TILE_H = 1050.0
TILES = [  # (suffix, x0, y0, orient)
    ("H0",   20.0, 1638.0, "R0"),
    ("H1", 2009.0, 1638.0, "MY"),
    ("H2",   20.0,    1.0, "MX"),
    ("H3", 2009.0,    1.0, "R180"),
]

def xform(x, y, x0, y0, orient):
    if orient == "R0":
        return x0 + x, y0 + y
    if orient == "MY":
        return x0 + TILE_W - x, y0 + y
    if orient == "MX":
        return x0 + x, y0 + TILE_H - y
    if orient == "R180":
        return x0 + TILE_W - x, y0 + TILE_H - y
    raise ValueError(orient)

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "pvs/hart_tile.lvslabels"
    dst = sys.argv[2] if len(sys.argv) > 2 else "pvs/chip_top_quad.lvslabels"
    pts = []
    for ln in open(src):
        parts = ln.split()
        if len(parts) >= 4:
            pts.append((int(parts[0]), float(parts[1]), float(parts[2]), parts[3]))
    with open(dst, "w") as f:
        for suffix, x0, y0, orient in TILES:
            for layer, x, y, text in pts:
                base = text.rstrip(":")
                gx, gy = xform(x, y, x0, y0, orient)
                f.write(f"{layer} {gx:.3f} {gy:.3f} {base}_{suffix}:\n")
    print(f"wrote {4*len(pts)} labels ({len(pts)} per tile) to {dst}")

if __name__ == "__main__":
    main()
