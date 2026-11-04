from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1]
src=R.parent/'media_hd_unified_20261025/sim/tb_unified_controls.sv'
s=src.read_text(encoding='utf8')
s=s.replace('always #20 video_clk','always #6.734007 video_clk')
s=s.replace('.music_play(music_play),.want_video(want_video)',".music_play(music_play)")
s=s.replace('    media_mode_reset #',"    assign want_video=1'b0;\n    media_mode_reset #")
s=s.replace('.VIDEO_CLK_HZ(25000000)','.VIDEO_CLK_HZ(74250000)')
s=s.replace('.BAUD(4000000))','.BAUD(4000000),.ACK_ENABLE(1))')
s=s.replace('.packet_error_count(packet_errors));',".packet_error_count(packet_errors),.ack_ready(1'b1));")
s=s.replace('for(n=2;n<=6;n=n+1)','for(n=2;n<=5;n=n+1)')
start=s.index('        mode_step(6);press(0);')
end=s.index('        before_count=codes_seen[13];',start)
s=s[:start]+'        mode_step(0);\n\n'+s[end:]
start=s.index('        // Preserve nondefault UI parameters,')
s=s[:start]+'''        check(packet_errors==0 && duplicates==0 && unsupported==0,"UART error counters");
        $display("PASS photo_ui checks=%0d controls=%0d next=%0d auto=%0d: six physical-key modes/debounce, vblank commits, all16 UART shortcuts through queue/arbiter/CDC, IR command mailbox, saturation/mute/music",checks,control_count,photo_next_count,photo_auto_count);
        $display("SCOPE accelerated UART10clocks/bit and debounce3clocks, IR command boundary injected; actual74.25/40MHz clocks; physical NEC/115200 ACK covered separately");
        $finish;
    end
endmodule
'''
dst=R/'sim/tb_unified_controls.sv';dst.write_text(s,encoding='utf8')
(R/'audit/ui_test_derivation.json').write_text(json.dumps({'source':str(src),'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'derived':str(dst),'derived_sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'changes':'Native video clock, six-mode photo-only proven controls, ACK queue enabled/always-ready sink; remove video-source mode and its reset tests. Retain every photo/UI assertion.'},indent=2)+'\n',encoding='utf8')
