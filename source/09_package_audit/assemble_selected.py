"""Snapshot the two selected releases without building or programming hardware."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT=Path('E:/HX4S20C_Deliveries/HX4S20C_8EB7D133_6F5DD197_FULL_20261103')
BOARDS=[Path('E:/HX4S20C_Test_20261026/board1_album_period_20261103'),
        Path('E:/HX4S20C_Test_20261026/board2_video480p15_20261102')]
DEST=[ROOT/'01_board1',ROOT/'02_board2']
SKIP={'.git','__pycache__','sim_stages','build_stages'}
records=[]

def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()

def save(p,obj):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf8')

def copy(p,d):
    d.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(p,d)
    h=sha(p)
    assert sha(d)==h
    records.append(dict(origin=str(p),path=d.relative_to(ROOT).as_posix(),sha256=h))

def tree(p,d):
    for f in sorted(p.rglob('*')):
        if f.is_file() and not any(s in SKIP for s in f.relative_to(p).parts) and f.suffix.lower() not in ('.dmp','.wlf','.pyc'):
            copy(f,d/f.relative_to(p))

for name in ('00_firmware_current','03_media','04_tools','05_docs','06_validation',
             '07_dependencies','08_licenses','09_package_audit'):
    (ROOT/name).mkdir(exist_ok=True)
deliveries=[]
checks=[]
external={}
sdk={}
for board,dest in zip(BOARDS,DEST):
    assert not dest.exists(),dest
    d=json.loads((board/'DELIVERY.json').read_text(encoding='utf8'))
    bit=Path(d['bit']);assert sha(bit)==d['sha256']
    manifest_path=Path(d.get('build_manifest',d.get('build_manifest_path')))
    assert sha(manifest_path)==d['build_manifest_sha256']
    m=json.loads(manifest_path.read_text(encoding='utf8'))
    assert m.get('pass',m.get('build_pass')) and m['bit_sha256']==d['sha256']
    sources=m['sources']
    entries=sources.items() if isinstance(sources,dict) else ((x['path'],x['sha256']) for x in sources)
    count=0
    for name,h in entries:
        assert sha(board/name)==h,('Build input mismatch',name)
        count+=1
    for name,h in d['report_hashes' if 'report_hashes' in d else 'unused'].items() if 'report_hashes' in d else m['build_reports_sha256'].items():
        assert sha(manifest_path.parent/name)==h,('Report mismatch',name)
    for name,t in d['tests'].items():
        p=Path(t['path']);assert sha(p)==t['sha256'],p
        report=json.loads(p.read_text(encoding='utf8'))
        assert report.get('passed',report.get('pass')),('Selected test not passed',p)
        for path,h in report.get('sources',{}).items():
            original=Path(path)
            assert sha(original)==h,('Test input changed',path)
            if not any(original.is_relative_to(root) for root in BOARDS):
                (sdk if original.is_relative_to(Path('E:/TD')) else external)[path]=h
        checks.append(dict(board=board.name,test=name,report=str(p),sha256=t['sha256'],selected_passed=True))
    tree(board,dest)
    copy(bit,ROOT/'00_firmware_current'/bit.name)
    deliveries.append(dict(board=board.name,bit=bit.name,sha256=d['sha256'],build_inputs=count,
                           setup_ns=d['setup_ns'],hold_ns=d['hold_ns'],hardware_tested=d['hardware_tested']))

# Support files used by the published regressions and media generators.
album=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/media_hd_unified_20261025')
jpeg=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/mjpeg_20261023')
peer=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/phone_ir_fit_link_ack_20261030/src/user_source/hdl_source/extensions')
tree(album/'sim/fixtures',ROOT/'07_dependencies/album_fixture_root/sim/fixtures')
tree(jpeg/'vendor/core_jpeg',ROOT/'07_dependencies/jpeg_reference_root/vendor/core_jpeg')
copy(jpeg/'decode_sim/tb_jpeg_decode.sv',ROOT/'07_dependencies/jpeg_reference_root/decode_sim/tb_jpeg_decode.sv')
for name in ('board_remote_control.v','uart_rx.v','event_packet_rx.v','event_fifo.v'):
    copy(peer/name,ROOT/'07_dependencies/peer'/name)
conditioner=Path('E:/HX4S20C_Board2/work/link_ack_20261026/data/conditioner.mem')
prefix=Path('E:/HX4S20C_Test_20261026/board2_adaptive_voice_20261101/media_bbb_20261102/DELIVERY/CARD_BBB_20s_320x240_25fps.img')
copy(conditioner,ROOT/'07_dependencies/conditioner.mem')
copy(prefix,ROOT/'07_dependencies/old320_prefix.img')
for origin,h in external.items():
    assert any(r['origin']==origin and r['sha256']==h for r in records),('Unbundled external test dependency',origin)
save(ROOT/'07_dependencies/PATH_MAP.json',{
    album.as_posix():'07_dependencies/album_fixture_root',
    jpeg.as_posix():'07_dependencies/jpeg_reference_root',
    peer.as_posix():'07_dependencies/peer',
    conditioner.as_posix():'07_dependencies/conditioner.mem',
    prefix.as_posix():'07_dependencies/old320_prefix.img'})
save(ROOT/'07_dependencies/REQUIRED_VENDOR_MODELS.json',sdk)

# One clearly labelled current video image and its preview.
b2=BOARDS[1]
for name in ('CARD_BBB_20s_640x480_15fps.img','BBB_480p15_preview.mp4','preview_640x480.png'):
    copy(b2/'DELIVERY'/name,ROOT/'03_media/board2_480p15'/name)
card=json.loads((b2/'DELIVERY.json').read_text())['card']
assert sha(ROOT/'03_media/board2_480p15'/Path(card['path']).name)==card['sha256']
assert sha(DEST[1]/'media/source_hd.mp4')==json.loads((DEST[1]/'media/SOURCE.json').read_text())['sha256']
prepared=Path('E:/HX4S20C_Deliveries/CARD_MEDIA_20261102_211850')
for folder in ('album1_bmp','album2_bmp','sources/photos','tools'):
    tree(prepared/folder,ROOT/'03_media/board1_examples'/folder)
for f in (prepared/'DELIVERY').iterdir():
    if f.is_file() and (f.name.startswith(('01_ALBUM','02_ALBUM')) or f.name in ('PHOTO_SOURCES.json','ALBUMS.json','SOURCES.md')):
        copy(f,ROOT/'03_media/board1_examples/DELIVERY'/f.name)
(ROOT/'03_media/board1_examples/README.md').write_text(
    '# 板一示例相册素材\n\n来自2026-11-02已准备的相册资源与制作工具；并非本轮读取的实物TF卡备份。'
    '板一新固件保持原相册格式，可继续使用原来正常的相册卡。此处只收录相册示例，板二当前卡必须使用board2_480p15中的640×480/15fps镜像。\n',encoding='utf8')
for f in Path('E:/HX4S20C_Test_20261026/tools').glob('*.py'):
    copy(f,ROOT/'04_tools/media_tools'/f.name)
old=Path('E:/HX4S20C_Deliveries/HX4S20C_GROUP2_8D600E63_DDF17025_20261102_205448')
for name in ('capture_pcm.py','read_mic_diag.py','check_card.py','pack_tf_audio.py','test_pack_tf_audio.py','requirements.txt'):
    copy(old/'04_tools'/name,ROOT/'04_tools'/name)
copy(old/'05_docs/WIRING_CURRENT.md',ROOT/'05_docs/WIRING_INHERITED.md')
copy(jpeg/'vendor/core_jpeg/LICENSE',ROOT/'08_licenses/core_jpeg_LICENSE')
copy(b2/'media/SOURCE.json',ROOT/'08_licenses/BBB_SOURCE.json')
copy(Path(__file__),ROOT/'09_package_audit/assemble_selected.py')
save(ROOT/'06_validation/INPUT_VERIFICATION.json',dict(passed=True,releases=deliveries,tests=checks,
    selected_firmware_unchanged=True,all_build_inputs_match=True,all_selected_test_inputs_match=True,
    card_and_video_source_hashes_match=True,rebuild_performed=False,hardware_or_card_writes=False,
    note='Recorded software passes are source-bound evidence; neither release is newly hardware accepted. Original rate startup-average failure retained.'))
save(ROOT/'09_package_audit/PROVENANCE.json',records)
save(ROOT/'09_package_audit/README_FACTS.json',dict(releases=deliveries,
    directories=[p.name for p in ROOT.iterdir() if p.is_dir() and p.name!='.git'],
    excluded_generated=['sim_stages','build_stages','__pycache__','.git','*.dmp','*.wlf','*.pyc'],
    note='All source, project, build scripts, reports, failed attempt evidence and available release media retained; temporary compiled simulator libraries and crash dumps omitted.'))
print(json.dumps(dict(passed=True,releases=deliveries,copied_files=len(records),external_dependencies=len(external)),indent=2))
