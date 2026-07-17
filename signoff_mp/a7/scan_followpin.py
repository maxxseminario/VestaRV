import struct as st
fn="a7/negctrl/chip_top_clean.gds"
data=open(fn,'rb').read()
LAY,DT=31,0   # M1 drawing
# scan several candidate top-level std-cell windows (below row0 / B1 band)
wins=[("B1band",500,520,400,470),("belowR0",500,520,60,140),("bandA",500,520,1252,1266)]
i=0;N=len(data);rects=[]
while i<N:
    rl,rt,df=st.unpack('>HBB',data[i:i+4])
    if rl==0:break
    if rt==0x08:
        lay=dt=None;pts=None;j=i+rl
        while j<N:
            rl2,rt2,df2=st.unpack('>HBB',data[j:j+4]);b2=data[j+4:j+rl2]
            if rt2==0x0D:lay=st.unpack('>h',b2)[0]
            elif rt2==0x0E:dt=st.unpack('>h',b2)[0]
            elif rt2==0x10:
                n=len(b2)//8;v=st.unpack('>%di'%(n*2),b2);pts=list(zip(v[0::2],v[1::2]))
            elif rt2==0x11:j+=rl2;break
            j+=rl2
        if lay==LAY and dt==DT and pts:
            xs=[p[0]/1000 for p in pts];ys=[p[1]/1000 for p in pts]
            rects.append((min(xs),min(ys),max(xs),max(ys)))
        i+=rl;continue
    i+=rl
for name,x0,x1,y0,y1 in wins:
    sel=[r for r in rects if r[0]<x1 and r[2]>x0 and r[1]<y1 and r[3]>y0]
    ys=sorted(set(round((r[1]+r[3])/2,3) for r in sel))
    print("%s x[%d,%d]y[%d,%d]: %d M1 rects; rail y-centroids(first14)=%s"%(name,x0,x1,y0,y1,len(sel),ys[:14]))
