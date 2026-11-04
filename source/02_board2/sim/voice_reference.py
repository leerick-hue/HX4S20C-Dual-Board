"""Independent integer signal/DTW analysis for the labeled development cases.

Used to inspect behavior, not an oracle for recognition labels or a claim about
physical distance. The RTL replay independently requires the original labels.
"""
from pathlib import Path
from collections import deque
import json,math,hashlib
import numpy as np
R=Path(__file__).resolve().parents[1];D=R/'sim/voice_data'
meta=json.loads((D/'cases.json').read_text(encoding='utf-8'))
data=[int(x,16) for x in (D/'voice_raw.hex').read_text().split()]
data=[x-(1<<24) if x&(1<<23) else x for x in data]
coeff=np.array([round(2*math.cos(2*math.pi*k/256)*16384) for k in (2,3,4,6,8,10,12,15,18,20,24,28,32,38,44,48,56,64,72,80,88,96,108,120)],dtype=np.int64)
def logpower(x):
 if x<=0:return 0
 n=x.bit_length()-1
 return n*4+((x>>(n-2))&3 if n>=2 else 0)
class Spectrum:
 def __init__(self):self.hp=self.previous=0
 def frame(self,samples):
  a=np.zeros(24,dtype=np.int64);b=a.copy();energy=0
  for n,x in enumerate(samples):
   self.hp=x-self.previous+self.hp-(self.hp>>5);self.previous=x
   energy+=abs(self.hp);w=((self.hp>>4)*min(n,255-n))>>7
   v=np.clip(w+((coeff*a)>>14)-b,-8388608,8388607);b=a;a=v
  powers=np.maximum(0,a*a+b*b-((coeff*a)>>14)*b)
  logs=[logpower(int(sum(powers[k:k+3]))) for k in range(0,24,3)]
  return energy>>8,[max(-128,x-max(logs)) for x in logs]
def dtw(a,b):
 if not a or not b:return 65535
 row=[0]+[1<<30]*len(b)
 for x in a:
  prior=row[0];row[0]=1<<30
  for j,y in enumerate(b,1):
   above=row[j];row[j]=sum(abs(u-v) for u,v in zip(x,y))+min(prior,row[j-1],above);prior=above
 return row[-1]//(len(a)+len(b))
