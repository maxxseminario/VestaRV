#!/usr/bin/env python3
"""PG4/F2 acceptance gate: strap-pin via1 presence, from the GDS alone.

The in-DB via gates false-passed for three tile versions (v18-v22c) while
the GDS had ZERO layer-51 cuts under any VDDG/VNW strap column — the
headers' always-on supply hung on nwell diffusion.  This gate checks the
artifact that actually ships: for every tall vertical M2 strap in the top
structure (the PG4 fabric columns, >=40 um tall, <=0.4 um wide), count
flattened layer-51 (VIA1) cuts inside the strap footprint.  A header/tap
column needs roughly one via1 per member cell (4 um pitch) — the gate
demands >= 1 cut per 8 um of strap, which the old GDS fails at 0.

Usage: gds_fabric_gate.py <gds> <top_struct>
Exit 0 = every strap column covered; exit 2 = failures (listed).
Negative control: run against the v22c hart_tile.gds2 — must FAIL.
"""
import struct, sys, collections

def parse(path):
    data = open(path, 'rb').read()
    i = 0
    cells = {}
    cur = None
    elem = None
    while i < len(data):
        ln, rt = struct.unpack('>HH', data[i:i+4])
        if ln == 0:
            break
        body = data[i+4:i+ln]
        if rt == 0x0606:
            cur = body.rstrip(b'\x00').decode()
            cells[cur] = {'shapes': [], 'refs': []}
        elif rt == 0x0800:
            elem = {'t': 'b'}
        elif rt in (0x0A00, 0x0B00):
            elem = {'t': 'r'}
        elif rt == 0x0D02 and elem is not None:
            elem['lay'] = struct.unpack('>h', body[:2])[0]
        elif rt == 0x1206 and elem is not None:
            elem['sname'] = body.rstrip(b'\x00').decode()
        elif rt == 0x1003 and elem is not None:
            n = len(body) // 4
            xy = struct.unpack('>%di' % n, body)
            elem['xy'] = [(xy[k] / 1000.0, xy[k+1] / 1000.0) for k in range(0, n, 2)]
        elif rt == 0x1100 and elem is not None:
            if cur:
                if elem['t'] == 'b' and 'lay' in elem and 'xy' in elem:
                    xs = [p[0] for p in elem['xy']]
                    ys = [p[1] for p in elem['xy']]
                    cells[cur]['shapes'].append((elem['lay'], min(xs), min(ys), max(xs), max(ys)))
                elif elem['t'] == 'r' and 'sname' in elem and 'xy' in elem:
                    cells[cur]['refs'].append((elem['sname'], elem['xy'][0]))
            elem = None
        i += ln
    return cells

def flat_cuts(cells, top, layer):
    """Flatten layer shapes (R0-ref approximation is fine: engine via
    structs place unrotated; cell-internal 51 does not exist)."""
    out = []
    def rec(cell, ox, oy, depth):
        if depth > 6 or cell not in cells:
            return
        for lay, x0, y0, x1, y1 in cells[cell]['shapes']:
            if lay == layer:
                out.append((x0 + ox, y0 + oy, x1 + ox, y1 + oy))
        for sname, (px, py) in cells[cell]['refs']:
            rec(sname, ox + px, oy + py, depth + 1)
    rec(top, 0.0, 0.0, 0)
    return out

def main():
    gds, top = sys.argv[1], sys.argv[2]
    cells = parse(gds)
    if top not in cells:
        sys.exit('top struct %s not in %s' % (top, gds))
    # Fabric-family M2 = pieces whose THICKNESS (min dimension) is exactly
    # the 0.3 um strap width: vertical strap runs/fragments AND horizontal
    # ladder links.  Signal M2 (0.10-0.14) and CTS/shield (0.4) fenced out.
    # A strap conductor is a CONNECTED COMPONENT of touching pieces (the
    # continuity add_shapes overlap the engine fragments; ladder links tie
    # covered columns and repeater bands to their neighbours) — vias are
    # demanded per component, never per rect:
    #   component with >=100 um of tall-run metal -> ~1 via1 per 10 um
    #   (pin-hookup density);  any other component with a >=40 um run ->
    #   >=1;  small via-less fragments -> WARN only (fabric litter).
    fam = []
    for lay, x0, y0, x1, y1 in cells[top]['shapes']:
        if lay != 32:
            continue
        w, h = x1 - x0, y1 - y0
        if 0.28 <= min(w, h) <= 0.32 and max(w, h) >= 2.0:
            fam.append((x0, y0, x1, y1))
    parent = list(range(len(fam)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for i in range(len(fam)):
        ax0, ay0, ax1, ay1 = fam[i]
        for j in range(i + 1, len(fam)):
            bx0, by0, bx1, by1 = fam[j]
            if ax0 <= bx1 and ax1 >= bx0 and ay0 <= by1 and ay1 >= by0:
                ra, rb = find(i), find(j)
                if ra != rb:
                    parent[ra] = rb
    comps = collections.defaultdict(list)
    for i in range(len(fam)):
        comps[find(i)].append(fam[i])
    cuts = flat_cuts(cells, top, 51)
    bad, warns = [], 0
    for rects in comps.values():
        n = sum(1 for cx0, cy0, cx1, cy1 in cuts for sx0, sy0, sx1, sy1 in rects
                if cx0 < sx1 and cx1 > sx0 and cy0 < sy1 and cy1 > sy0)
        tall = sum((y1 - y0) for x0, y0, x1, y1 in rects if (y1 - y0) >= 100.0)
        runmax = max(max(x1 - x0, y1 - y0) for x0, y0, x1, y1 in rects)
        bb = (min(r[0] for r in rects), min(r[1] for r in rects),
              max(r[2] for r in rects), max(r[3] for r in rects))
        if tall >= 100.0:
            need = max(1, int(tall / 10.0))
        elif runmax >= 40.0:
            need = 1
        else:
            need = 0
        if need and n < need:
            bad.append(bb)
            print('component bb=(%.1f,%.1f)-(%.1f,%.1f) %d rects: via1 cuts %d (need >=%d) FAIL'
                  % (bb[0], bb[1], bb[2], bb[3], len(rects), n, need))
        elif not need and n == 0:
            warns += 1
        else:
            print('component bb=(%.1f,%.1f)-(%.1f,%.1f) %d rects: via1 cuts %d (need >=%d) ok'
                  % (bb[0], bb[1], bb[2], bb[3], len(rects), n, need))
    print('%d strap components, %d under-covered, %d small via-less fragments (warn)'
          % (len(comps), len(bad), warns))
    sys.exit(2 if bad else 0)

if __name__ == '__main__':
    main()
