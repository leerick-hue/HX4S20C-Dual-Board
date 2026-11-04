`timescale 1ns/1ps
module tb_motion_top;
 parameter integer SMOKE=0;
 reg clk=0,rst_n=1,key1=1,key2=1,key3=1;
 always #10 clk=~clk;
 wire hc,h0,h1,h2,scl,ncs,sck,mosi;wire[5:0]sel;wire[7:0]seg;tri1 sda;
 top dut(.clk(clk),.rst_n(rst_n),.key1(key1),.key2(key2),.key3(key3),
  .ir_in(1'b1),.link_rx(1'b1),.sd_miso(1'b1),.seg_sel(sel),.seg_data(seg),
  .HDMI_CLK_P(hc),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2),
  .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda),.sd_ncs(ncs),.sd_dclk(sck),.sd_mosi(mosi));
 defparam dut.control.EDID_DELAY_CYCLES=7425;
 wire integer inputs,samples,aps,acrs,aifs,avis,clears,lastn,lastcts,queued,gcps,sets;wire avmuted;
 hdmi_sequence_decoder #(.CTS_MIN(74250),.CTS_MAX(74250)) sink(.clk(dut.pixel_clk),.rst(dut.pixel_rst),
  .c0(dut.ch0),.c1(dut.ch1),.c2(dut.ch2),.audio_in_valid(dut.hdmi.I_audio_valid),
  .audio_in_left(dut.tone_left),.audio_in_right(dut.tone_right),
  .inputs(inputs),.samples(samples),.audio_packets(aps),.acr_packets(acrs),
  .aif_packets(aifs),.avi_packets(avis),.avmute_clears(clears),.last_n(lastn),.last_cts(lastcts),
  .queued(queued),.gcp_packets(gcps),.avmute_sets(sets),.avmuted(avmuted));
 integer frames=0,x=0,y=0,pixels=0,pcm_count=0,acr_inputs=0;
 reg [23:0]prior_rgb=0;reg prior_de=0,seen_sof=0;reg[23:0]expected_tone;
 always @(posedge dut.pixel_clk)begin
  if(dut.pixel_rst)begin frames=0;x=0;y=0;pixels=0;prior_de=0;prior_rgb=0;pcm_count=0;acr_inputs=0;seen_sof=0;end
  else begin
   if(dut.axis_valid!==prior_de || (prior_de&&dut.axis_data!==prior_rgb))$fatal(1,"AXIS pixel pipeline mismatch");
   prior_de=dut.bypass?dut.de:dut.mde;
   prior_rgb=dut.bypass?dut.rgb:dut.memory_rgb;
   if(dut.axis_valid)begin
    if(dut.axis_user)begin
     if(x!=0||y!=0)$fatal(1,"misplaced SOF");seen_sof=1;
    end
    if(!seen_sof||dut.axis_last!==(x==1279)||(^dut.axis_data===1'bx))$fatal(1,"invalid AXIS geometry/data");
    pixels=pixels+1;
    if(x==1279)begin
     x=0;y=y+1;
     if(y==720)begin
      frames=frames+1;y=0;
      $display("TOP_FRAME n=%0d stored_id=%0d core_locked=%0b samples=%0d ACR=%0d",frames,dut.display_id,dut.core_video_locked,samples,acrs);
     end
    end else x=x+1;
   end
   if(dut.hdmi.I_audio_valid)begin
    if(!dut.core_video_locked||dut.muted)$fatal(1,"audio gate");
    expected_tone=pcm_count%48<24?24'h100000:24'hf00000;
    if(dut.tone_left!==expected_tone||dut.tone_right!==expected_tone)$fatal(1,"PCM content");
    pcm_count=pcm_count+1;
   end
   if(dut.hdmi.I_acr_valid)begin
    if(!dut.hdmi.I_audio_valid||pcm_count%48!=0||dut.tone_n!=6144||dut.tone_cts!=74250)$fatal(1,"ACR cadence");
    acr_inputs=acr_inputs+1;
   end
   if(dut.underruns!=0)$fatal(1,"memory underflow");
   if(dut.player_error!=0||dut.bridge_overflow)$fatal(1,"TF/JPEG error");
  end
 end
 integer saved_frames,saved_samples,saved_acrs,saved_id;
 initial begin
  #100;rst_n=0;#3000;rst_n=1;
  wait(dut.pixel_rst===0);
  if(SMOKE)begin
   repeat(16)@(negedge dut.pixel_clk);force dut.core_video_locked=1;
   wait(pcm_count>=3);release dut.core_video_locked;
  end else begin
   wait(frames>=3 && dut.display_valid && samples>=256 && acrs>=4 && clears>=1 && aifs>=1 && avis>=1);
   if(avmuted||lastn!=6144||lastcts!=74250)$fatal(1,"HDMI metadata");
  end
  saved_frames=frames;saved_samples=samples;saved_acrs=acrs;saved_id=dut.display_id;
  // Runtime keys must not change boot-only diagnostic selection.
  key1=0;key2=0;key3=0;repeat(20)@(negedge clk);
  if(dut.bypass||dut.freeze||dut.muted)$fatal(1,"runtime key changed boot mode");
  rst_n=0;#3000;rst_n=1;wait(dut.pixel_rst===0);repeat(16)@(negedge dut.pixel_clk);
  force dut.core_video_locked=1;
  repeat(512)begin
   @(negedge dut.pixel_clk);
   if(!dut.bypass||!dut.freeze||!dut.muted||dut.hdmi.I_audio_valid||dut.hdmi.I_acr_valid)$fatal(1,"boot mode/mute");
  end
  repeat(8)@(negedge clk);
  if(dut.display_code[23:20]!==4'hb||!dut.display_code[16])$fatal(1,"diagnostic display");
  release dut.core_video_locked;
  if(SMOKE)$display("PASS motion_top_smoke actual_vendor_PLL_PHY core_lock_forced PCM3 modes512 no_full_frame_claim");
  else $display("PASS motion_top natural_lock=1 frames=%0d JPEG_memory_id=%0d PCM_decoded=%0d ACR_decoded=%0d BCH_checksum_checked=1 boot_modes512=1 synthetic_card=1",saved_frames,saved_id,saved_samples,saved_acrs);
  $finish;
 end
 initial begin #160000000;$fatal(1,"top timeout frames=%0d id=%0d lock=%b samples=%0d ACR=%0d",frames,dut.display_id,dut.core_video_locked,samples,acrs);end
endmodule
