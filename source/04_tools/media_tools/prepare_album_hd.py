"""Create an isolated still-photo candidate; never modifies existing releases."""
from pathlib import Path
import shutil, json, hashlib, re

BASE=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board')
SRC=BASE/'hd_video_20261023'
DST=BASE/'album_hd_prefetch_20261029'
LINK=BASE/'linkdiag_20261026'
FIX=Path('E:/HX4S20C_赛题一_基础逻辑源码_v0.1/hd_media_phase_20261028')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def edit(p,old,new):
    t=p.read_text(encoding='utf-8'); assert old in t,(p,old);p.write_text(t.replace(old,new),encoding='utf-8')
def main():
    assert not DST.exists(), 'Candidate already exists; refusing to overwrite'
    DST.mkdir()
    for folder in ['src','sim_source','tools']:
        shutil.copytree(SRC/folder,DST/folder,ignore=shutil.ignore_patterns('*.db','*.bit','*.log','*.rpt','*.area','*.timing','*.ts','__pycache__'))
    for name in ['build.tcl','run_sim.py']:
        shutil.copy2(SRC/name,DST/name)
    H=DST/'src/user_source/hdl_source'
    records=[]
    # Reuse the reliable protocol without bringing any video-file decoder.
    for rel in ['extensions/board_remote_control.v','extensions/event_packet_rx.v','extensions/event_packet_tx.v','extensions/uart_tx.v','SD/sd_card_cmd.v','SD/sd_card_sec_read_write.v']:
        p=LINK/'src/user_source/hdl_source'/rel
        shutil.copy2(p,H/rel);records.append({'from':str(p),'to':rel,'sha256':sha(p)})
    for rel in ['SD/frame_fifo_read.v','SD/frame_read_write.v','include/global_def.v','extensions/video_hd_pll.v']:
        p=FIX/'src/user_source/hdl_source'/rel
        shutil.copy2(p,H/rel);records.append({'from':str(p),'to':rel,'sha256':sha(p)})
    # Preserve the still-only three-output PLL interface, with the fixed PHY budget.
    edit(H/'IP/sys_pll.v','.CLKC1_DIV(8)','.CLKC1_DIV(20)')
    edit(H/'IP/sys_pll.v','.CLKC1_CPHASE(7)','.CLKC1_CPHASE(19)')
    edit(H/'IP/sys_pll.v','.CLKC2_DIV(8)','.CLKC2_DIV(20)')
    edit(H/'IP/sys_pll.v','.CLKC2_CPHASE(3)','.CLKC2_CPHASE(7)')
    edit(H/'IP/sys_pll.v','.CLKC2_FPHASE(0)','.CLKC2_FPHASE(4)')
    edit(H/'IP/sys_pll.v','125.000000MHZ','50.000000MHZ')
    edit(H/'IP/sys_pll.v','180.0000 DEG','144.0000 DEG')
    top=H/'top_tf_hdmi_audio.v'
    edit(top,'input                       link_rx,','output                      link_ack_tx,\n    input                       link_rx,')
    edit(top,'.fade_enable(1\'b1)', '.fade_enable(1\'b0)')
    edit(top,'board_remote_control remote(', 'wire ack_valid,ack_ready,ack_byte_valid,ack_byte_ready;wire[31:0]ack_data;wire[7:0]ack_sequence,ack_byte;\nboard_remote_control #(.ACK_ENABLE(1)) remote(')
    edit(top,'.unsupported_count(remote_unsupported),.packet_error_count(remote_errors));', '''.unsupported_count(remote_unsupported),.packet_error_count(remote_errors),
    .received_byte_count(),.valid_packet_count(),
    .ack_valid(ack_valid),.ack_ready(ack_ready),.ack_data(ack_data),.ack_sequence(ack_sequence));
event_packet_tx #(.USE_EVENT_SEQUENCE(1)) acknowledgements(.clk(sd_card_clk),.rst_n(!rst_all),
    .event_valid(ack_valid),.event_ready(ack_ready),.event_data(ack_data),.event_sequence(ack_sequence),
    .byte_valid(ack_byte_valid),.byte_ready(ack_byte_ready),.byte_data(ack_byte));
uart_tx #(.CLK_HZ(100000000),.BAUD(115200)) acknowledgement_wire(.clk(sd_card_clk),.rst_n(!rst_all),
    .byte_valid(ack_byte_valid),.byte_ready(ack_byte_ready),.byte_data(ack_byte),.tx(link_ack_tx),.busy());''')
    # Add only the two small ACK modules to the existing XML source manifest.
    project=DST/'src/td_project/HX4S20C_Extensions.al'
    t=project.read_text(encoding='utf-8')
    tags=''.join(f'<File Path="../user_source/hdl_source/extensions/{n}.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/></FileInfo></File>' for n in ['event_packet_tx','uart_tx'])
    t=t.replace('</Verilog>',tags+'</Verilog>')
    t=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*',lambda m:m[1]+project.parent.as_posix(),t,count=1)
    project.write_text(t,encoding='utf-8')
    pin=DST/'src/user_source/constraints_source/pin.adc'
    lp=(LINK/'src/user_source/constraints_source/pin.adc').read_text(encoding='utf-8')
    ack_lines='\n'.join(x for x in lp.splitlines() if 'link_ack_tx' in x)
    assert ack_lines
    pin.write_text(pin.read_text(encoding='utf-8')+'\n'+ack_lines+'\n',encoding='utf-8')
    # ADC assignments are copied exactly; no blanket timing exemptions.
    sdc=DST/'src/user_source/constraints_source/timing.sdc'
    sdc.write_text(sdc.read_text(encoding='utf-8')+'''
# First synchronizer stages only; 50MHz SDRAM data paths remain fully checked.
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_write_m0/write_req_d0}]
set_false_path -to [get_regs {sd_card_bmp_m0/wrfin_tgl_sync[0] sd_card_bmp_m0/bmp_read_m0/ack_sync[0]}]
''',encoding='utf-8')
    # Allow the fitter to merge small carry chains; retain explicit seed.
    build=DST/'build.tcl'
    edit(build,'optimize_gate','set_param synthesis carry_chain_min_length 5\noptimize_gate')
    edit(build,'place\n','set_param place seed 11\nplace\n')
    (DST/'provenance.json').write_text(json.dumps({'base':str(SRC),'imports':records,'scope':'still-photo only, no MJPEG/HXJV decoder; original releases preserved'},indent=2),encoding='utf-8')
    print(DST)
if __name__=='__main__':main()
