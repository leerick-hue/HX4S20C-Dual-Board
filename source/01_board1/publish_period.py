"""Publish only the current, timing-clean board-one period candidate."""
from pathlib import Path
import hashlib,json,re,shutil
R=Path(__file__).resolve().parent
B=R/'build/album_period_seed11'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def latest(pattern):
    files=sorted((R/'sim_logs').glob(pattern));assert files,pattern
    return files[-1]
def check_test(path):
    d=read(path);assert d.get('pass') is True,f'Latest test failed: {path}'
    assert d.get('sources') and all(sha(Path(n))==h for n,h in d['sources'].items()),f'Stale test: {path}'
    return d
def main():
    assert __debug__
    m=read(B/'manifest.json');stage=Path(m['workspace'])
    assert m['pass'] and m['bit_generated'] and not m['errors']
    assert not m['changed_during_build'] and not m['unexpected_stage_changes']
    assert m['strategy_overrides']=={'place.seed':11,'rtl.min_ripple_len':5}
    assert sha(R/'tools/build_video.py')==m['build_helper_sha256']
    for e in m['sources']:assert sha(R/e['path'])==e['sha256'],e['path']
    for e in m['staged_sources']:
        if e['path']=='src/td_project/HX4S20C_Extensions.al':
            assert sha(stage/e['path'])==m['stage_project_sha256'] and m['project_metadata_only']
        else:assert sha(stage/e['path'])==e['sha256'],e['path']
    reports=('HX4S20C_UNIFIED_phy.ts','HX4S20C_UNIFIED_pr.timing','HX4S20C_UNIFIED_phy.area')
    for n in reports:assert sha(B/n)==sha(stage/'build'/n),n
    status=(B/reports[0]).read_text();timing=(B/reports[1]).read_text()
    setup=float(re.search(r'SWNS:\s*([-\d.]+)',status)[1]);hold=float(re.search(r'HWNS:\s*([-\d.]+)',status)[1])
    assert setup>=0 and hold>=0,(setup,hold)
    assert 'Both (Slow and Fast)' in timing
    assert all(re.search(c+r'\s*\| yes\s+yes',timing) for c in ('Slow','Fast'))
    coverage=float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1]);assert coverage>=99.9
    clocks={name:float(freq) for freq,name in re.findall(r'^\s*clk\d+:\s*([\d.]+)\s+\d+\s+(\S+)',timing,re.M)}
    assert len(clocks)>=10
    for n,f in {'clk':50,'jpeg_clk':40,'ext_mem_clk':50,'video_clk':74.25,'sd_card_clk':100}.items():
        assert n in clocks and abs(clocks[n]-f)<.02,(n,clocks)
    bit=B/'HX4S20C_UNIFIED_TEST.bit';assert sha(bit)==m['bit_sha256']==sha(stage/'build'/bit.name)
    unitpath=latest('period_unit_*/summary.json');unit=check_test(unitpath)
    assert unit.get('results')
    tests={'unit':dict(path=str(unitpath),sha256=sha(unitpath),scope=unit['scope'],results=unit['results'])}
    for job in ('album','ui','infrared'):
        path=latest(f'period_integration_*/{job}/summary.json');d=check_test(path)
        assert d.get('markers') and any('PASS ' in line for line in d['markers'])
        rootstage=Path(d['stage']).parent.parent
        for n,h in d['sources'].items():assert sha(rootstage/Path(n).relative_to(R))==h
        if job=='album':
            assert len(d['frames'])==4
            for index,e in enumerate(d['frames']):
                assert e['words']==460800
                actual=Path(d['stage'])/f'frame_{index}.hex'
                golden=rootstage/'fixtures'/f"photo{e['asset']}.hex"
                assert sha(actual)==e['sha256'] and sha(golden)==e['reference_sha256']
                assert actual.read_text().lower().split()==golden.read_text().lower().split()
        tests[job]=dict(path=str(path),sha256=sha(path),results=d['markers'])
    baseline=read(R/'BASELINE.json');parent=Path(baseline['parent'])
    production=[e for e in baseline['sources'] if e['path'].startswith(('src/','rtl/'))]
    changed=[e['path'] for e in production if sha(R/e['path'])!=e['sha256']]
    assert changed==['src/user_source/hdl_source/SD/sd_card_bmp.v'],changed
    assert all(sha(parent/e['path'])==e['sha256'] for e in production),'Parent sources changed'
    basebit=Path(baseline['board1_base_bit'])
    assert sha(basebit)=='8d600e63c8ef8777cd048737b1a086dc5403e3adb5f059e10513c21608df48bc'
    area=(B/reports[2]).read_text();resources={n:int(re.search(r'^#'+n+r'\s+(\d+)',area,re.M)[1]) for n in ('lut','reg','le','bram','dsp','pll')}
    out=R/'DELIVERY';out.mkdir(exist_ok=True)
    dest=out/('HX4S20C_BOARD1_ALBUM_PERIOD_'+sha(bit)[:8].upper()+'.bit')
    if dest.exists():assert sha(dest)==sha(bit)
    else:shutil.copy2(bit,dest)
    report=dict(state='software_verified_board1_period_pending_hardware',hardware_tested=False,bit=str(dest),sha256=sha(dest),
                setup_ns=setup,hold_ns=hold,sta_coverage_percent=coverage,clocks_mhz=clocks,resources=resources,
                periods_seconds=[1,2,5,10,30],default_period_seconds=1,default_auto_enabled=False,
                physical_keys={'KEY1':'reset','KEY2_B2':'next photo','KEY3_B1':'edit mode','KEY4_C1':'short-release auto toggle; hold1.2s step period'},
                tests=tests,changed_production=changed,build_manifest=str(B/'manifest.json'),build_manifest_sha256=sha(B/'manifest.json'),
                report_hashes={n:sha(B/n) for n in reports},baseline_bit_sha256=sha(basebit),
                limits=['Timing-clean candidate, no physical programming or TF write',
                        'Each period is idle display dwell time; image load/commit/fade adds to observed interval',
                        'One long press advances one tier; reset/power loss clears tier to1s',
                        'No on-screen numeric period readout added',
                        'Functional album/PCM app model, not physical SD/SDRAM/HDMI electrical acceptance'])
    (R/'DELIVERY.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    (out/'SHA256SUMS.txt').write_text(sha(dest)+'  '+dest.name+'\n')
    print(json.dumps({k:report[k] for k in ('state','bit','sha256','setup_ns','hold_ns','resources')},indent=2))
if __name__=='__main__':main()
