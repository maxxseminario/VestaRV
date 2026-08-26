#!/usr/bin/env python3
# A7-1 DEF-level evidence for the v5/A7 chip_top floorplan trial.
# Parses the saved DEF (chip_top_argus_a7fp.innovus.def[.gz]) and proves:
#  (1) each of the 18 tiles mcu0/hartH is PLACED at x in {30+445c}, one of the
#      three v5 row y's {565.085,1268.085,1971.085}, orient N (=R0);
#  (2) a same-net M7 SPECIAL wire (a vertical lane) exists at every tile PG pin
#      stripe x: VDD at cx+51+50k, VSS at cx+60+50k, cx=30+445c, k=0..6.
# Usage: python3 a7fp_def_evidence.py <def_path> [tol_um]
import sys, gzip, re

TILE_W = 405.0
GAP = (2690.0 - 2*30.0 - 6*405.0) / 5.0   # 40.0
COLS = [30.0 + c*(TILE_W+GAP) for c in range(6)]     # 30,475,920,1365,1810,2255
ROWS = [565.085, 1268.085, 1971.085]

def openf(p):
    return gzip.open(p, 'rt') if p.endswith('.gz') else open(p, 'r')

def main():
    if len(sys.argv) < 2:
        print("usage: a7fp_def_evidence.py <def> [tol_um]"); sys.exit(2)
    path = sys.argv[1]
    tol = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
    txt = openf(path).read()

    # UNITS DISTANCE MICRONS <n>
    m = re.search(r'UNITS\s+DISTANCE\s+MICRONS\s+(\d+)', txt)
    units = int(m.group(1)) if m else 2000
    def u(v): return float(v)/units

    # ---- COMPONENTS: 18 tiles ----
    comp = re.search(r'COMPONENTS\s+\d+\s*;(.*?)END COMPONENTS', txt, re.S)
    cbody = comp.group(1) if comp else ""
    placed = {}
    # - mcu0/hartH hart_tile ... + (PLACED|FIXED) ( x y ) ORIENT ;
    for mm in re.finditer(r'-\s+(\S+)\s+hart_tile\b.*?\+\s+(?:PLACED|FIXED)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)', cbody, re.S):
        placed[mm.group(1)] = (u(mm.group(2)), u(mm.group(3)), mm.group(4))

    print("=== 18-TILE PLACEMENT (DEF COMPONENTS) ===")
    print(f"# DEF units/micron = {units}; tol = {tol} um")
    tiles_ok = True
    for h in range(18):
        nm = f"mcu0/hart{h}"
        if nm not in placed:
            print(f"{nm}: NOT FOUND"); tiles_ok = False; continue
        x, y, o = placed[nm]
        xok = any(abs(x-c) <= tol for c in COLS)
        yok = any(abs(y-r) <= tol for r in ROWS)
        ook = (o == 'N')   # DEF orient N == innovus R0
        col = min(range(6), key=lambda c: abs(x-COLS[c]))
        row = min(range(3), key=lambda r: abs(y-ROWS[r]))
        good = xok and yok and ook
        tiles_ok = tiles_ok and good
        print(f"{nm}: x={x:.3f} y={y:.3f} orient={o}  col{col} row{row}  "
              f"[x{'OK' if xok else 'BAD'} y{'OK' if yok else 'BAD'} orient{'OK' if ook else 'BAD'}]")
    print(f"ALL_18_TILES_OK = {tiles_ok}\n")

    # ---- SPECIALNETS: collect VDD/VSS M7 vertical lane x's ----
    # Grab each specialnet block: - VDD ( ... ) ... ; up to next '- ' or END
    sn = re.search(r'SPECIALNETS\s+\d+\s*;(.*?)END SPECIALNETS', txt, re.S)
    sbody = sn.group(1) if sn else ""
    # split into per-net entries
    lanes = {'VDD': set(), 'VSS': set()}
    # each special net starts with "- NAME" ; capture NAME + body until the ';'
    for nm_m in re.finditer(r'-\s+(VDD|VSS)\b(.*?);', sbody, re.S):
        net = nm_m.group(1); body = nm_m.group(2)
        # routing points: "NEW M7 <w> ( x y ) ( x2 y2 )" or "( x y ) ( x2 * )"
        # A vertical M7 stripe: same x for both endpoints, different y.
        # Track current layer as we scan tokens.
        for seg in re.finditer(r'\bM7\s+(\d+)\b(.*?)(?=\bNEW\b|\bM\d+\s+\d+|$)', body, re.S):
            w = u(int(seg.group(1)))
            pts = re.findall(r'\(\s*(-?\d+|\*)\s+(-?\d+|\*)\s*\)', seg.group(2))
            # convert, resolving '*' (means same as previous coord)
            coords = []
            px = py = None
            for xs, ys in pts:
                x = px if xs == '*' else int(xs)
                y = py if ys == '*' else int(ys)
                coords.append((x, y)); px, py = x, y
            for i in range(len(coords)-1):
                (x1, y1), (x2, y2) = coords[i], coords[i+1]
                if x1 == x2 and y1 != y2:   # vertical stripe centerline at x1
                    # lane llx = centerline - w/2  (stripe area was [x, .., x+5])
                    lanes[net].add(round(u(x1) - w/2.0, 3))

    print("=== M7 PG LANE EVIDENCE (DEF SPECIALNETS) ===")
    exp = []
    for c in range(6):
        cx = COLS[c]
        for k in range(7):
            exp.append(('VDD', round(cx+51+50*k, 3), c, k))
            exp.append(('VSS', round(cx+60+50*k, 3), c, k))
    lanes_ok = True
    missing = []
    for net, lx, c, k in exp:
        hit = any(abs(lx - g) <= 0.6 for g in lanes[net])  # lane llx within 0.6um
        if not hit:
            lanes_ok = False; missing.append((net, lx, c, k))
    print(f"expected lanes: {len(exp)} (VDD {len([e for e in exp if e[0]=='VDD'])}, "
          f"VSS {len([e for e in exp if e[0]=='VSS'])})")
    print(f"found M7 vertical lane llx's: VDD {len(lanes['VDD'])}, VSS {len(lanes['VSS'])}")
    if missing:
        print(f"MISSING {len(missing)} lanes:")
        for net, lx, c, k in missing[:40]:
            print(f"   {net} x={lx} (col{c} k{k})")
    print(f"ALL_LANES_PRESENT = {lanes_ok}\n")
    print(f"OVERALL_EVIDENCE_PASS = {tiles_ok and lanes_ok}")
    sys.exit(0 if (tiles_ok and lanes_ok) else 1)

if __name__ == '__main__':
    main()
