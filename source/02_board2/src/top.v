// 640x480 TF JPEG video, SDRAM frame buffers, HDMI and voice-control integration.
// HDMI audio service starts after core video lock.
module top(
 input clk,rst_n,key1,key2,key3,sd_miso,
 input mic_sd,link_ack_rx,input [3:0] keypad_col_n,
 output mic_sck,mic_ws,link_tx,debug_tx,
 output [3:0] led_n,keypad_row_n,
 output [5:0] seg_sel, output [7:0] seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 output HDMI_DDC_SCL, inout HDMI_DDC_SDA,
 output sd_ncs,sd_dclk,sd_mosi
);
 localparam VGA_MODE = 0; // Build helper changes only this mode selection.
 localparam W=VGA_MODE?640:1280, H=VGA_MODE?480:720;
 localparam HT=VGA_MODE?800:1650, VT=VGA_MODE?525:750;
 localparam HS=VGA_MODE?96:40, HF=VGA_MODE?16:110, HB=VGA_MODE?48:220;
 localparam VS=VGA_MODE?2:5, VF=VGA_MODE?10:5, VB=VGA_MODE?33:20;
 wire pixel_clk,serial_clk,pll_locked,pixel_rst,edid_trigger,edid_valid;
 wire [23:0] status_code;
 wire [7:0] edid_data;
 wire core_video_locked,axis_ready;
 wire muted,tone_valid,tone_acr_valid;
 wire[23:0]tone_left,tone_right;wire[19:0]tone_n,tone_cts;
 // This candidate plays silent video. KEY2/3/4 belong exclusively to
 // template enrollment; no boot-time video diagnostics consume those keys.
 wire tone_enable=1'b0;
 assign muted=1'b1;
 assign tone_valid=1'b0,tone_acr_valid=1'b0;
 assign tone_left=24'd0,tone_right=24'd0;
 assign tone_n=20'd6144,tone_cts=20'd74250;
 // pin.adc maps key1=B2(KEY2), key3=B1(KEY3), key2=C1(KEY4).
 board2_voice_top voice(.clk(clk),.rst_n(rst_n),.key_n({key2,key3,key1}),
   .mic_sd(mic_sd),.mic_sck(mic_sck),.mic_ws(mic_ws),
   .keypad_row_n(keypad_row_n),.keypad_col_n(keypad_col_n),
   .link_tx(link_tx),.link_ack_rx(link_ack_rx),.debug_tx(debug_tx),.led_n(led_n));
 reg pcm_seen,acr_seen;
 always @(posedge pixel_clk or posedge pixel_rst)
   if(pixel_rst)begin pcm_seen<=0;acr_seen<=0;end
   else begin if(tone_valid)pcm_seen<=1;if(tone_acr_valid)acr_seen<=1;end
 (* ASYNC_REG="TRUE" *)reg[3:0]audio_meta,audio_sync;
 always @(posedge clk or negedge rst_n)
   if(!rst_n)begin audio_meta<=0;audio_sync<=0;end
   else begin audio_meta<={acr_seen,pcm_seen,tone_enable,muted};audio_sync<=audio_meta;end
 wire [9:0] ch0,ch1,ch2,chclk;
 generate if(VGA_MODE) begin: vga
   diag_vga_pll pll(.refclk(clk),.reset(!rst_n),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(pll_locked));
 end else begin: hd
   video_hd_pll pll(.refclk(clk),.reset(!rst_n),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(pll_locked));
 end endgenerate
 diag_control #(.EDID_DELAY_CYCLES(VGA_MODE?2500000:7425000)) control(
   .ref_clk(clk),.pixel_clk(pixel_clk),.rst_n(rst_n),.pll_locked(pll_locked && mem_locked),
   .edid_valid(edid_valid),.pixel_rst(pixel_rst),.edid_trigger(edid_trigger),.display_code(status_code));
 wire hs,vs,de;reg[10:0]bar_x;
 wire mem_clk,mem_clk_shift,mem_locked,mem_rst_n,sd_clk,decode_clk,sd_rst_n,decode_rst_n;
 sys_pll memory_pll(.refclk(clk),.reset(!rst_n),.clk0_out(sd_clk),.clk1_out(mem_clk),
   .clk2_out(mem_clk_shift),.clk3_out(decode_clk),.locked(mem_locked));
 reset_sync memory_reset(.clk(mem_clk),.arst_n(rst_n && mem_locked && pll_locked),.rst_n(mem_rst_n));
 reset_sync sd_reset(.clk(sd_clk),.arst_n(rst_n&&mem_locked&&pll_locked),.rst_n(sd_rst_n));
 reset_sync decode_reset(.clk(decode_clk),.arst_n(rst_n&&mem_locked&&pll_locked),.rst_n(decode_rst_n));
 wire card_ready,card_req,card_valid,card_end;wire[31:0]card_addr;wire[7:0]card_data;
 sd_card_top card(.clk(sd_clk),.rst(!sd_rst_n),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),
  .SD_MOSI(sd_mosi),.SD_MISO(sd_miso),.sd_init_done(card_ready),
  .sd_sec_read(card_req),.sd_sec_read_addr(card_addr),.sd_sec_read_data(card_data),
  .sd_sec_read_data_valid(card_valid),.sd_sec_read_end(card_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
  .sd_sec_write_data_req(),.sd_sec_write_end());
 wire[3:0]player_state,player_error;wire bridge_overflow;
 wire[31:0]dropped_frames,committed_frames;
 wire bypass,freeze;
 assign bypass=1'b0,freeze=1'b0;
 wire mhs,mvs,mde,mem_init,display_valid;
 wire [23:0]memory_rgb;wire [15:0]display_id;wire [31:0]underruns;
 video_path motion(.mem_clk(mem_clk),.mem_clk_shift(mem_clk_shift),.mem_rst(!mem_rst_n),
   .pixel_clk(pixel_clk),.pixel_rst(pixel_rst),.hs_native(hs),.vs_native(vs),.de_native(de),
   .decode_clk(decode_clk),.decode_rst(!decode_rst_n),.sd_clk(sd_clk),.sd_rst(!sd_rst_n),
   .sd_ready(card_ready),.sd_req(card_req),.sd_addr(card_addr),.sd_data(card_data),.sd_valid(card_valid),.sd_end(card_end),
   .player_state(player_state),.player_error(player_error),.bridge_overflow(bridge_overflow),
   .dropped_frames(dropped_frames),.committed_frames(committed_frames),
   .freeze(freeze),.hs(mhs),.vs(mvs),.de(mde),.rgb(memory_rgb),.init_done(mem_init),
   .display_valid(display_valid),.display_id(display_id),.underruns(underruns));
 wire axis_user,axis_valid,axis_last;wire[23:0]axis_data;
 always @(posedge pixel_clk or posedge pixel_rst)
   if(pixel_rst)bar_x<=0;else if(!de)bar_x<=0;else bar_x<=bar_x+1'b1;
 wire[23:0]rgb=bar_x<160?24'hffffff:bar_x<320?24'hffff00:bar_x<480?24'h00ffff:
   bar_x<640?24'h00ff00:bar_x<800?24'hff00ff:bar_x<960?24'hff0000:bar_x<1120?24'h0000ff:24'h202020;
 native_video_timing #(.WIDTH(W),.HEIGHT(H),.HSA(HS),.HBP(HB),.HFP(HF),
   .VSA(VS),.VBP(VB),.VFP(VF),.HS_POLARITY(1),.VS_POLARITY(1)) timing(
   .clk(pixel_clk),.rst(pixel_rst),.hs(hs),.vs(vs),.de(de));
 video_rgb_to_axis_640x480 #(.WIDTH(W)) adapter(.I_clk(pixel_clk),.I_rst(pixel_rst),
   .I_vs(bypass?vs:mvs),.I_de(bypass?de:mde),.I_rgb(bypass?rgb:memory_rgb),.O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_data));
 (* ASYNC_REG="TRUE" *)reg[1:0]lock_sync;
 always @(posedge clk or negedge rst_n)
   if(!rst_n)lock_sync<=0;else lock_sync<={lock_sync[0],core_video_locked};
 // Human-readable counters are sampled for diagnosis, not used in control.
 (* ASYNC_REG="TRUE" *)reg [21:0] diag_meta,diag_sync;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin diag_meta<=0;diag_sync<=0;end
  else begin
   diag_meta<={bypass,freeze,mem_init,core_video_locked,(|underruns),muted,display_id};
   diag_sync<=diag_meta;
  end
 (* ASYNC_REG="TRUE" *)reg[8:0]err_meta,err_sync;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin err_meta<=0;err_sync<=0;end
  else begin err_meta<={bridge_overflow,player_error,player_state};err_sync<=err_meta;end
 wire[23:0]display_code=(|err_sync[8:4])?{4'he,err_sync[8]?4'hb:err_sync[7:4],err_sync[3:0],diag_sync[11:0]}:
   {diag_sync[21]?4'hb:(diag_sync[20]?4'hf:4'hc),diag_sync[19:0]};
 wire [6:0] s0,s1,s2,s3,s4,s5;
 seg_decoder d0(.bin_data(display_code[23:20]),.seg_data(s0));
 seg_decoder d1(.bin_data(display_code[19:16]),.seg_data(s1));
 seg_decoder d2(.bin_data(display_code[15:12]),.seg_data(s2));
 seg_decoder d3(.bin_data(display_code[11:8]),.seg_data(s3));
 seg_decoder d4(.bin_data(display_code[7:4]),.seg_data(s4));
 seg_decoder d5(.bin_data(display_code[3:0]),.seg_data(s5));
 seg_scan scan(.clk(clk),.rst_n(rst_n),.seg_sel(seg_sel),.seg_data(seg_data),
   .seg_data_0({1'b1,s0}),.seg_data_1({1'b1,s1}),.seg_data_2({1'b1,s2}),
   .seg_data_3({1'b1,s3}),.seg_data_4({1'b1,s4}),.seg_data_5({1'b1,s5}));
 hdmi_1_4b_transmitter_core_wrapper #(
   .DEVICE("EG"),.HTOTAL(HT),.HSA(HS),.HFP(HF),.HBP(HB),.HACTIVE(W),
   .VTOTAL(VT),.VSA(VS),.VFP(VF),.VBP(VB),.VACTIVE(H),
   .VIDEO_VIC(VGA_MODE?1:4),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
   .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(VGA_MODE?125:372)
 ) hdmi(
   .I_pixel_clk(pixel_clk),.I_rst(pixel_rst),.I_edid_read_trig(edid_trigger),
   .O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
   .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),
   .O_axis_s_ready(axis_ready),.I_audio_valid(tone_valid && tone_enable),.I_audio_left_data(tone_left),.I_audio_right_data(tone_right),
   .I_acr_valid(tone_acr_valid && tone_enable),.I_acr_cts(tone_cts),.I_acr_n(tone_n),.O_video_locked(core_video_locked),
   .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
   .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
 hdmi_phy_wrapper phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(pixel_rst),
   .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(chclk),
   .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));

endmodule
