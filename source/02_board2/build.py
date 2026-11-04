"""Stage, compile and fingerprint this isolated candidate; never programs a device."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,uuid,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
stage=R/'build_stages'/uuid.uuid4().hex[:10];stage.mkdir(parents=True)
out=R/'build';out.mkdir(exist_ok=True)
files=[p for folder in ('src','project','user_source') for p in (R/folder).rglob('*') if p.is_file()]+[R/'build.tcl']
hashes={p.relative_to(R).as_posix():sha(p) for p in files}
for p in files:
 d=stage/p.relative_to(R);d.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,d)
p=stage/'project/HX4S20C_Extensions.al';tree=ET.parse(p);tree.getroot().set('Path',p.parent.as_posix());tree.write(p,encoding='utf8',xml_declaration=True)
print('STAGE',stage,flush=True)
with (out/'console.log').open('w') as log:
 run=subprocess.Popen(['E:/TD/TD/bin/td_commands_prompt.exe','build.tcl'],cwd=stage,stdout=log,stderr=subprocess.STDOUT)
 (out/'process.json').write_text(json.dumps(dict(pid=run.pid,stage=str(stage))))
 run.wait()
log=(out/'console.log').read_text(errors='replace')
errors=re.findall(r'^.*(?:ERROR|Error:).*$',log,re.M)
bit=stage/'HDMI_TPG_DIAG.bit'
unchanged=all(sha(R/p)==h for p,h in hashes.items())
ok=run.returncode==0 and bit.exists() and not errors and unchanged
setup=hold=None
if (stage/'diag_phy.ts').is_file():
 status=(stage/'diag_phy.ts').read_text()
 sm=re.search(r'SWNS:\s*([-\d.]+)',status);hm=re.search(r'HWNS:\s*([-\d.]+)',status)
 if sm and hm:setup,hold=float(sm[1]),float(hm[1])
timing_ok=setup is not None and hold is not None and setup>=0 and hold>=0
ok=ok and timing_ok
for p in stage.iterdir():
 if p.is_file() and p.suffix in ('.bit','.area','.timing','.ts','.db','.txt'):shutil.copy2(p,out/p.name)
result=dict(build_pass=ok,exit_code=run.returncode,stage=str(stage),sources=hashes,sources_unchanged=unchanged,errors=errors,bit_sha256=sha(bit) if bit.exists() else None,hardware_tested=False)
result.update(setup_ns=setup,hold_ns=hold,timing_pass=timing_ok)
result['build_reports_sha256']={n:sha(out/n) for n in ('diag_phy.ts','diag_final.timing','diag_phy.area') if (stage/n).is_file()}
(out/'manifest.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print('BUILD PASS' if ok else 'BUILD FAIL',flush=True)
if not ok:print(log[-6000:])
raise SystemExit(0 if ok else 1)
