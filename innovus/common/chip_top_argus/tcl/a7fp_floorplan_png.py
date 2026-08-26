#!/usr/bin/env python3
# A7-1 floorplan snapshots from the saved DEF (headless; PIL, no matplotlib).
# Draws tiles, RAM banks, analog macros, the two escape bands, B1, x=1345 axis,
# and the M7 PG lanes. Emits full-die + bandA + bandB + B1-closeup PNGs.
import sys, gzip, re
from PIL import Image, ImageDraw, ImageFont

def openf(p): return gzip.open(p, 'rt') if p.endswith('.gz') else open(p, 'r')

def parse(defp):
    txt = openf(defp).read()
    m = re.search(r'UNITS\s+DISTANCE\s+MICRONS\s+(\d+)', txt); units = int(m.group(1)) if m else 2000
    U = lambda v: float(v)/units
    sizes = {'hart_tile': (405.0, 685.0), 'sram1p16k_hvt_pg': (319.65, 383.085),
             'rom_hvt_pg': (156.525, 325.055), 'GlitchFilter': (31.195, 18.87),
             'PowerOnResetCheng': (26.41, 11.55), 'OscillatorCurrentStarved': (58.17, 37.145)}
    tiles, banks, macros = [], [], []
    comp = re.search(r'COMPONENTS\s+\d+\s*;(.*?)END COMPONENTS', txt, re.S).group(1)
    # anchor on the known macro cell names (~90 placed objs) so we never let a
    # non-greedy span cross the 31k unplaced std cells (catastrophic backtrack).
    cellalt = r'(hart_tile|sram1p16k_hvt_pg|rom_hvt_pg|GlitchFilter|PowerOnResetCheng|OscillatorCurrentStarved)'
    for mm in re.finditer(r'-\s+(\S+)\s+'+cellalt+r'\b[^;]*?\+\s+(?:PLACED|FIXED)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)', comp):
        inst, cell, x, y, o = mm.group(1), mm.group(2), U(mm.group(3)), U(mm.group(4)), mm.group(5)
        if cell not in sizes: continue
        w, h = sizes[cell]
        if o in ('E','W','FE','FW','R90','R270'): w, h = h, w
        rec = (inst.split('/')[-1], x, y, w, h)
        (tiles if cell=='hart_tile' else banks if cell=='sram1p16k_hvt_pg' else macros).append(rec)
    # PG lanes: drawn from the known lane grid (cx+51+50k VDD, cx+60+50k VSS,
    # cx=30+445c) -- these exact lanes were independently PROVEN present in this
    # DEF's SPECIALNETS by a7fp_def_evidence.py (ALL_LANES_PRESENT=True). Drawing
    # the 2.3MB special-net path stream directly is too slow for a snapshot.
    TILE_W=405.0; GAP=(2690.0-2*30.0-6*405.0)/5.0
    GRID_TOP=2656.085
    lanes = {'VDD': [], 'VSS': []}
    for c in range(6):
        cx = 30.0 + c*(TILE_W+GAP)
        for k in range(7):
            lanes['VDD'].append((cx+51+50*k, 0.0, 5.0, GRID_TOP))
            lanes['VSS'].append((cx+60+50*k, 0.0, 5.0, GRID_TOP))
    return tiles, banks, macros, lanes

def render(tiles, banks, macros, lanes, xlim, ylim, title, outf, px=1500):
    x0,x1 = xlim; y0,y1 = ylim
    sx = px/(x1-x0); sy = sx
    W = int((x1-x0)*sx); H = int((y1-y0)*sy) + 22
    img = Image.new('RGB', (W, H), '#ffffff'); d = ImageDraw.Draw(img)
    def TX(x): return int((x-x0)*sx)
    def TY(y): return int(H - 22 - (y-y0)*sy)   # flip y (DEF y up)
    def box(x,y,w,h,fill=None,outline=None,wd=1):
        d.rectangle([TX(x),TY(y+h),TX(x+w),TY(y)], fill=fill, outline=outline, width=wd)
    # bands + B1 (full width shading)
    box(0,395.085,2690,166,fill='#fff2cc')                 # B1
    box(0,1250.085,2690,18,fill='#d5e8d4')                 # bandA
    box(0,1953.085,2690,18,fill='#d5e8d4')                 # bandB
    d.rectangle([TX(0),TY(2690),TX(2690),TY(0)], outline='#999999', width=1)  # interior
    for lx,ly,lw,lh in lanes['VSS']: box(lx,ly,max(lw,1.0),lh, fill='#8fb3e0')
    for lx,ly,lw,lh in lanes['VDD']: box(lx,ly,max(lw,1.0),lh, fill='#e08f8f')
    for nm,x,y,w,h in tiles:  box(x,y,w,h, fill='#dae8fc', outline='#3b6ea5', wd=2)
    for nm,x,y,w,h in banks:  box(x,y,w,h, fill='#e1d5e7', outline='#7d5ba6', wd=1)
    for nm,x,y,w,h in macros:
        box(x,y,w,h, fill='#f8cecc', outline='#b85450', wd=2)
        d.text((TX(x+w/2)-14, TY(y+h/2)-4), nm, fill='#000000')
    # x=1345 symmetry axis
    d.line([TX(1345),TY(y1),TX(1345),TY(y0)], fill='#000000', width=1)
    d.text((6, H-18), title, fill='#000000')
    img.save(outf); print("wrote", outf, img.size)

def main():
    defp = sys.argv[1]; pre = sys.argv[2] if len(sys.argv)>2 else "out/chip_top_argus_a7fp"
    tiles,banks,macros,lanes = parse(defp)
    render(tiles,banks,macros,lanes,(-160,2850),(-160,2850),
           "chip_top_argus v5/A7 full die (x=1345 axis; VDD=red VSS=blue lanes)", f"{pre}.full.png", 1400)
    render(tiles,banks,macros,lanes,(-30,2720),(360,640),
           "B1 band -- analog macros balanced about x=1345", f"{pre}.B1.png", 1800)
    render(tiles,banks,macros,lanes,(-30,2720),(1200,1320),
           "bandA escape band (row0 top .. row1 bottom)", f"{pre}.bandA.png", 1800)
    render(tiles,banks,macros,lanes,(-30,2720),(1905,2025),
           "bandB escape band (row1 top .. row2 bottom)", f"{pre}.bandB.png", 1800)

if __name__ == '__main__':
    main()