class Endpoint:
 def __init__(self,robust):
  self.robust=robust;self.cal=[];self.noise=16;self.state=0;self.onset=0;self.history=deque(maxlen=8);self.templates={};self.events=[];self.pending=0;self.segments=[]
 def frame(self,energy,feature,case,clips,amplified_energy=0):
  if len(self.cal)<32:
   self.cal.append(energy)
   if len(self.cal)==32:self.noise=sum(self.cal)//32
   return
  threshold=max(8 if self.robust else 64,4*self.noise);release=max(4 if self.robust else 32,2*self.noise)
  onset_hit=(energy>4*self.noise and amplified_energy>64) if self.robust else energy>threshold
  release_hit=(energy>2*self.noise and amplified_energy>32) if self.robust else energy>release
  if self.state==0:
   self.history.append((energy,amplified_energy,feature))
   if energy<threshold//2:self.noise+=(energy-self.noise)>>4
   if onset_hit:
    self.onset+=1
    if self.onset>=(2 if self.robust else 1):
     self.training=self.pending;self.first=case;self.state=1;self.quiet=0;self.clip_start=clips
     self.active=[f for e,a,f in self.history if e>2*self.noise and a>32] if self.robust else [feature]
     self.voiced=sum(e>4*self.noise and a>64 for e,a,f in self.history) if self.robust else 1
     self.count=len(self.active);self.onset=0
   else:self.onset=0
  else:
   self.count+=1
   if release_hit:self.active.append(feature);self.quiet=0
   else:self.quiet+=1
   if onset_hit:self.voiced+=1
   if self.count>=240:
    self.state=0;self.history.clear();return
   if self.quiet>=20:
    self.state=0;self.history.clear()
    if self.voiced<4 or (self.robust and clips-self.clip_start>2*self.count):return
    if self.training:
     self.templates[self.training]=self.active;self.pending=0
     self.segments.append(dict(case=case,train=self.training,frames=len(self.active)))
    elif len(self.templates)==3:
     scores=[dtw(self.active[:24],self.templates[k][:24]) for k in (1,2,3)]
     order=sorted(range(3),key=lambda k:scores[k]);best=order[0]+1
     full_scores=[dtw(self.active,self.templates[k]) for k in (1,2,3)]
     combined=[p+2*f for p,f in zip(scores,full_scores)]
     if self.robust:
      ranked=sorted(range(3),key=lambda k:combined[k]);best=ranked[0]+1
     full=full_scores[best-1];duration=max(len(self.active),len(self.templates[best]))<=2*min(len(self.active),len(self.templates[best]))
     if self.robust:
      po=min(scores[k] for k in range(3) if k!=best-1);fo=min(full_scores[k] for k in range(3) if k!=best-1)
      pm=po-scores[best-1];fm=fo-full
      ok=combined[ranked[0]]<=144 and combined[ranked[1]]-combined[ranked[0]]>=12 and full<=48 and scores[best-1]<=96 and pm>=0 and fm>=0 and (pm>=8 or fm>=8 or (pm>=4 and fm>=4)) and duration
     else:ok=scores[order[0]]<=96 and scores[order[1]]-scores[order[0]]>=8 and full<=96 and duration
     self.events.append(dict(case=case,id=best if ok else 0,scores=scores,full_scores=full_scores,combined=combined,full=full,frames=len(self.active)))
new,old=Endpoint(True),Endpoint(False);ns,os=Spectrum(),Spectrum()
dc=None;idx=peak=0;noise_peak=64;gain=1;clips=0;case=-1
def sat(x):return max(-32768,min(32767,x))
for first in range(0,len(data),256):
 while case+1<len(meta['cases']) and first>=meta['cases'][case+1]['first']:
  case+=1;new.pending=old.pending=meta['cases'][case]['train']
 nr=[];br=[]
 for raw in data[first:first+256]:
  if dc is None:dc=raw<<16;nr.append(0);br.append(0);continue
  delta=(raw<<16)-dc;dc+=delta>>5;mag=abs(delta>>16)
  safe=max([g for g in range(7) if mag<=30000<<(8-g)] or [0]);use=min(gain,safe)
  value=delta>>(24-use);clips+=value>32767 or value< -32768
  nr.append(sat(value));br.append(sat(delta>>23));peak=max(peak,mag);idx=(idx+1)&255
  if idx==0:
   desired=max([g for g in range(7) if peak<=8192<<(8-g)] or [0])
   if peak>max(512,3*noise_peak):
    if not new.state or desired<gain:gain=desired
   elif not new.state:gain=1;noise_peak=max(16,noise_peak+((peak-noise_peak)>>4))
   peak=0
  if safe<gain:gain=safe
 ne,nf=ns.frame(nr);oe,of=os.frame(br)
 new.frame(sum(abs(x) for x in br)//256,nf,case,clips,ne);old.frame(oe,of,case,0)
 if first%131072==0:print('MODEL',first,'/',len(data),flush=True)
results=[]
for i,c in enumerate(meta['cases']):
 if c['train']:continue
 n=[x for x in new.events if x['case']==i];o=[x for x in old.events if x['case']==i]
 row=dict(case=i,name=c['name'],expected=c['label'],divisor=c['divisor'],new=n,old=o);results.append(row)
 print('MODEL_RESULT',i,c['label'],c['divisor'],n,o,flush=True)
(D/'reference_analysis.json').write_text(json.dumps(dict(scope=__doc__,results=results,new_training=new.segments,old_training=old.segments),indent=2),encoding='utf-8')
