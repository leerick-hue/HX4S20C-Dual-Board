"""Read retained routed databases in isolated project copies; export actual cells."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,tempfile
R=Path(__file__).resolve().parents[1];OLD=Path(json.loads((R/'BASELINE.json').read_text(encoding='utf8'))['source'])
TD='E:/TD/TD/bin/td_commands_prompt.exe'
jobs=[('accepted',OLD,'photo_probe_clean_seed11_hold'),('failed',R,'hd720_controls_release')]
for label,root,name in jobs:
 out=R/'audit/implementation'/label;out.mkdir(parents=True,exist_ok=False)
 m=json.loads((root/'build'/name/'manifest.json').read_text(encoding='utf8'))
 db=Path(m['routed_db']);assert db.is_file(),str(db)
 stage=Path(tempfile.mkdtemp(prefix='hx_impl_'+label+'_'))
 for d in ['src','rtl']:shutil.copytree(root/d,stage/d)
 project=stage/'src/td_project/HX4S20C_Extensions.al'
 s=project.read_text(encoding='utf8');s=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*',lambda q:q[1]+project.parent.as_posix(),s,count=1);project.write_text(s,encoding='utf8')
 script=f'''import_device eagle_s20.db -package EG4S20BG256
open_project -single_run {{{project.as_posix()}}}
import_db {{{db.as_posix()}}}
update_timing -mode final
write_verilog {{{(out/'routed.v').as_posix()}}}
report_cells [get_cells {{video_pll_m0/pll_inst}}] -connection -timing -mode final
report_cells [get_cells {{u_hdmi2phy_wrapper/u3_lane_lvds_8_1/*}}] -connection
close_project
exit
'''
 (stage/'inspect.tcl').write_text(script,encoding='utf8')
 print('Inspecting',label,db,flush=True)
 with(out/'console.log').open('w',encoding='utf8')as log:p=subprocess.run([TD,'inspect.tcl'],cwd=stage,stdout=log,stderr=subprocess.STDOUT)
 report={'label':label,'exit':p.returncode,'source_root':str(root),'db':str(db),'db_sha256':hashlib.sha256(db.read_bytes()).hexdigest(),'stage':str(stage),'netlist':str(out/'routed.v')}
 (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
 assert p.returncode==0 and (out/'routed.v').is_file(),(out/'console.log').read_text(encoding='utf8')[-2000:]
 print('Exported',label,(out/'routed.v').stat().st_size,flush=True)
