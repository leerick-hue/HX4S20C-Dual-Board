`timescale 1ns/1ps
// Physical demodulated NEC waveform -> unchanged receiver/bridge/CDC/controls.
module tb_phone_ir_media;
 reg video_clk=0,sd_clk=0;
 always #6.734007 video_clk=~video_clk;
 always #12.5 sd_clk=~sd_clk;
 reg video_rst_n=0,sd_rst_n=0,ir_in=1,album_ready=1,album_auto=0;
 reg vblank_start=0;
 wire legacy_ready,photo_next,photo_auto_valid,photo_auto_enable;
 wire control_valid,control_ready,seen;wire [7:0] control_id;
 wire [31:0] last_code,error_count,dropped_count;
 wire [3:0] brightness,contrast,volume_level;wire [2:0] edit_mode;
 wire bars_enable,music_play;
 ir_media_bridge #(.VIDEO_CLK_HZ(74250000)) bridge(.video_clk(video_clk),.video_rst_n(video_rst_n),
  .sd_clk(sd_clk),.sd_rst_n(sd_rst_n),.ir_in(ir_in),.video_mode(1'b0),.album_ready(album_ready),
  .auto_enabled(album_auto),.legacy_next(1'b0),.legacy_auto_valid(1'b0),
  .legacy_auto_enable(1'b0),.legacy_ready(legacy_ready),.photo_next(photo_next),
  .photo_auto_valid(photo_auto_valid),.photo_auto_enable(photo_auto_enable),
  .control_valid(control_valid),.control_ready(control_ready),.control_id(control_id),
  .last_code(last_code),.error_count(error_count),.dropped_count(dropped_count),.seen(seen));
 board_video_controls controls(.clk(video_clk),.rst_n(video_rst_n),
  .vblank_start(vblank_start),.key_n(3'b111),.command_valid(control_valid),
  .command_id(control_id),.command_ready(control_ready),.brightness(brightness),
  .contrast(contrast),.edit_mode(edit_mode),.volume_level(volume_level),
  .bars_enable(bars_enable),.music_play(music_play));
 integer next_count=0,auto_count=0,controls_count=0;
 always @(posedge video_clk) if(video_rst_n && control_valid && control_ready)
  controls_count=controls_count+1;
 always @(posedge sd_clk) if(sd_rst_n) begin
  if(photo_next) next_count=next_count+1;
  if(photo_auto_valid) begin auto_count=auto_count+1;album_auto<=photo_auto_enable;end
 end
 task send_nec(input [15:0] address,input [7:0] code);
  reg [31:0] bits;integer i;
  begin
   bits={~code,code,address};
   @(negedge video_clk);ir_in=0;#9000000;ir_in=1;#4500000;
   for(i=0;i<32;i=i+1) begin
    ir_in=0;#560000;ir_in=1;
    if(bits[i]) #1690000;else #560000;
   end
   ir_in=0;#560000;ir_in=1;#200000;
   if(last_code!=={address,8'h00,code}) $fatal(1,"NEC raw tuple mismatch %h",last_code);
  end
 endtask
 task commit_volume(input [3:0] expected);
  begin
   @(negedge video_clk);vblank_start=1;
   @(negedge video_clk);vblank_start=0;
   if(volume_level!==expected) $fatal(1,"volume expected%0d got%0d",expected,volume_level);
  end
 endtask
 integer n;
 initial begin
  repeat(10) @(negedge video_clk);video_rst_n=1;sd_rst_n=1;
  send_nec(16'hbf00,8'h43);
  if(volume_level!=8 || next_count!=0 || controls_count!=1) $fatal(1,"volume down accidentally next");
  commit_volume(7);
  send_nec(16'hbf00,8'h44);commit_volume(8);
  send_nec(16'hbf00,8'h0d);commit_volume(0);
  album_ready=0;send_nec(16'hbf00,8'h4a);
  if(next_count!=0 || legacy_ready) $fatal(1,"next ignored ready");
  album_ready=1;repeat(30) @(negedge sd_clk);
  if(next_count!=1) $fatal(1,"next did not cross clocks once");
  send_nec(16'hbf00,8'h0d);commit_volume(8);
  send_nec(16'hbf00,8'h4b);
  if(!album_auto || auto_count!=1) $fatal(1,"auto did not enable");
  #260000000;send_nec(16'hbf00,8'h4b);
  if(album_auto || auto_count!=2) $fatal(1,"auto did not disable");
  n=controls_count;send_nec(16'hbf00,8'h47);send_nec(16'hbe00,8'h43);
  if(controls_count!=n || next_count!=1 || auto_count!=2 || !seen || error_count || dropped_count)
   $fatal(1,"foreign/unmapped key acted or decode errors");
  $display("PASS phone physical NEC: BF00 wire address, five keys through production receiver/bridge/CDC/controls, volume 8->7->8, mute/restore, queued next, slideshow on/off, unknown/foreign rejection");
  $finish;
 end
 initial begin #2000000000;$fatal(1,"phone NEC watchdog");end
endmodule
