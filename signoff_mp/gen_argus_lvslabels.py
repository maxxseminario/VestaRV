#!/usr/bin/env python3
"""Argus A6: generate pvs/chip_top_argus.lvslabels (VDD_SW_H0..17) from the
Argus tile's pvs/hart_tile_argus.lvslabels, transformed to the 18 tile
placements of the chip_top_argus floorplan.

Argus (18-tile) analogue of gen_mcu_lvslabels.py (4-tile Castalia). VDD_SW is
tile-INTERNAL (no LEF pin, absent from the chip netlist) so after Pegasus
flattening each tile's switched rail is a SEPARATE schematic net -> each tile
gets a DISTINCT text name VDD_SW_H<h>; the source binding is the
`lvs_cpoint VDD_SW_H<h> Xmcu0/Xhart<h>/VDD_SW` rules in pvs/lvs_chip_argus_ctl
(keep names + cpoints in sync).

PLACEMENTS ARE TAKEN FROM THE ACTUAL CHIP DB, NOT the MCU_ARGUS tcl constants:
the A6 re-cut / legalization shifts rows off the nominal Y_R* (row0/1 by -3 um,
row2 by +4 um) and the tcl coords would mis-place every label. The table
pvs/argus_tile_placements.txt is dumped by tcl/dump_argus_tile_placements.tcl
(`h orient x1 y1 x2 y2` = box-LL/UR + orient of mcu0/hart<h>). mcu0 sits at chip
(0,0) so these box coords are already chip-absolute (== MCU coords).

The tile fPlan box is (0,0)-(405,685) (verified), so the dumped tile-local piece
coords are already bbox-relative -- no tile-LL subtraction needed. placeInstance
bbox-LL convention: box-LL (x1,y1) is where the LEF origin lands; W=x2-x1,
H=y2-y1; orient reflects the cell within [x1,x1+W] x [y1,y1+H].

Usage: gen_argus_lvslabels.py [tile_labels] [placement_table] [out]
"""
import sys


def transform(orient, x1, y1, W, H, x, y):
    # local (x,y) in [0,W]x[0,H] -> chip-absolute under placeInstance orient
    if orient == "R0":
        return x1 + x, y1 + y
    if orient == "MX":            # mirror-Y (preserves X)
        return x1 + x, y1 + (H - y)
    if orient == "MY":            # mirror-X (preserves Y)
        return x1 + (W - x), y1 + y
    if orient == "R180":
        return x1 + (W - x), y1 + (H - y)
    raise ValueError(f"unsupported orient {orient}")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "pvs/hart_tile_argus.lvslabels"
    tbl = sys.argv[2] if len(sys.argv) > 2 else "pvs/argus_tile_placements.txt"
    dst = sys.argv[3] if len(sys.argv) > 3 else "pvs/chip_top_argus.lvslabels"

    pts = []
    for ln in open(src):
        p = ln.split()
        if len(p) >= 4:
            pts.append((int(p[0]), float(p[1]), float(p[2]), p[3]))

    placements = []
    for ln in open(tbl):
        p = ln.split()
        if len(p) >= 6:
            h = int(p[0]); orient = p[1]
            x1, y1, x2, y2 = map(float, p[2:6])
            placements.append((h, orient, x1, y1, x2 - x1, y2 - y1))
    placements.sort()

    n = 0
    with open(dst, "w") as f:
        for h, orient, x1, y1, W, H in placements:
            for layer, x, y, text in pts:
                base = text.rstrip(":")
                gx, gy = transform(orient, x1, y1, W, H, x, y)
                f.write(f"{layer} {gx:.3f} {gy:.3f} {base}_H{h}:\n")
                n += 1
    print(f"wrote {n} labels ({len(pts)} per tile x {len(placements)} tiles) to {dst}")


if __name__ == "__main__":
    main()
