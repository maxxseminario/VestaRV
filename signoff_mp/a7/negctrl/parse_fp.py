import re
lines=open('a7/negctrl/specialnets.txt').read().splitlines()
net=None
# collect M1 followpins: (net,y,x1,x2)
fps=[]
for ln in lines:
    s=ln.strip()
    m=re.match(r'- (VDD|VSS)\b',s)
    if m: net=m.group(1); continue
    # NEW M1 600 + SHAPE FOLLOWPIN ( x1 y1 ) ( x2 * )
    fm=re.search(r'NEW M1 \d+ \+ SHAPE FOLLOWPIN \( (\d+) (\d+) \) \( (\d+|\*) (\d+|\*) \)',s)
    if fm and net:
        x1=int(fm.group(1)); y1=int(fm.group(2)); x2=fm.group(3)
        x2=int(x2) if x2!='*' else x1
        fps.append((net,y1,x1,x2))
print("total M1 followpins:",len(fps))
# Band B1: y between 2500170 and 2536170
def band(name,ylo,yhi):
    sel=[f for f in fps if ylo<=f[1]<=yhi]
    print(f"\n=== {name} y[{ylo},{yhi}] ({(yhi-ylo)/2000:.0f}um): {len(sel)} M1 fps ===")
    # group by y
    ys=sorted(set(f[1] for f in sel))
    for y in ys:
        row=[f for f in sel if f[1]==y]
        nets=set(f[0] for f in row)
        # longest segment
        seg=max(row,key=lambda f:f[3]-f[2])
        print(f"  y={y}({y/2000:.3f}um) net={','.join(nets)} nseg={len(row)} longest x[{seg[2]},{seg[3]}]({seg[2]/2000:.1f}-{seg[3]/2000:.1f}um len {(seg[3]-seg[2])/2000:.1f}um)")
band("B1band",2500170,2536170)
band("B2band",3906170,3942170)
