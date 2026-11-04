from pathlib import Path
import shutil
R=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/album_hd_prefetch_20261029')
O=Path('E:/HX4S20C_赛题一_基础逻辑源码_v0.1/hd_media_20261025')
(R/'sim').mkdir(exist_ok=True)
for n in ['run_memory_flow.py','sdram_scan_model.sv','tb_hd_memory_flow.sv']:shutil.copy2(O/'sim'/n,R/'sim'/n)
p=R/'sim/tb_hd_memory_flow.sv';t=p.read_text()
t=t.replace('parameter TEST_FRAMES=1;', 'parameter TEST_FRAMES=3;\n parameter HD1080=0;')
t=t.replace('wire[20:0] length=video_mode?153600:460800;', 'localparam FRAME_WORDS=HD1080?1036800:460800;\n wire[20:0] length=FRAME_WORDS;')
t=t.replace('h>=260 && h<1540 && v>=25 && v<745', 'h>=(HD1080?192:260) && h<(HD1080?2112:1540) && v>=(HD1080?41:25) && v<(HD1080?1121:745)')
t=t.replace('wire window=active && (!video_mode || (h>=580 && h<1220 && v>=145 && v<625));', 'wire window=active;')
t=t.replace('h==1649','h==(HD1080?2199:1649)').replace('v==749','v==(HD1080?1124:749)')
t=t.replace('.FRAME_WIDTH(640),.FRAME_HEIGHT(720)', '.FRAME_WIDTH(HD1080?960:640),.FRAME_HEIGHT(HD1080?1080:720)')
t=t.replace('.mem_clk(mclk),.rst(rst)', '.read_capture_delay(1\'b1),.mem_clk(mclk),.rst(rst)')
t=t.replace("21'd460800", '21\'(FRAME_WORDS)').replace('460800+write_words','FRAME_WORDS+write_words')
t=t.replace('sdram_scan_model model(', 'sdram_scan_model #(.WRITE_BASE(FRAME_WORDS)) model(')
t=t.replace('one_mode(0);one_mode(1);','one_mode(0);')
p.write_text(t)
p=R/'sim/run_memory_flow.py';t=p.read_text()
t=t.replace("ap.add_argument('--mem-mhz'", "ap.add_argument('--hd1080',action='store_true')\nap.add_argument('--mem-mhz'")
t=t.replace("f'-gPHY_CHECK={int(a.phy_check)}'", "f'-gPHY_CHECK={int(a.phy_check)}',f'-gHD1080={int(a.hd1080)}'")
t=t.replace("'mem_mhz':a.mem_mhz", "'hd1080':a.hd1080,'mem_mhz':a.mem_mhz")
p.write_text(t)
# ACK compatibility regression uses the new board-one receiver and unchanged
# delivered board-two reliable transport; recognizer training is not simulated here.
L=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/linkdiag_20261026')
B=Path('E:/HX4S20C_Board2/work/link_ack_20261026')
for n in ['event_packet_tx','uart_tx']:
 shutil.copy2(R/f'src/user_source/hdl_source/extensions/{n}.v',R/f'sim_source/rtl/{n}.v')
for n in ['reliable_event_link','event_arbiter','voice_status_leds']:
 shutil.copy2(B/f'rtl/{n}.v',R/f'sim_source/rtl/{n}.v')
for n in ['tb_link_ack','tb_link_pair','tb_sd_token_retry']:
 shutil.copy2(L/f'sim/{n}.sv',R/f'sim_source/sim/{n}.sv')
print('Prepared production memory/ACK regression')
