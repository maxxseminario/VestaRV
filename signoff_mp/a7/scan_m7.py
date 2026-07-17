import struct as st
fn="a7/negctrl/chip_top_clean.gds"
data=open(fn,'rb').read()
LAY,DT=37,0   # M7 drawing
x0,y0,x1,y1=75,795,100,815
i=0;N=len(data)
rects=[]
while i<N:
    rl,rt,df=st.unpack('>HBB',data[i:i+4])
    if rl==0:break
    if rt==0x08:  # BOUNDARY
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
            bx0,bx1,by0,by1=min(xs),max(xs),min(ys),max(ys)
            if bx0<x1 and bx1>x0 and by0<y1 and by1>y0:
                rects.append((round(bx0,3),round(by0,3),round(bx1,3),round(by1,3)))
        i+=rl;continue
    i+=rl
rects=sorted(set(rects))
print("M7(37:0) rects overlapping x[%d,%d]y[%d,%d]: %d"%(x0,x1,y0,y1,len(rects)))
for r in rects[:30]:
    print("  x[%.3f,%.3f] y[%.3f,%.3f] w=%.2f"%(r[0],r[2],r[1],r[3],r[2]-r[0]))
