"""Existing human development speech with digital amplitude changes, not distance."""
from pathlib import Path
import hashlib,json,struct,wave,random
R=Path(__file__).resolve().parents[1]
OLD=Path('E:/HX4S20C_Board2/work/voice_phrasefix_20261025')
j=json.loads((OLD/'human_reference.json').read_text(encoding='utf-8'))
manifest=Path(j['manifest']);assert hashlib.sha256(manifest.read_bytes()).hexdigest()==j['manifest_sha256']
out=R/'sim/voice_data';out.mkdir(exist_ok=True)
clips=[];sources={str(manifest):hashlib.sha256(manifest.read_bytes()).hexdigest()}
for c in j['clips']:
 p=manifest.parent/c['wav'];assert hashlib.sha256(p.read_bytes()).hexdigest()==c['wav_sha256']
 sources[str(p)]=c['wav_sha256']
 with wave.open(str(p),'rb') as f:
  assert (f.getframerate(),f.getnchannels(),f.getsampwidth())==(16000,1,2)
  x=list(struct.unpack('<%dh'%f.getnframes(),f.readframes(f.getnframes())))
 s=next(s for s in j['segments'] if s['wav']==c['wav'])
 start=max(0,s['start_frame']-c['first_frame']-12)*256
 end=min(len(x),(s['end_frame']-c['first_frame']+5)*256)
 x=x[start:end];x+=[0]*((-len(x))%256)
 clips.append((c,x))
cases=[];raw=[]
def add(name,label,train,divisor,x):
 # These WAVs were already conditioned by the older recorder. Lift them into a
 # tagged 24-bit input surrogate to exercise both conditioners equally. This is
 # deliberately not represented as a raw microphone or acoustic recording.
 v=[max(-8388608,min(8388607,(n*128)//divisor+100000)) for n in x]
 v+=[100000]*((-len(v))%256)
 v+=[100000]*(40*256)
 cases.append(dict(name=name,label=label,train=train,divisor=divisor,first=len(raw),samples=len(v)))
 raw.extend(v)
for c,x in clips[:3]:add(c['wav'],c['label'],c['label'],1,x)
for divisor in (1,4,16,32):
 for c,x in clips[3:]:add(c['wav'],c['label'],0,divisor,x)
rng=random.Random(731)
add('quiet',0,0,1,[0]*(50*256))
add('low_background',0,0,1,[rng.randint(-2,2) for _ in range(60*256)])
add('single_click',0,0,1,[0]*(8*256)+[24000]*32+[0]*(40*256))
add('steady_tone',0,0,1,[800 if (n%40)<20 else -800 for n in range(50*256)])
# Enough initial quiet for noise calibration; it is sent before the case loop.
initial=[100000]*(48*256);raw=initial+raw
for c in cases:c['first']+=len(initial)
(out/'voice_raw.hex').write_text(''.join(f'{n&0xffffff:06x}\n' for n in raw),encoding='ascii')
(out/'voice_cases.hex').write_text(''.join(f'{(c["train"]<<64)|(c["label"]<<56)|(c["divisor"]<<48)|c["samples"]:018x}\n' for c in cases),encoding='ascii')
(out/'voice_counts.vh').write_text(f'`define RAW_COUNT {len(raw)}\n`define CASE_COUNT {len(cases)}\n`define INITIAL_SAMPLES {len(initial)}\n',encoding='ascii')
report=dict(scope=__doc__,sources=sources,cases=cases,total_samples=len(raw),initial_samples=len(initial),
 caveat='Digitally attenuated existing development WAVs lifted to24bit surrogate, with fixed DC offset. No physical distance/reverberation evidence. Training repeat1, distinct repeat2/3 test recordings.')
(out/'cases.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared',len(cases),'cases',len(raw),'samples')
