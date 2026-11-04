"""Publish the isolated 480p candidate only when current evidence passes."""
from pathlib import Path
import hashlib,json,re,shutil,struct,zlib,sys
R=Path(__file__).resolve().parent
B=R/('build_reroute' if '--reroute' in sys.argv else 'build')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def test(pattern):
    paths=sorted((R/'sim_logs').glob(pattern));assert paths,pattern
    p=paths[-1];d=read(p)
    assert d['passed'],f'Latest test failed: {p}'
    assert d.get('results') and d.get('scope') and d.get('sources'),f'Incomplete evidence: {p}'
    assert all(sha(Path(n))==h for n,h in d['sources'].items()),f'Stale evidence: {p}'
    return dict(path=str(p),sha256=sha(p),scope=d['scope'],results=d['results'])
def rate_test():
    paths=sorted((R/'sim_logs').glob('rate480_*/summary.json'));assert paths
    p=paths[-1];d=read(p)
    if d['passed']:return test('rate480_*/summary.json')
    # A separate audit may qualify steady state while retaining the original
    # startup-inclusive failure. It must bind exactly the latest failed run.
    qpath=p.parent/'qualified_rate.json';q=read(qpath)
    assert q['passed'] and q['original_average_failed'] and not q['original_passed']
    assert Path(q['original_summary'])==p and q['original_summary_sha256']==sha(p)
    assert q['raw_log_sha256']==sha(Path(q['raw_log']))
    assert q['sources']==d['sources'] and all(sha(Path(n))==h for n,h in q['sources'].items())
    assert q['steady_state_fps']>=14.7 and q['steady_state_swap_range']==[2,6]
    assert q['dropped_frames']==q['underruns']==q['late_frames']==0
    return dict(path=str(qpath),sha256=sha(qpath),scope=q['qualification'],
                original_report=str(p),original_passed=False,original_average_failed=True,
                results={k:q[k] for k in ('startup_interval_ms','startup_inclusive_fps','all_intervals_ms','steady_state_fps','checked_display_pixels','decode_due')})
