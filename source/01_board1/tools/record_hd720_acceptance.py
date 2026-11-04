"""Freeze exactly the user-accepted photo/audio implementation without rebuilding."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,zipfile
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf8'))
def write(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
manifest=R/'build/hd720_controls_seed11/manifest.json';m=read(manifest)
delivery=R/'delivery_route_comparison.json';d=read(delivery);bit=Path(d['file'])
assert m['pass'] and sha(bit)==d['sha256']==m['bit_sha256']=='8d600e63c8ef8777cd048737b1a086dc5403e3adb5f059e10513c21608df48bc'
for e in m['sources']:assert sha(R/e['path'])==e['sha256'],e['path']
guard=read(R/'build/hd720_guard_verified/manifest.json')
assert guard['hold_repair_skipped']and guard['bit_sha256']==sha(bit)and guard['timing_closed']
previous=read(R/'HARDWARE_STATUS.json')
utc=datetime.now(timezone.utc).isoformat()
record={'utc':utc,'date_local':'2026-10-30','state':'HD720_photo_audio_user_accepted_controls_pending',
 'bit':{'path':str(bit),'sha256':sha(bit),'bytes':bit.stat().st_size},'user_report':'9CF1F7 照片声音全部恢复',
 'hardware_scope':{'photo_display':True,'TF_audio':True,'mobile_IR':None,'voice_commands':None,'manual_next':None,'auto_slideshow':None,'extended_run':None,'repeated_reset':None},
 'configured_video':{'width':1280,'height':720,'nominal_fps':60,'storage':'RGB565','aspect_fit':True,'video_decoder_enabled':False},
 'setup_ns':d['setup_ns'],'hold_ns':d['hold_ns'],'implementation_manifest':str(manifest),'implementation_manifest_sha256':sha(manifest),
 'regression_isolated_to_post_route_hold_repair_result':True,'underlying_physical_mechanism_confirmed':False,
 'failed_implementation_sha256':'08977bfb14a461de72046d097e7d8f678a37026f3f0a72ed0e1e1f6336189d5f',
 'build_guard_verified':str(R/'build/hd720_guard_verified/manifest.json'),'agent_programmed_hardware':False,'agent_wrote_TF_card':False}
record_path=R/'audit/BOARD_ACCEPTANCE_8D600E63_20261030.json';assert not record_path.exists();write(record_path,record)
write(R/'HARDWARE_STATUS.json',{'current':record,'previous_failed_impl_evidence':previous})
d.update(status='User accepted photo/audio at9CF1F7; controls regression pending',photo_audio_hardware_accepted=True,hardware_acceptance_record=str(record_path))
# hardware_accepted remains false until the complete requested control scope passes.
write(delivery,d)
checkpoints=R/'checkpoints';checkpoints.mkdir(exist_ok=True)
archive=checkpoints/'HD720_PHOTO_AUDIO_8D600E63_ACCEPTED_20261030.zip';assert not archive.exists()
files={f'production/{e["path"]}':R/e['path']for e in m['sources']}
files[f'firmware/{bit.name}']=bit
db=Path(m['workspace'])/'build/HX4S20C_UNIFIED_pr.db';assert db.is_file()
files['implementation/HX4S20C_UNIFIED_pr.db']=db
files['implementation/effective_build.tcl']=Path(m['workspace'])/'build.tcl'
for p in manifest.parent.iterdir():
 if p.is_file()and p.suffix in ['.json','.timing','.ts','.area']:files['implementation/'+p.name]=p
for n in ['README.md','VALIDATION.md','ROUTE_COMPARISON.md','HARDWARE_STATUS.json','delivery_route_comparison.json','BASELINE.json']:
 files['records/'+n]=R/n
files['records/BOARD_ACCEPTANCE.json']=record_path
for p in (R/'tools').glob('*.py'):files['tools/'+p.name]=p
for p in (R/'sim').glob('*'):
 if p.is_file():files['sim/'+p.name]=p
for n in ['keymap','infrared','ack','scale','ui','album720','acr_service_top','hdmi_native_core']:
 p=R/'sim_logs'/n/'summary.json';assert read(p)['pass'];files[f'simulation/{n}/summary.json']=p
hashes={name:sha(p)for name,p in files.items()}
with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6)as z:
 for name,p in sorted(files.items()):z.write(p,name)
 z.writestr('SHA256SUMS.json',json.dumps(hashes,indent=2)+'\n')
with zipfile.ZipFile(archive)as z:
 assert z.testzip()is None
 for name,h in hashes.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
assert sha(bit)==record['bit']['sha256']
for e in m['sources']:assert sha(R/e['path'])==e['sha256']
pointer={'date_local':'2026-10-30','state':record['state'],'bit':record['bit'],'acceptance':str(record_path),
 'checkpoint':{'path':str(archive),'sha256':sha(archive),'entries_verified':len(hashes)},'next':'Hardware regression of IR/voice/album controls on this same bit; no re-download required.'}
write(R/'CURRENT_HD720.json',pointer)
print('Frozen user-accepted HD720 photo/audio:',bit.name,'archive',archive,'verified entries',len(hashes),flush=True)
