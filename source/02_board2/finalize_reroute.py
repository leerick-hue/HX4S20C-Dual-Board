"""Bind a successful post-route artifact to the original compiled inputs."""
from pathlib import Path
import hashlib,json,re,shutil
R=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
old_dir=R/'build_attempts/seed45_timing_failed'
old_path=old_dir/'manifest.json';old=json.loads(old_path.read_text())
old_stage=Path(old['stage']);stage=R/'postroute_reroute'
db=old_dir/'diag_pr.db'
assert sha(db)==sha(old_stage/'diag_pr.db')
assert all(sha(old_dir/n)==h==sha(old_stage/n) for n,h in old['build_reports_sha256'].items())
sources={n:h for n,h in old['sources'].items() if n not in ('src/timing.sdc','build.tcl')}
assert all(sha(R/n)==h for n,h in sources.items()),'Compiled RTL/IP/project identity changed'
before=(old_stage/'src/timing.sdc').read_text().splitlines()
after=(R/'src/timing.sdc').read_text().splitlines()
start=before.index('# aspect_16x9 is a quasi-static clip property (assign aspect_16x9 = img_height==180).')
end=before.index('set_false_path -to [get_regs {motion/aspect_sync[0]}]')
assert before[:start]+before[end+1:]==after,'Only the removed-register exception may differ'
sources.update({'src/timing.sdc':sha(R/'src/timing.sdc'),'reroute_opt.tcl':sha(R/'reroute_opt.tcl')})
status=(stage/'diag_phy.ts').read_text();timing=(stage/'diag_final.timing').read_text()
setup=float(re.search(r'SWNS:\s*([-\d.]+)',status)[1]);hold=float(re.search(r'HWNS:\s*([-\d.]+)',status)[1])
assert setup>=0 and hold>=0,(setup,hold)
assert float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1])>=99.9
clocks={name:float(freq) for freq,name in re.findall(r'^\s*clk\d+:\s*([\d.]+)\s+\d+\s+(\S+)',timing,re.M)}
assert len(clocks)>=8
for name,freq in {'ref_clk':50,'memory_pll/pll_inst.clkc[3]':40,'hd$pll/pll_inst.clkc[1]':74.25}.items():
    assert name in clocks and abs(clocks[name]-freq)<.02,(name,clocks)
log=(stage/'console.log').read_text(errors='replace')
assert 'ERROR' not in log and 'Oops!' not in log
bit=stage/'HDMI_TPG_DIAG.bit';assert bit.is_file()
out=R/'build_reroute';out.mkdir(exist_ok=True)
names=('diag_phy.ts','diag_final.timing','diag_phy.area','HDMI_TPG_DIAG.bit','diag_pr.db','console.log')
for name in names:shutil.copy2(stage/name,out/name)
report=dict(build_pass=True,timing_pass=True,setup_ns=setup,hold_ns=hold,stage=str(stage),
            sources=sources,sources_unchanged=True,errors=[],bit_sha256=sha(bit),hardware_tested=False,
            build_reports_sha256={n:sha(stage/n) for n in ('diag_phy.ts','diag_final.timing','diag_phy.area')},
            flow='Fresh-session import of seed45 compiled checkpoint, original actual-clock constraints, normal reroute with extra optimization rounds; no RTL resynthesis',
            compiled_basis_manifest=str(old_path),compiled_basis_manifest_sha256=sha(old_path),
            compiled_basis_db=str(db),compiled_basis_db_sha256=sha(db),
            compiled_basis_original_stage=str(old_stage),compiled_recipe_sha256=sha(old_stage/'build.tcl'),
            constraint_change='Only deletion of false_path to nonexistent aspect_sync; source equivalence verified line by line',
            before_timing_sha256=sha(stage/'before.timing'),clocks_mhz=clocks)
(out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ('build_pass','setup_ns','hold_ns','bit_sha256','clocks_mhz')},indent=2))
