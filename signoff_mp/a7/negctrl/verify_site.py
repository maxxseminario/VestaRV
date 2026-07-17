import struct as st
fn="a7/negctrl/chip_top_clean_a7.gds"
data=open(fn,'rb').read()
# units
def real8(b):
    s=-1.0 if b[0]&0x80 else 1.0; e=(b[0]&0x7f)-64; m=0
    for by in b[1:8]: m=(m<<8)|by
    return s*m/(1<<56)*(16.0**e)
i=0;N=len(data);dbpum=None;top=None
# find UNITS
while i<N:
    ln,rt=st.unpack('>HH',data[i:i+4])
    if ln<4:break
    if rt==0x0305:
        dbpum=1e-6/real8(data[i+4+8:i+4+16]);
    i+=ln
print("db/um=",dbpum)
LAY,DT=31,0
# window: x[190,215]um y[1252,1260]um
xw=(190*dbpum,215*dbpum); yw=(1252*dbpum,1260*dbpum)
i=0;cur=None;hits=[]
while i<N:
    ln,rt=st.unpack('>HH',data[i:i+4])
    if ln<4:break
    if rt==0x0606: cur=data[i+4:i+ln].rstrip(b'\x00').decode('latin1')
    elif rt==0x0800:  # BOUNDARY
        lay=dt=None;pts=None;j=i+ln
        while j<N:
            l2,r2=st.unpack('>HH',data[j:j+4]);b2=data[j+4:j+l2]
            if r2==0x0D02:lay=st.unpack('>h',b2)[0]
            elif r2==0x0E02:dt=st.unpack('>h',b2)[0]
            elif r2==0x1003:
                n=len(b2)//8;v=st.unpack('>%di'%(n*2),b2);pts=list(zip(v[0::2],v[1::2]))
            elif r2==0x1100:j+=l2;break
            j+=l2
        if lay==LAY and dt==DT and pts and cur=='chip_top':
            xs=[p[0] for p in pts];ys=[p[1] for p in pts]
            if min(xs)<xw[1] and max(xs)>xw[0] and min(ys)<yw[1] and max(ys)>yw[0]:
                hits.append((min(xs)/dbpum,min(ys)/dbpum,max(xs)/dbpum,max(ys)/dbpum))
        i+=ln;continue
    i+=ln
print("top-level M1 (31/0) rects in window x[190,215] y[1252,1260]um:",len(hits))
for h in sorted(set(round(h[1],2) for h in hits)):
    print("  yband centered near",h)
for r in hits[:12]:
    print("   rect x[%.2f,%.2f] y[%.3f,%.3f]"%r)
