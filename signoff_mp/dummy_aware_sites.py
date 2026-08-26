#!/usr/bin/env python3
"""PG4: dummy-M2-aware direction chooser for the MCU min-area patch pass.

The analog macros' GDS masters carry dummy-M2 fill (GDS 32:1) that the
Innovus DB cannot see; DM2.S.2 demands real-M2 >= 0.3 um from it, so a
min-area extension picked blind can land inside the keepout (trial #3:
37 DM2.S.2 from ~30 of the 97 analog-band sites). This reads the merged
GDS's 32:1 shapes (flattened through SREF/AREF with orientation), replays
the patch tcl's extension geometry for each site/direction, and emits
minarea_sites2.txt with a 6th field: plus | minus | either | none.
It also reports dummy clearance for the hardcoded onesie rects.

Usage: dummy_aware_sites.py <gds> <sites_in> <sites_out> [topstruct]
  topstruct defaults to "MCU" (the assembly top). For flat chips pass the
  chip's own struct name (e.g. MCU_castalia) — C6 finding 2026-07-29: the
  hardcoded "MCU" flattened NOTHING on the flat wound-quad chip and the tool
  silently blessed all 179 sites (the G1 wrong-GDS class, new form). The
  script now FATALs if the GDS contains 32:1 shapes but the flatten from
  topstruct reaches none of them.
"""
import struct, sys, math

def parse_gds(path):
    data = open(path, "rb").read()
    structs = {}   # name -> {"shapes":[bbox...], "refs":[(ref,x,y,strans,angle,cols,rows,dx,dy)]}
    cur = None; layer = None; dt = None; pend = None
    i = 0
    while i < len(data):
        ln, rt = struct.unpack(">HH", data[i:i+4])
        if ln == 0: break
        body = data[i+4:i+ln]
        if rt == 0x0606:
            cur = body.rstrip(b"\x00").decode(); structs[cur] = {"shapes": [], "refs": []}
        elif rt == 0x0800 or rt == 0x0A00 or rt == 0x0B00:  # BOUNDARY/SREF/AREF
            pend = {"t": rt}
        elif rt == 0x1206 and pend: pend["ref"] = body.rstrip(b"\x00").decode()
        elif rt == 0x0D02: layer = struct.unpack(">h", body[:2])[0]
        elif rt == 0x0E02: dt = struct.unpack(">h", body[:2])[0]
        elif rt == 0x1A01 and pend: pend["strans"] = struct.unpack(">H", body[:2])[0]
        elif rt == 0x1B05 and pend: pass  # MAG
        elif rt == 0x1C05 and pend:
            # GDS real8 angle
            b = body[:8]
            sign = -1 if b[0] & 0x80 else 1
            exp = (b[0] & 0x7F) - 64
            mant = 0
            for k in range(1, 8): mant = (mant << 8) | b[k]
            pend["angle"] = sign * mant * (16.0 ** exp) / (2 ** 56) if mant else 0.0
        elif rt == 0x1302 and pend:  # COLROW
            pend["cols"], pend["rows"] = struct.unpack(">hh", body[:4])
        elif rt == 0x1003:
            n = (ln - 4) // 8
            pts = struct.unpack(f">{2*n}i", body)
            if pend and pend["t"] in (0x0A00, 0x0B00):
                x, y = pts[0]/1000.0, pts[1]/1000.0
                cols = pend.get("cols", 1); rows = pend.get("rows", 1)
                dx = dy = 0.0
                if pend["t"] == 0x0B00 and n >= 3:
                    dx = (pts[2]/1000.0 - x) / max(cols, 1)
                    dy = (pts[5]/1000.0 - y) / max(rows, 1)
                structs[cur]["refs"].append((pend["ref"], x, y,
                    pend.get("strans", 0), pend.get("angle", 0.0), cols, rows, dx, dy))
                pend = None
            elif pend and pend["t"] == 0x0800:
                if layer == 32 and dt == 1:
                    xs = [pts[k]/1000.0 for k in range(0, 2*n, 2)]
                    ys = [pts[k]/1000.0 for k in range(1, 2*n, 2)]
                    structs[cur]["shapes"].append((min(xs), min(ys), max(xs), max(ys)))
                pend = None
        elif rt == 0x1100:
            pend = None
        i += ln
    return structs