def main():
    assert __debug__,'Assertions required'
    m=read(B/'manifest.json')
    assert m['build_pass'] and m['sources_unchanged'] and not m['errors']
    assert all(sha(R/n)==h for n,h in m['sources'].items()),'Build inputs changed'
    stage=Path(m['stage']);bit=B/'HDMI_TPG_DIAG.bit'
    assert sha(bit)==m['bit_sha256']==sha(stage/bit.name)
    for n,h in m['build_reports_sha256'].items():assert sha(B/n)==h==sha(stage/n)
    status=(B/'diag_phy.ts').read_text();timing=(B/'diag_final.timing').read_text()
    setup=float(re.search(r'SWNS:\s*([-\d.]+)',status)[1]);hold=float(re.search(r'HWNS:\s*([-\d.]+)',status)[1])
    assert setup>=0 and hold>=0,(setup,hold)
    assert 'Both (Slow and Fast)' in timing
    assert all(re.search(c+r'\s*\| yes\s+yes',timing) for c in ('Slow','Fast'))
    coverage=float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1]);assert coverage>=99.9
    clocks={name:float(freq) for freq,name in re.findall(r'^\s*clk\d+:\s*([\d.]+)\s+\d+\s+(\S+)',timing,re.M)}
    assert len(clocks)>=8,'Actual clock definitions missing'
    for name,freq in {'ref_clk':50,'memory_pll/pll_inst.clkc[3]':40,'hd$pll/pll_inst.clkc[1]':74.25}.items():
        assert name in clocks and abs(clocks[name]-freq)<.02,(name,clocks)
    sample=read(R/'media/RTL_SAMPLE_CHECK.json');assert sample['passed']
    assert all(sha(Path(n))==h for n,h in sample['sources'].items()),'Changed JPEG evidence'
    tests={n:test(p) for n,p in [('video','video480_*/summary.json'),('coexist','coexist_*/summary.json')]}
    tests['rate']=rate_test()
    tests['jpeg_reference']=dict(path=str(R/'media/RTL_SAMPLE_CHECK.json'),sha256=sha(R/'media/RTL_SAMPLE_CHECK.json'),scope=sample['scope'],results=sample['results'],numerical_tolerance=sample['numerical_tolerance'])
    baseline=read(R/'BASELINE.json');parent=Path(baseline['parent'])
    allowed={'src/video_source.v','src/video_path.v','src/mjpeg_video_player.v','src/timing.sdc'}
    production=[f for f in baseline['files'] if f['path'].startswith(('src/','project/','user_source/'))]
    changed=[f['path'] for f in production if sha(R/f['path'])!=f['sha256']]
    assert set(changed)<=allowed,changed
    assert all(sha(parent/f['path'])==f['sha256'] for f in production),'Parent sources changed'
    media=read(R/'media/MEDIA_REPORT.json');card=Path(media['card']['path']);assert sha(card)==media['card']['sha256']==sample['card_sha256']
    # Tie every tested/source JPEG to its actual payload in the delivered card.
    raw=card.read_bytes();base,video_sectors,total=struct.unpack_from('<3I',raw,40)
    assert raw[36:40]==b'HXUV' and total*512==len(raw) and base==8
    header=struct.unpack_from('<4s20I',raw,base*512)
    assert header[:9]==(b'HXJV',1,512,0,640,480,15,1,300)
    assert header[17]==video_sectors
    for i in range(300):
        lba,n,pts,crc=struct.unpack_from('<4I',raw,(base+header[9])*512+i*16)
        blob=raw[(base+lba)*512:(base+lba)*512+n]
        assert pts==3200*i and 4<=n<=50000
        assert zlib.crc32(blob)==crc and blob==(R/'media/frames'/f'frame_{i:08d}.jpg').read_bytes(),f'Card frame mismatch: {i}'
    area=(B/'diag_phy.area').read_text()
    resources={n:int(re.search(r'^#'+n+r'\s+(\d+)',area,re.M)[1]) for n in ('lut','reg','le','bram','dsp','pll')}
    out=R/'DELIVERY';out.mkdir(exist_ok=True)
    dest=out/('HX4S20C_BOARD2_VIDEO_480P15_'+sha(bit)[:8].upper()+'.bit')
    if dest.exists():assert sha(dest)==sha(bit)
    else:shutil.copy2(bit,dest)
    report=dict(state='software_verified_480p_candidate_pending_hardware',hardware_tested=False,bit=str(dest),sha256=sha(dest),
                setup_ns=setup,hold_ns=hold,sta_coverage_percent=coverage,clocks_mhz=clocks,resources=resources,
                source_video=dict(width=640,height=480,fps=15),hdmi=dict(width=1280,height=720,nominal_hz=60,window=[320,120,640,480]),
                card=media['card'],tests=tests,changed_production=changed,build_manifest_path=str(B/'manifest.json'),build_manifest_sha256=sha(B/'manifest.json'),
                limits=['Native centred640x480 window, no full-screen scaler','No audio soundtrack',
                        '15fps refers to steady state; startup-inclusive rate and first-swap interval reported separately',
                        'Sampled JPEGs, not all300frames in RTL; bounded fixed-point C-reference differences explicitly recorded',
                        'Functional SDRAM and synthetic sector service; actual card/receiver/frame rate pending hardware',
                        'Coexistence injects recognition events, not physical speech-recognition acceptance',
                        'Inherited voice acquisition issue remains unresolved; no hardware programming or physical card write'])
    (R/'DELIVERY.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    (out/'SHA256SUMS.txt').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in (dest,card)))
    print(json.dumps({k:report[k] for k in ('state','bit','sha256','setup_ns','hold_ns','resources')},indent=2))
if __name__=='__main__':main()
