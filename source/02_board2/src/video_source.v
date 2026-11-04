`timescale 1ns/1ps
// TF catalogue -> indexed JPEG decoder -> RGB565 words.
// Video decoding and HDMI audio service use independent paths.
module video_source(
 input decode_clk,decode_rst,sd_clk,sd_rst,mem_clk,mem_rst,mem_init,sd_ready,freeze,
 output sd_req,output [31:0]sd_addr,input[7:0]sd_data,input sd_valid,sd_end,
 output write_req,input write_ack,write_finish,
 output word_valid,input word_ready,output [20:0]word_addr,output [31:0]word_data,
 output write_bank,output [15:0]frame_id,output swap_valid,input swap_ready,swap_done,
 output swap_bank,output [3:0]state_code,error_code,output bridge_overflow,
 output [31:0]dropped_frames,output [31:0]committed_frames,
 output aspect_16x9,output [20:0] frame_words
);
 (* ASYNC_REG="TRUE" *)reg [1:0] ready_sync,freeze_sync;
 reg finish_toggle;
 always @(posedge mem_clk or posedge mem_rst)
  if(mem_rst)finish_toggle<=0;else if(write_finish)finish_toggle<=!finish_toggle;
 always @(posedge decode_clk or posedge decode_rst)
  if(decode_rst)begin ready_sync<=0;freeze_sync<=0;end
  else begin ready_sync<={ready_sync[0],sd_ready&&mem_init};freeze_sync<={freeze_sync[0],freeze};end
 reg client_req;reg [31:0]client_addr;
 wire client_valid,client_end;wire [7:0]client_data;
 sd_sector_cdc sectors(.client_clk(decode_clk),.sd_clk(sd_clk),.rst(sd_rst||decode_rst),
  .client_req(client_req),.client_addr(client_addr),.client_data(client_data),
  .client_valid(client_valid),.client_end(client_end),.sd_req(sd_req),.sd_addr(sd_addr),
  .sd_data(sd_data),.sd_valid(sd_valid),.sd_end(sd_end),.overflow(bridge_overflow));
 wire cat_req,cat_ready,video_present;wire[31:0]cat_addr,video_base;wire[3:0]cat_error;
 media_catalog catalog(.clk(decode_clk),.rst(decode_rst),.sd_ready(ready_sync[1]),.want_video(1'b1),
  .sec_req(cat_req),.sec_addr(cat_addr),.sec_data(client_data),
  .sec_valid(client_valid&&!cat_ready),.sec_end(client_end&&!cat_ready),
  .ready(cat_ready),.active_video(),.video_present(video_present),.photo_present(),
  .video_base(video_base),.photo_start(),.photo_max(),.photo_count(),
  .photo_audio_present(),.photo_audio_start(),.photo_audio_frames(),.error_code(cat_error));
 wire player_req;wire [31:0]player_addr,pending_id;wire [1:0]player_bank;
 wire pixel_valid,pixel_ready,started;wire[20:0]player_pixel_addr;wire[23:0]pixel_rgb;
 wire [3:0]player_state,player_error;
 // Register address translation before the held request crosses to SPI.
 always @(posedge decode_clk or posedge decode_rst)
  if(decode_rst)begin client_req<=0;client_addr<=0;end
  else begin client_req<=cat_ready?player_req:cat_req;client_addr<=cat_ready?(video_base+player_addr):cat_addr;end
 assign write_bank=player_bank[0];assign frame_id=pending_id[15:0];
 assign error_code=cat_error!=0?4'hc:(cat_ready&&!video_present)?4'he:player_error;
 assign state_code=!ready_sync[1]?4'h0:!cat_ready?4'h1:player_state;
 reg [11:0]sample_phase;reg [31:0]playhead;
 // 40 MHz * 3/2500 = 48 kHz. First completed frame starts the common clock.
 // The soundtrack will later replace this temporary presentation timer.
 always @(posedge decode_clk or posedge decode_rst)
  if(decode_rst)begin sample_phase<=0;playhead<=0;end
  else if(started&&!freeze_sync[1])begin
   if(sample_phase>=2497)begin sample_phase<=sample_phase-2497;playhead<=playhead+1'b1;end
   else sample_phase<=sample_phase+2'd3;
  end
 mjpeg_video_player player(.clk(decode_clk),.rst(decode_rst),
  .sd_ready(cat_ready&&video_present&&cat_error==0),.play_enable(!freeze_sync[1]||!started),
  .playhead_samples(playhead),.sec_req(player_req),.sec_addr(player_addr),.sec_data(client_data),
  .sec_valid(client_valid&&cat_ready),.sec_end(client_end&&cat_ready),
  .media_ready(),.audio_present(),.audio_start(),.audio_frames(),.playback_started(started),
  .frame_number(committed_frames),.total_frames(),.late_frames(),.dropped_frames(dropped_frames),
  .pending_frame_number(pending_id),.state_code(player_state),.error_code(player_error),
  .write_req(write_req),.write_req_ack(write_ack),.write_finish_toggle(finish_toggle),
  .write_bank(player_bank),.pixel_valid(pixel_valid),.pixel_ready(pixel_ready),
  .pixel_addr(player_pixel_addr),.pixel_rgb(pixel_rgb),
  .pixel_row(),.pixel_word(),
  .aspect_16x9(aspect_16x9),.frame_words(frame_words),
  .swap_valid(swap_valid),.swap_ready(swap_ready),.swap_done(swap_done),.swap_bank(swap_bank));
 // Store native JPEG coordinates directly in RGB565 SDRAM.
 rgb565_pack packer(.clk(decode_clk),.rst(decode_rst||write_req),
  .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_addr(player_pixel_addr),.pixel_rgb(pixel_rgb),
  .word_valid(word_valid),.word_ready(word_ready),.word_addr(word_addr),.word_data(word_data));
endmodule
