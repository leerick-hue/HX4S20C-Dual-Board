`timescale 1ns/1ps
// Full RTL/vendor clocks; deliberate audio/lock/packet-ack endpoint stimuli.
// No actual TF, SDRAM contents, photo or receiver acceptance is claimed.
module tb_acr_service_top;
 reg clk=0,rst_n=1;always #10 clk=~clk;
 wire hc,h0,h1,h2,scl,sck,mosi,ncs;tri1 sda;wire[7:0]seg;wire[5:0]sel;
 top dut(.clk(clk),.rst_n(rst_n),.key1(1'b1),.key2(1'b1),.key3(1'b1),
  .ir_in(1'b1),.link_rx(1'b1),.sd_miso(1'b1),.HDMI_CLK_P(hc),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2),
  .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda),.sd_dclk(sck),.sd_mosi(mosi),.sd_ncs(ncs),.seg_data(seg),.seg_sel(sel));
 initial begin force dut.sys_pll_m0.reset=1;#1000;release dut.sys_pll_m0.reset;end
 reg pv=0,av=0,ack=0,locked=0,armed=0;reg[23:0]l=0,r=0;reg[19:0]n=0,cts=0;
 reg[47:0]expected[0:127];integer wr=0,rd=0,checks=0,acrs=0;
 always @(posedge dut.video_clk)if(armed)begin
  if(dut.rst_all || dut.media_rst || dut.hdmi_rst)$fatal(1,"ACR service reset video/media");
  if(pv && locked)begin expected[wr]={l,r};wr=wr+1;end
  if(dut.u_hdmi_1_4b_transmitter_core_wrapper.I_audio_valid)begin
   if(rd==wr || {dut.u_hdmi_1_4b_transmitter_core_wrapper.I_audio_left_data,dut.u_hdmi_1_4b_transmitter_core_wrapper.I_audio_right_data}!==expected[rd])$fatal(1,"top PCM endpoint/order");
   rd=rd+1;
  end
  if(dut.u_hdmi_1_4b_transmitter_core_wrapper.I_acr_valid)begin
   if(!locked || dut.u_hdmi_1_4b_transmitter_core_wrapper.I_acr_n!==6144 || dut.u_hdmi_1_4b_transmitter_core_wrapper.I_acr_cts!==74250)$fatal(1,"top ACR endpoint");
   acrs=acrs+1;
  end
  checks=checks+1;
 end
 initial begin
  #20;rst_n=0;#3000;rst_n=1;
  wait(dut.video_pll_lock && dut.audio_pll_lock && dut.system_pll_lock);
  wait(dut.media_rst===0);repeat(12)@(negedge dut.video_clk);
  force dut.audio_valid=pv;force dut.audio_left_data=l;force dut.audio_right_data=r;
  force dut.acr_valid=av;force dut.acr_n=n;force dut.acr_cts=cts;
  force dut.hdmi_video_locked=locked;force dut.service_packet_seen=ack;armed=1;
  // Audio presented before video lock must not enter the core or queue.
  pv=1;av=1;n=6144;cts=74250;repeat(4)@(negedge dut.video_clk);pv=0;av=0;
  repeat(4)@(negedge dut.video_clk);
  if(wr || rd || dut.service_queued || dut.service_acr_valid)$fatal(1,"prelock data passed");
  locked=1;
  for(integer i=0;i<64;i=i+1)begin
   @(negedge dut.video_clk);pv=1;l=24'h123456^(i*17);r=24'hfedcba^(i*31);
   if(i%16==0)begin av=1;n=6144;cts=74250;end
   @(negedge dut.video_clk);pv=0;av=0;n=0;cts=0;
   if(i%16==0)begin
    repeat(40)@(negedge dut.video_clk);
    if(!dut.service_wait || dut.service_queued==0)$fatal(1,"top did not retain pending PCM");
    ack=1;@(negedge dut.video_clk);ack=0;
   end
   repeat(36)@(negedge dut.video_clk);
  end
  wait(rd==64);repeat(20)@(negedge dut.video_clk);
  if(wr!=64 || acrs!=4 || dut.service_overflow || dut.service_queued || checks<2000)$fatal(1,"top final accounting");
  repeat(12)@(negedge clk);
  if(dut.service_sync!==4'b1100 || dut.diagnostic_code[23:20]!==9)$fatal(1,"diagnostic flag CDC/prefix");
  if(dut.volume_level!=8 || dut.brightness!=4 || dut.contrast!=4 || dut.want_video!=0)$fatal(1,"normal control defaults lost");
  $display("PASS acr_service_top source64_core64_ACR4 no_media_video_reset checks=%0d prelock_gate_parameter_hold_ACK_wait_order_default_controls_diagnostic_CDC actual_vendor_clocks_forced_audio_and_ack_endpoints",checks);$finish;
 end
 initial begin #150000;$fatal(1,"service top timeout");end
endmodule
