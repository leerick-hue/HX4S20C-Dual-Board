"""Create an isolated SDRAM motion + known HDMI reference-tone experiment."""
from pathlib import Path
import hashlib, json, shutil, xml.etree.ElementTree as ET

R = Path('E:/HX4S20C_Test_20261026/video_restart_20261029')
B = Path('E:/HX4S20C_赛题一_基础逻辑源码_v0.1')
A = B / 'hdmi_audio_standalone_20261028'
M = B / 'hd_media_phase_20261028/src/user_source/hdl_source'
assert not R.exists(), R
R.mkdir()
records=[]
def copy(source, relative):
    dest=R/relative; dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,dest)
    records.append(dict(source=str(source),destination=relative,sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
for p in (A/'src').glob('*'):
    if p.is_file(): copy(p,'src/'+p.name)
copy(A/'project/HX4S20C_Extensions.al','project/HX4S20C_Extensions.al')
copy(A/'build.tcl','build.tcl')
for folder,names in {
    'SD':['frame_read_write.v','frame_fifo_write.v','frame_fifo_read.v','sdram.v','video_delay.v','video_timing_data.v'],
    'extensions':['reset_sync.v','frame_swap_fx_cdc.v','media_viewport.v','rgb565_unpack.v'],
    'IP':['sys_pll.v','afifo_32_16_256.v','afifo_32_16_256.tcl'],
    '':['pixel_write_fifo.v'],
}.items():
    for name in names: copy(M/folder/name,'src/'+name)
for name in ['global_def.v','sdr_as_ram.enc.v','sdr_wrrd.enc.v','sdr_init_ref.enc.v']:
    copy(M/'include'/name,'user_source/hdl_source/include/'+name)
copy(B/'hd_media_readalign_20261027/sim/sdram_retention_model.sv','sim/sdram_retention_model.sv')
# Keep just the frame-request module from the legacy raster source.
p=R/'src/video_timing_data.v'
p.write_text(p.read_text().split('module board_frame_request')[1].join(['module board_frame_request','']),encoding='utf8')
(R/'SOURCE_PROVENANCE.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
print(R)
