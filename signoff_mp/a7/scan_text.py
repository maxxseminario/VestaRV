import struct as st, sys
fn="a7/negctrl/chip_top_clean.gds"
data=open(fn,'rb').read()
x0,y0,x1,y1=70,560,100,1260
i=0;N=len(data);cur=None
# single pass; TEXT element: 0x0C00 TEXT, 0x0D LAYER,0x16 TEXTTYPE?,0x10 XY,0x19 STRING(0x1906)
# actually STRING rt=0x19 df=06 -> 0x1906
hits=[]
# track element: when see TEXT (0x0C), collect until ENDEL
k=0
while i<N:
    rl,rt,df=st.unpack('>HBB',data[i:i+4]); 
    if rl==0: break
    body=data[i+4:i+rl]
    if rt==0x0C:  # TEXT
        lay=None;xy=None;txt=None
        j=i+rl
        while j<N:
            rl2,rt2,df2=st.unpack('>HBB',data[j:j+4]);b2=data[j+4:j+rl2]
            if rt2==0x0D: lay=st.unpack('>h',b2)[0]
            elif rt2==0x10:
                v=st.unpack('>ii',b2[:8]); xy=(v[0]/1000.0,v[1]/1000.0)
            elif rt2==0x19: txt=b2.rstrip(b'\x00').decode(errors='replace')
            elif rt2==0x11: j+=rl2; break
            j+=rl2
        if xy and txt and x0<=xy[0]<=x1 and y0<=xy[1]<=y1 and ('VDD' in txt or 'VSS' in txt):
            hits.append((round(xy[0],3),round(xy[1],3),lay,txt))
        i+=rl; continue
    i+=rl
hits.sort()
print("VDD/VSS texts in x[%d,%d]y[%d,%d]: %d"%(x0,x1,y0,y1,len(hits)))
from collections import Counter
byname=Counter(h[3] for h in hits)
print("by net:",dict(byname))
# show x-distribution per net
for net in ('VDD','VSS','VDD_SW'):
    xs=sorted(set(h[0] for h in hits if h[3]==net))
    print("%s x-centroids(first20): %s"%(net,xs[:20]))
