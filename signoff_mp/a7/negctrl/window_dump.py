import struct as st,sys
fn=sys.argv[1]
X0,X1,Y0,Y1=float(sys.argv[2]),float(sys.argv[3]),float(sys.argv[4]),float(sys.argv[5])
data=open(fn,'rb').read()
def real8(b):
    s=-1.0 if b[0]&0x80 else 1.0;e=(b[0]&0x7f)-64;m=0
    for by in b[1:8]:m=(m<<8)|by
    return s*m/(1<<56)*(16.0**e)
i=0;N=len(data);dbpum=None
while i<N:
    ln,rt=st.unpack('>HH',data[i:i+4])
    if ln<4:break
    if rt==0x0305:dbpum=1e-6/real8(data[i+4+8:i+4+16]);break
    i+=ln
# find UNITS properly (scan)
i=0
while i<N:
    ln,rt=st.unpack('>HH',data[i:i+4])
    if ln<4:break
    if rt==0x0305:dbpum=1e-6/real8(data[i+4+8:i+4+16])
    i+=ln
u=dbpum
i=0;cur=None;out=[]
while i<N:
    ln,rt=st.unpack('>HH',data[i:i+4])
    if ln<4:break
    if rt==0x0606:cur=data[i+4:i+ln].rstrip(b'\x00').decode('latin1')
    elif rt==0x0800:
        lay=dt=None;pts=None;j=i+ln
        while j<N:
            l2,r2=st.unpack('>HH',data[j:j+4]);b2=data[j+4:j+l2]
            if r2==0x0D02:lay=st.unpack('>h',b2)[0]
            elif r2==0x0E02:dt=st.unpack('>h',b2)[0]
            elif r2==0x1003:
                n=len(b2)//8;v=st.unpack('>%di'%(n*2),b2);pts=list(zip(v[0::2],v[1::2]))
            elif r2==0x1100:j+=l2;break
            j+=l2
        if lay==31 and dt==0 and pts and cur=='chip_top':
            xs=[p[0]/u for p in pts];ys=[p[1]/u for p in pts]
            xmn,xmx,ymn,ymx=min(xs),max(xs),min(ys),max(ys)
            if xmn<X1 and xmx>X0 and ymn<Y1 and ymx>Y0:
                w=xmx-xmn;h=ymx-ymn
                kind="RAIL(horiz,long)" if (xmx-xmn)>50 else ("VBRIDGE/local" )
                out.append((ymn,ymx,xmn,xmx,w,h,kind))
        i+=ln;continue
    i+=ln
print(f"db/um={u:.0f}  M1(31/0) chip_top rects overlapping x[{X0},{X1}] y[{Y0},{Y1}]: {len(out)}")
for ymn,ymx,xmn,xmx,w,h,kind in sorted(out):
    print(f"  y[{ymn:.3f},{ymx:.3f}] x[{xmn:.2f},{xmx:.2f}] w={w:.2f} h={h:.3f}  {kind}")
