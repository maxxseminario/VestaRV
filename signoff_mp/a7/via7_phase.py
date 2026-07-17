#!/usr/bin/env python3
"""A7 via-phase verdict: SREF/AREF-aware, PRUNED to structs that (transitively)
carry VIA7 (layer 57 dt 40). For each requested window it lists each VIA7 cut's
bbox tagged with the IMMEDIATE containing struct (chip_top_VIA* = chip/assembly
array; hart_tile_VIA* = tile-internal array) so coincidence vs 0.5um interleave
is read directly. Coords um (1000 dbu/um)."""
import sys, struct as st, math
from collections import defaultdict

fn = "/home/mseminario2/vestarv/innovus/common/out/chip_top_argus.gds2"
LAY, DT = 57, 40
data = open(fn, 'rb').read()
structs = {}; cur = None; el = None; i = 0; N = len(data)
refs = {}
while i < N:
    rl, rt, df = st.unpack('>HBB', data[i:i+4])
    if rl == 0:
        break
    body = data[i+4:i+rl]; i += rl
    if rt == 0x05:
        el = []
    elif rt == 0x06:
        cur = body.rstrip(b'\x00').decode()
    elif rt == 0x07:
        structs[cur] = el; el = None
    elif el is not None:
        el.append((rt, body))

direct = set()
for name, elems in structs.items():
    kids = set(); k = 0
    while k < len(elems):
        rt, body = elems[k]
        if rt in (0x0A, 0x0B):
            k += 1
            while k < len(elems) and elems[k][0] != 0x11:
                if elems[k][0] == 0x12:
                    kids.add(elems[k][1].rstrip(b'\x00').decode())
                k += 1
        elif rt == 0x08:
            L = D = None; k += 1
            while k < len(elems) and elems[k][0] != 0x11:
                r2, b2 = elems[k]
                if r2 == 0x0D:
                    L = st.unpack('>h', b2)[0]
                elif r2 == 0x0E:
                    D = st.unpack('>h', b2)[0]
                k += 1
            if L == LAY and D == DT:
                direct.add(name)
        else:
            k += 1
    refs[name] = kids

carry = set(direct); changed = True
while changed:
    changed = False
    for name, kids in refs.items():
        if name not in carry and (kids & carry):
            carry.add(name); changed = True

def xy(b):
    n = len(b)//8; v = st.unpack('>%di' % (n*2), b); return list(zip(v[0::2], v[1::2]))

def gds_real(b):
    sgn = -1 if b[0] & 0x80 else 1; ex = (b[0] & 0x7f) - 64
    return sgn*(int.from_bytes(b[1:8], 'big')/float(1 << 56))*(16.0**ex)

def transform(pts, ox, oy, strans, mag, angle):
    c = math.cos(math.radians(angle)); s = math.sin(math.radians(angle)); out = []
    for (x, y) in pts:
        if strans & 0x8000:
            y = -y
        out.append(((x*c - y*s)*mag + ox, (x*s + y*c)*mag + oy))
    return out

hits = []
def walk(name, ox, oy, strans, mag, angle, depth):
    if depth > 10 or name not in structs or name not in carry:
        return
    el = structs[name]; k = 0
    while k < len(el):
        rt, body = el[k]
        if rt == 0x08:
            L = D = None; pts = None; k += 1
            while k < len(el) and el[k][0] != 0x11:
                r2, b2 = el[k]
                if r2 == 0x0D:
                    L = st.unpack('>h', b2)[0]
                elif r2 == 0x0E:
                    D = st.unpack('>h', b2)[0]
                elif r2 == 0x10:
                    pts = xy(b2)
                k += 1
            if L == LAY and D == DT and pts:
                tp = transform(pts, ox, oy, strans, mag, angle)
                xs = [p[0] for p in tp]; ys = [p[1] for p in tp]
                hits.append((min(xs), min(ys), max(xs), max(ys), name))
        elif rt in (0x0A, 0x0B):
            sname = None; sst = 0; smag = 1.0; sang = 0.0; spts = None; cols = rows = 1; k += 1
            while k < len(el) and el[k][0] != 0x11:
                r2, b2 = el[k]
                if r2 == 0x12:
                    sname = b2.rstrip(b'\x00').decode()
                elif r2 == 0x1A:
                    sst = st.unpack('>H', b2)[0]
                elif r2 == 0x1B:
                    smag = st.unpack('>d', b2)[0] if len(b2) == 8 else 1.0
                elif r2 == 0x1C:
                    sang = gds_real(b2)
                elif r2 == 0x13:
                    cols, rows = st.unpack('>hh', b2)
                elif r2 == 0x10:
                    spts = xy(b2)
                k += 1
            if sname and spts and sname in carry:
                base = transform(spts, ox, oy, strans, mag, angle)
                a2 = sang + (angle if not (strans & 0x8000) else -angle)
                st2 = sst ^ (strans & 0x8000)
                if rt == 0x0A:
                    walk(sname, base[0][0], base[0][1], st2, smag*mag, a2, depth+1)
                else:
                    o = base[0]
                    dc = ((base[1][0]-o[0])/cols, (base[1][1]-o[1])/cols)
                    dr = ((base[2][0]-o[0])/rows, (base[2][1]-o[1])/rows)
                    for r in range(rows):
                        for c in range(cols):
                            walk(sname, o[0]+c*dc[0]+r*dr[0], o[1]+c*dc[1]+r*dr[1], st2, smag*mag, a2, depth+1)
        else:
            k += 1

