from pathlib import Path
import shutil,json,hashlib,xml.etree.ElementTree as ET,copy
P=Path(__file__).resolve().parents[1]
V=P/'video_step2_tf_retry_20261029'
U=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/ir_voice_video_20261029')
R=P/'integrated_ir_voice_video_20261029'
assert not (R/'PROVENANCE.json').exists();R.mkdir(exist_ok=True)
for n in ('src','project','user_source','vendor'):shutil.copytree(V/n,R/n,dirs_exist_ok=True)
for n in ('build.py','build.tcl','USER_CONFIRMED_BASELINES.json'):shutil.copy2(V/n,R/n)
shutil.copytree(U/'sim',R/'legacy_sim',dirs_exist_ok=True)
(R/'sim').mkdir(exist_ok=True);(R/'sim_logs').mkdir(exist_ok=True)
for n in ('sdram_retention_model.sv','hdmi_sequence_decoder.sv'):shutil.copy2(V/'sim'/n,R/'sim'/n)
shutil.copytree(V/'sim/fixtures',R/'sim/fixtures',dirs_exist_ok=True)
critical={'afifo_32_16_256.v','frame_fifo_read.v','frame_fifo_write.v','frame_read_write.v','frame_swap_fx_cdc.v',
 'hdmi_1_4b_transmitter_core_wrapper.enc.v','hdmi_phy_warpper.v','lane_lvds_10_1.v','reset_sync.v',
 'rgb565_pack.v','rgb565_unpack.v','pixel_write_fifo.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v',
 'spi_master.v','sdram.v','sys_pll.v','video_delay.v','video_rgb_to_axis_640x480.v','native_video_timing.v',
 'board_frame_request.v','mjpeg_video_player.v','jpeg_sector_stream.v','sd_sector_cdc.v','media_catalog.v'}
project=U/'src/td_project/HX4S20C_Extensions.al';tree=ET.ElementTree(ET.fromstring(project.read_text(encoding='utf8').replace('UsedInP&R','UsedInP&amp;R')))
files=[];provenance=[]
for e in tree.findall('./Source_Files/Verilog/File'):
 source=(project.parent/e.get('Path')).resolve();name=source.name
 if name in ('top_tf_hdmi_audio.v','video_pll.v','PLL_HDMI_AUDIO.v','audio_arc_calculate.v','startup_pulse.v'):continue
 if name in critical:source=V/'src'/name
 if name.startswith('jpeg_') and (V/'src/jpeg'/name).exists():source=V/'src/jpeg'/name
 target=R/'src'/name
 if name in ('global_def.v','sdr_as_ram.v','sdr_wrrd.enc.v'):
  source=V/'user_source/hdl_source/include'/name;target=R/'user_source/hdl_source/include'/name
 assert source.exists(),source
 if source!=target:shutil.copy2(source,target)
 files.append(target)
 provenance.append({'source':str(source),'target':str(target.relative_to(R)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
for name in ('video_hd_pll.v','diag_control.v','hdmi_reference_tone.v','media_viewport.v'):
 shutil.copy2(V/'src'/name,R/'src'/name);files.append(R/'src'/name)
shutil.copy2(U/'src/user_source/hdl_source/top_tf_hdmi_audio.v',R/'src/top.v');files.append(R/'src/top.v')
base=ET.parse(V/'project/HX4S20C_Extensions.al');ver=base.find('./Source_Files/Verilog');template=copy.deepcopy(ver[0]);ver.clear()
for i,f in enumerate(dict.fromkeys(files)):
 elem=copy.deepcopy(template);elem.set('Path','../'+f.relative_to(R).as_posix())
 for a in elem.findall('.//Attr'):
  if a.get('Name')=='CompileOrder':a.set('Val',str(i+1))
 ver.append(elem)
base.write(R/'project/HX4S20C_Extensions.al',encoding='utf8',xml_declaration=True)
shutil.copy2(U/'src/user_source/constraints_source/timing.sdc',R/'src/timing.sdc')
(R/'PROVENANCE.json').write_text(json.dumps({'video_baseline':str(V),'control_integration_reference':str(U),'imports':provenance},indent=2),encoding='utf8')
print(R)
