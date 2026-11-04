from pathlib import Path
import json,hashlib,shutil
R=Path(__file__).resolve().parents[1];P=R.parent
records=[]
def derive(src,dst,replacements):
    s=src.read_text(encoding='utf8')
    for a,b in replacements:
        assert a in s,(str(src),a)
        s=s.replace(a,b)
    dst.write_text(s,encoding='utf8')
    records.append({'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'derived':str(dst),'derived_sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'replacements':replacements})
derive(P/'phone_ir_link_ack_20261030/sim/tb_phone_keymap.sv',R/'sim/tb_phone_keymap.sv',[
 ('always #20 clk','always #6.734007 clk'),('ir_keymap dut','ir_keymap #(.CLK_HZ(74250000)) dut'),
 ('#(.PHONE_ENABLE(0))','#(.CLK_HZ(74250000),.PHONE_ENABLE(0))')])
derive(P/'phone_ir_link_ack_20261030/sim/tb_phone_ir_media.sv',R/'sim/tb_phone_ir_media.sv',[
 ('always #20 video_clk','always #6.734007 video_clk'),('always #5 sd_clk','always #12.5 sd_clk'),
 ('ir_media_bridge bridge','ir_media_bridge #(.VIDEO_CLK_HZ(74250000)) bridge'),
 ('.ir_in(ir_in),.album_ready',".ir_in(ir_in),.video_mode(1'b0),.album_ready")])
derive(P/'linkdiag_20261026/sim/tb_link_ack.sv',R/'sim/tb_link_ack.sv',[
 ('always #5 rclk','always #12.5 rclk'),('#(.ACK_ENABLE(1))','#(.CLK_HZ(40000000),.ACK_ENABLE(1))'),
 ('#(.CLK_HZ(100000000))','#(.CLK_HZ(40000000))'),('actual50/100MHz','actual50/40MHz')])
derive(P/'album_hd_prefetch_20261029/sim_source/sim/tb_scale_1920x1080.sv',R/'sim/tb_scale.sv',[
 ('W=1920,H=1080,FIT=0','W=1280,H=720,FIT=1'),
 ('        $display("PASS 1920x1080 destination: exact 21-bit address coverage and mapped pixels");',
 '''        build(3,7,0,54,40,0);run_file(payload_end,0,1,1);
        build(7,2,1,54,40,0);run_file(payload_end,0,1,1);
        build(1280,720,0,54,40,0);run_file(payload_end,0,1,1);
        $display("PASS native1280x720 fit: five complete frames, exact unique address coverage, RGB and black borders, portrait/wide/top-down/bottom-up/native input, random stalls");''')])
base=Path(json.loads((R/'BASELINE.json').read_text())['source'])
shutil.copy2(base/'sim/run_top.py',R/'sim/run_top.py')
shutil.copy2(base/'sim/tb_acr_service_top.sv',R/'sim/tb_acr_service_top.sv')
(R/'test_derivation.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf8')
print('Prepared native clock/size regressions and unchanged full-top audio integration.')
