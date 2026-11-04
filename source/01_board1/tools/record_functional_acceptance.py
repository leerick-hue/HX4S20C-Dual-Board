"""Append full user functional acceptance and parameters to an immutable checkpoint."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,zipfile
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf8'))
def write(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
pointer=read(R/'CURRENT_HD720.json');previous=read(Path(pointer['acceptance']));bit=Path(pointer['bit']['path'])
assert sha(bit)==pointer['bit']['sha256']==previous['bit']['sha256']
source_manifest=read(Path(previous['implementation_manifest']))
for e in source_manifest['sources']:assert sha(R/e['path'])==e['sha256'],e['path']
params=R/'PARAMETERS_8D600E63.json';p=read(params);assert p['sha256']==sha(bit)
for rel in p['sources']:assert (R/rel).is_file(),rel
assert p['display']['pixels_per_frame']==1280*720
assert p['memory']['two_frame_bytes']==1280*720*2*2
assert p['memory']['two_frame_MiB']==p['memory']['two_frame_bytes']/1024**2
assert abs(p['audio']['calculated_sample_rate_hz']-750000000/61/256)<1e-6
assert p['power']['measured_watts']is None and p['power']['tool_estimated_watts']is None
record=dict(previous);record['utc']=datetime.now(timezone.utc).isoformat()
record['state']='HD720_full_function_user_accepted'
record['user_report']='全部正常 告诉我这一版的分辨率 功耗等相关参数'
record['hardware_scope']=dict(previous['hardware_scope'])
for n in ['mobile_IR','voice_commands','manual_next','auto_slideshow']:record['hardware_scope'][n]=True
record['hardware_accepted']=True
record['user_test_request']='PhoneIR next, volume down/up,mute/restore,auto on/off; voice next,pause/resume; user replied all normal.'
record['parameters']={'path':str(params),'sha256':sha(params)}
record['power_status']='Not measured; no power-analysis report; no wattage claim.'
record['extended_test_scope']='No quantified endurance,temperature-range,acoustic accuracy or latency measurement claimed.'
path=R/'audit/FUNCTIONAL_ACCEPTANCE_8D600E63_20261030.json';assert not path.exists();write(path,record)
hardware=read(R/'HARDWARE_STATUS.json');hardware['current']=record;write(R/'HARDWARE_STATUS.json',hardware)
delivery=read(R/'delivery_route_comparison.json');delivery.update(status='User accepted photo/audio,IR,voice andalbum controls',hardware_accepted=True,hardware_acceptance_record=str(path));write(R/'delivery_route_comparison.json',delivery)
old=Path(pointer['checkpoint']['path']);assert sha(old)==pointer['checkpoint']['sha256']
archive=R/'checkpoints/HD720_FUNCTIONAL_8D600E63_ACCEPTED_20261030.zip';assert not archive.exists()
with zipfile.ZipFile(old)as z:
 assert z.testzip()is None
 payload={i.filename:z.read(i.filename)for i in z.infolist()if i.filename!='SHA256SUMS.json'}
 before=json.loads(z.read('SHA256SUMS.json'))
 for name,h in before.items():assert hashlib.sha256(payload[name]).hexdigest()==h,name
for name in ['README.md','VALIDATION.md','ROUTE_COMPARISON.md','HARDWARE_STATUS.json','delivery_route_comparison.json','PARAMETERS_8D600E63.json','PARAMETERS_8D600E63.md']:
 payload['records/'+name]=(R/name).read_bytes()
payload['records/FUNCTIONAL_ACCEPTANCE.json']=path.read_bytes()
payload['tools/record_functional_acceptance.py']=Path(__file__).read_bytes()
hashes={name:hashlib.sha256(data).hexdigest()for name,data in payload.items()}
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6)as z:
 for name,data in sorted(payload.items()):z.writestr(name,data)
 z.writestr('SHA256SUMS.json',json.dumps(hashes,indent=2)+'\n')
with zipfile.ZipFile(archive)as z:
 assert z.testzip()is None
 for name,h in hashes.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
assert sha(bit)==p['sha256']
pointer.update(state=record['state'],acceptance=str(path),checkpoint={'path':str(archive),'sha256':sha(archive),'entries_verified':len(hashes)},parameters=str(R/'PARAMETERS_8D600E63.md'),next='Keep this exact bit; power measurements may be added separately.')
write(R/'CURRENT_HD720.json',pointer)
print('Recorded full functional acceptance; frozen',len(hashes),'entries; bit unchanged',sha(bit),flush=True)
