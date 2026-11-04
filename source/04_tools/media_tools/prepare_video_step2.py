from pathlib import Path
import shutil,json,hashlib,xml.etree.ElementTree as ET
P=Path(__file__).resolve().parents[1];R=P/'video_step2_tf_20261029';S=P/'video_restart_20261029'
B=Path('E:/HX4S20C_赛题一_基础逻辑源码_v0.1/hd_media_phase_20261028');H=B/'src/user_source/hdl_source'
assert not (R/'SOURCE_PROVENANCE.json').exists()
for directory in ('src','project','user_source'):
 shutil.copytree(S/directory,R/directory,dirs_exist_ok=True)
for name in ('build.py','build.tcl','USER_CONFIRMED_BASELINES.json'):
 shutil.copy2(S/name,R/name)
records=[]
def cp(source,dest):
 target=R/dest;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
 records.append(dict(source=str(source),destination=dest,sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
for name in ('mjpeg_video_player.v','jpeg_sector_stream.v','sd_sector_cdc.v','media_catalog.v'):cp(B/'rtl'/name,'src/'+name)
for name in ('sd_card_top.v','sd_card_sec_read_write.v','spi_master.v'):cp(H/'SD'/name,'src/'+name)
cp(Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/linkdiag_20261026/src/user_source/hdl_source/SD/sd_card_cmd.v'),'src/sd_card_cmd.v')
cp(H/'extensions/rgb565_pack.v','src/rgb565_pack.v')
for p in (H/'jpeg').glob('*.v'):cp(p,'src/jpeg/'+p.name)
for n in ('sdram_retention_model.sv','hdmi_sequence_decoder.sv','phy_omitted.v'):
 cp(S/'sim'/n,'sim/'+n)
F=Path('E:/HX4S20C_赛题一_基础逻辑源码_v0.1/hd_media_20261025/sim/fixtures')
for n in ('fps30.hex','combined.img','video0.hex','video1.hex','video2.hex','manifest.json'):cp(F/n,'sim/fixtures/'+n)
(R/'SOURCE_PROVENANCE.json').write_text(json.dumps(dict(step1_bit_sha256=json.loads((S/'DELIVERY.json').read_text(encoding='utf8'))['sha256'],added_sources=records),ensure_ascii=False,indent=2),encoding='utf8')
print(R)