walk('chip_top', 0, 0, 0, 1.0, 0.0, 0)
hits = [(a/1000.0, b/1000.0, c/1000.0, d/1000.0, e) for (a, b, c, d, e) in hits]  # DBU -> um
print("# structs carrying VIA7: %d (direct %d); total VIA7 cuts flattened: %d" % (len(carry), len(direct), len(hits)))
if hits:
    allx = [(h[0]+h[2])/2 for h in hits]; ally = [(h[1]+h[3])/2 for h in hits]
    print("# GLOBAL cut-centroid extent: x[%.1f,%.1f] y[%.1f,%.1f]" % (min(allx), max(allx), min(ally), max(ally)))
    fh = defaultdict(int)
    for h in hits:
        fh[(int((h[0]+h[2])/2//250)*250, int((h[1]+h[3])/2//250)*250)] += 1
    print("# top 250um bins by cut count:")
    for (bx, by), c in sorted(fh.items(), key=lambda kv: -kv[1])[:12]:
        print("#   bin x=%d y=%d : %d" % (bx, by, c))
    # per-struct-family cut counts + x-extent
    ff = defaultdict(list)
    for h in hits:
        ff[fam(h[4]) if 'fam' in dir() else (h[4][:9])].append(h)

def fam(name):
    if name.startswith('chip_top'):
        return 'CHIP'
    if name.startswith('hart_tile'):
        return 'TILE'
    return name

# rows to analyse: (label, ylo, yhi) and a col x-window to keep it small
rows = eval(sys.argv[1])  # [(label, ylo, yhi, xlo, xhi), ...]
for lab, ylo, yhi, xlo, xhi in rows:
    band = [h for h in hits if h[1] >= ylo and h[3] <= yhi and (h[0]+h[2])/2 >= xlo and (h[0]+h[2])/2 <= xhi]
    # per-family lane x-centroids (rounded 0.05um)
    byfam = defaultdict(lambda: defaultdict(int))
    for h in band:
        cx = round((h[0]+h[2])/2, 2)
        byfam[fam(h[4])][cx] += 1
    print("\n=== %s  y[%s,%s] x[%s,%s]  %d cuts ===" % (lab, ylo, yhi, xlo, xhi, len(band)))
    chip_x = sorted(byfam.get('CHIP', {}))
    tile_x = sorted(byfam.get('TILE', {}))
    print("  CHIP lanes x: %s" % ([("%.2f" % x) for x in chip_x]))
    print("  TILE lanes x: %s" % ([("%.2f" % x) for x in tile_x]))
    # coincidence / interleave test: for each chip lane, nearest tile lane gap
    flags = []
    for cx in chip_x:
        if tile_x:
            g = min(abs(cx - tx) for tx in tile_x)
            near = min(tile_x, key=lambda tx: abs(cx - tx))
            if g < 0.05:
                tag = "COINCIDENT"
            elif 0.4 < g < 0.6:
                tag = "!!INTERLEAVE-0.5!!"
            else:
                tag = "gap=%.2f" % g
            flags.append("chip %.2f<->tile %.2f: %s" % (cx, near, tag))
    for f in flags:
        print("    " + f)
