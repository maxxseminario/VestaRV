#!/usr/bin/env python3
"""SREF/AREF-aware GDS window scan: dump shapes on a layer:datatype inside a
window of the top struct (flattening references). PG4-toolkit style.
Usage: gds_via_window.py file.gds TOP layer datatype x0 y0 x1 y1
Coords in um (assumes 1000 dbu/um)."""
import sys, struct as st

fn, top, lay, dt = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
x0, y0, x1, y1 = (float(v)*1000 for v in sys.argv[5:9])

data = open(fn, 'rb').read()
# parse records
structs = {}   # name -> list of (kind, payload)
cur = None; curname = None
i = 0; N = len(data)
elems = None
while i < N:
    rl, rt, df = st.unpack('>HBB', data[i:i+4])
    if rl == 0: break
    body = data[i+4:i+rl]
    i += rl
    if rt == 0x05:  # BGNSTR
        elems = []
    elif rt == 0x06 and elems is not None:  # STRNAME
        curname = body.rstrip(b'\x00').decode()
    elif rt == 0x07:  # ENDSTR
        structs[curname] = elems; elems = None
    elif elems is not None:
        elems.append((rt, body))

def xy(body):
    n = len(body)//8
    v = st.unpack('>%di' % (n*2), body)
    return list(zip(v[0::2], v[1::2]))

def transform(pts, ox, oy, strans, mag, angle):
    out = []
    import math
    c = math.cos(math.radians(angle)); s = math.sin(math.radians(angle))
    for (x, y) in pts:
        if strans & 0x8000: y = -y          # mirror about x BEFORE rotation
        x2 = x*c - y*s; y2 = x*s + y*c
        out.append((x2*mag + ox, y2*mag + oy))
    return out

hits = []
def walk(name, ox, oy, strans, mag, angle, depth):
    if depth > 8 or name not in structs: return
    j = 0; el = structs[name]
    k = 0
    while k < len(el):
        rt, body = el[k]
        if rt == 0x08:  # BOUNDARY
            L = D = None; pts = None
            k += 1
            while k < len(el) and el[k][0] != 0x11:
                r2, b2 = el[k]
                if r2 == 0x0D: L = st.unpack('>h', b2)[0]
                elif r2 == 0x0E: D = st.unpack('>h', b2)[0]
                elif r2 == 0x10: pts = xy(b2)
                k += 1
            if L == lay and D == dt and pts:
                tp = transform(pts, ox, oy, strans, mag, angle)
                xs = [p[0] for p in tp]; ys = [p[1] for p in tp]
                if max(xs) >= x0 and min(xs) <= x1 and max(ys) >= y0 and min(ys) <= y1:
                    hits.append((min(xs), min(ys), max(xs), max(ys), name))
        elif rt in (0x0A, 0x0B):  # SREF / AREF
            sname = None; sst = 0; smag = 1.0; sang = 0.0; spts = None
            cols = rows = 1
            k += 1
            while k < len(el) and el[k][0] != 0x11:
                r2, b2 = el[k]
                if r2 == 0x12: sname = b2.rstrip(b'\x00').decode()
                elif r2 == 0x1A: sst = st.unpack('>H', b2)[0]
                elif r2 == 0x1B: smag = st.unpack('>d', b2)[0] if len(b2)==8 else 1.0
                elif r2 == 0x1C:
                    # 8-byte GDS real
                    b = b2
                    sgn = -1 if b[0] & 0x80 else 1
                    ex = (b[0] & 0x7f) - 64
                    mant = int.from_bytes(b[1:8], 'big') / float(1 << 56)
                    sang = sgn * mant * (16.0 ** ex)
                elif r2 == 0x13: cols, rows = st.unpack('>hh', b2)
                elif r2 == 0x10: spts = xy(b2)
                k += 1
            if sname and spts:
                if rt == 0x0A:
                    px, py = transform(spts, ox, oy, strans, mag, angle)[0]
                    a2 = sang + (angle if not (strans & 0x8000) else -angle)
                    st2 = sst ^ (strans & 0x8000)
                    walk(sname, px, py, st2, smag*mag, a2, depth+1)
                else:
                    p = transform(spts, ox, oy, strans, mag, angle)
                    o = p[0]
                    dc = ((p[1][0]-o[0])/cols, (p[1][1]-o[1])/cols)
                    dr = ((p[2][0]-o[0])/rows, (p[2][1]-o[1])/rows)
                    for r in range(rows):
                        for c in range(cols):
                            px = o[0] + c*dc[0] + r*dr[0]
                            py = o[1] + c*dc[1] + r*dr[1]
                            a2 = sang + (angle if not (strans & 0x8000) else -angle)
                            st2 = sst ^ (strans & 0x8000)
                            walk(sname, px, py, st2, smag*mag, a2, depth+1)
        else:
            k += 1
    return

walk(top, 0.0, 0.0, 0, 1.0, 0.0, 0)
print(f"{len(hits)} shapes on {lay}:{dt} in window")
for h in sorted(hits)[:40]:
    print(f"  ({h[0]/1000:.3f},{h[1]/1000:.3f})-({h[2]/1000:.3f},{h[3]/1000:.3f})  [{h[4]}]")
