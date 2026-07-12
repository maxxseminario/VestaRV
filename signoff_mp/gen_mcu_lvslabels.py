#!/usr/bin/env python3
"""PG4: generate pvs/MCU.lvslabels from pvs/hart_tile.lvslabels.

The VDD_SW virtual-connect texts live only in the LVS working GDS (lvs.sh
injects them post-strmout) -- the harden's out/hart_tile.gds2 carries NO
texts, so nothing survives the assembly merge (verified: 0 "VDD_SW:"
occurrences in the tile GDS). The MCU LVS therefore needs its own labels,
transformed to the four tile placements.

NAMING: VDD_SW is tile-INTERNAL (no LEF pin, absent from MCU.lvs.v), so
after Pegasus flattening each tile's switched rail is a SEPARATE schematic
net. The four tiles get DISTINCT text names (VDD_SW_H<h>) -- one shared
name would virtual-connect the rails ACROSS tiles into one layout net and
manufacture a 4-net short against the schematic. NOTE the names alone do
NOT bind the compare: hierarchical texts (Xhart0/VDD_SW) are rejected as
net names (slash), and even a clean flat name never seeds a match to a
DIFFERENT schematic name -- without binding, the matcher cannot anchor
four topologically identical switched-rail networks and the dead-wrapper
class (504/tile) + all 1027 hart0 headers unmatch. The binding is done by
`lvs_cpoint VDD_SW_H<h> Xhart<h>/VDD_SW` rules in pvs/lvs_mcu_ctl (passed
by accept_mcu.sh) -- keep the label names and the cpoint rules in sync.

Placements from tcl/MCU_MP.innovus.tcl (placeInstance is bbox-LL):
  TILE_X0=20 PITCH=663 TILE_Y=1700-1-1050=649 W=660
  hart0/hart1 = R0 -> (X + x, 649 + y)
  hart2/hart3 = MY -> (X + W - x, 649 + y)

Usage: gen_mcu_lvslabels.py [tile_labels] [out]  (defaults below)
"""
import sys

TILES = [  # (label suffix, X_ll, orient)
    ("H0", 20.0, "R0"),
    ("H1", 683.0, "R0"),
    ("H2", 1346.0, "MY"),
    ("H3", 2009.0, "MY"),
]
TILE_Y = 649.0
TILE_W = 660.0

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "pvs/hart_tile.lvslabels"
    dst = sys.argv[2] if len(sys.argv) > 2 else "pvs/MCU.lvslabels"
    pts = []
    for ln in open(src):
        parts = ln.split()
        if len(parts) >= 4:
            pts.append((int(parts[0]), float(parts[1]), float(parts[2]), parts[3]))
    with open(dst, "w") as f:
        for suffix, x0, orient in TILES:
            for layer, x, y, text in pts:
                base = text.rstrip(":")
                gx = x0 + (TILE_W - x if orient == "MY" else x)
                gy = TILE_Y + y
                f.write(f"{layer} {gx:.3f} {gy:.3f} {base}_{suffix}:\n")
    print(f"wrote {4*len(pts)} labels ({len(pts)} per tile) to {dst}")

if __name__ == "__main__":
    main()