def xform(b, x, y, strans, angle):
    x0, y0, x1, y1 = b
    if strans & 0x8000:  # mirror about x-axis before rotation
        y0, y1 = -y1, -y0
    a = int(round(angle)) % 360
    if a == 90:   x0, y0, x1, y1 = -y1, x0, -y0, x1
    elif a == 180: x0, y0, x1, y1 = -x1, -y1, -x0, -y0
    elif a == 270: x0, y0, x1, y1 = y0, -x1, y1, -x0
    return (x0 + x, y0 + y, x1 + x, y1 + y)

def flatten(structs, top):
    out = []
    def rec(name, fx):
        st = structs.get(name)
        if not st: return
        for b in st["shapes"]:
            bb = b
            for (x, y, s, a) in reversed(fx): bb = xform(bb, x, y, s, a)
            out.append(bb)
        for (ref, x, y, s, a, cols, rows, dx, dy) in st["refs"]:
            for c in range(cols):
                for r in range(rows):
                    rec(ref, fx + [(x + c*dx, y + r*dy, s, a)])
    rec(top, [])
    return out

def gridup(v):
    g = v * 200.0
    if abs(g - round(g)) < 1e-6: return round(g) / 200.0
    return math.ceil(g) / 200.0

def clear_of_dummy(rect, dums, margin=0.3):
    x0, y0, x1, y1 = rect
    for dx0, dy0, dx1, dy1 in dums:
        if dx0 - margin < x1 and dx1 + margin > x0 and dy0 - margin < y1 and dy1 + margin > y0:
            return False
    return True

def main():
    gds, sin, sout = sys.argv[1], sys.argv[2], sys.argv[3]
    top = sys.argv[4] if len(sys.argv) > 4 else "MCU"
    structs = parse_gds(gds)
    if top not in structs:
        print(f"FATAL: top struct '{top}' not in GDS (structs incl.: "
              f"{sorted(structs)[:5]}...)"); sys.exit(1)
    dums = flatten(structs, top)
    raw_dummy = sum(len(s["shapes"]) for s in structs.values())
    print(f"dummy-M2 shapes: raw-in-GDS={raw_dummy} flattened-from-{top}={len(dums)}")
    if raw_dummy > 0 and not dums:
        print("FATAL: GDS contains 32:1 dummy shapes but NONE are reachable from "
              f"the top struct '{top}' — wrong topstruct (or wrong GDS). Refusing "
              "to bless sites blind (C6 2026-07-29 guard).")
        sys.exit(1)
    need = 0.052 + 0.006
    nplus = nminus = neither = nnone = 0
    with open(sout, "w") as f:
        for ln in open(sin):
            p = ln.split()
            if len(p) != 5: continue
            lay, x0, y0, x1, y1 = p[0], float(p[1]), float(p[2]), float(p[3]), float(p[4])
            if lay != "M2":
                f.write(f"{lay} {x0:.3f} {y0:.3f} {x1:.3f} {y1:.3f} either\n"); neither += 1; continue
            w = x1 - x0; h = y1 - y0
            if w >= h:
                ext = gridup(need / h - w); ext = ext if ext > 0 else 0.06
                rp = (x1, y0, x1 + ext, y1); rm = (x0 - ext, y0, x0, y1)
            else:
                ext = gridup(need / w - h); ext = ext if ext > 0 else 0.06
                rp = (x0, y1, x1, y1 + ext); rm = (x0, y0 - ext, x1, y0)
            okp = clear_of_dummy(rp, dums); okm = clear_of_dummy(rm, dums)
            if okp and okm: d = "either"; neither += 1
            elif okp: d = "plus"; nplus += 1
            elif okm: d = "minus"; nminus += 1
            else: d = "none"; nnone += 1
            f.write(f"{lay} {x0:.3f} {y0:.3f} {x1:.3f} {y1:.3f} {d}\n")
    print(f"either={neither} plus-only={nplus} minus-only={nminus} NONE={nnone}")

    # onesie rects (patch tcl hardcodes) — report clearance
    onesies = [
        ("G.4a", (999.45, 484.5, 999.635, 484.79)),
        ("G.4b", (1006.65, 484.4, 1006.79, 484.6)),
        ("M2.S.2-tab1", (1208.1, 545.47, 1208.2, 545.59)),
        ("M2.S.2-tab2", (1208.1, 545.97, 1208.2, 546.09)),
        ("M2.S.2.1", (1319.76, 553.9, 1319.9, 554.3)),
        ("VIA1fix-M2", (1292.4, 39.2, 1292.8, 39.4)),
        ("VIA2fix-M2", (1100.45, 39.43, 1101.0, 39.57)),
    ]
    for tag, r in onesies:
        print(f"onesie {tag}: dummy-clear={clear_of_dummy(r, dums)}")

if __name__ == "__main__":
    main()
