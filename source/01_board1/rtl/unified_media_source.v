`timescale 1ns/1ps
// A single source interface for both BMP albums and indexed MJPEG video.
// Every emitted RGB24 pixel enters the same RGB565 framebuffer path.
module unified_media_source #(parameter ENABLE_VIDEO=1, CLK_FREQ_HZ=40000000, PHOTO_WIDTH=1280, PHOTO_HEIGHT=720, PHOTO_ADDR_BITS=$clog2(PHOTO_WIDTH*PHOTO_HEIGHT))(
 input clk,rst,sd_ready,want_video,play_enable,input [31:0] playhead_samples,
 input key1,key2,input [2:0] edit_mode,
 input photo_next_cmd,photo_auto_valid_cmd,photo_auto_enable_cmd,
 output remote_album_ready,auto_state,
 output reg merged_req,output reg [31:0] merged_addr,
 input [7:0] player_byte,input player_byte_valid,player_end,bridge_overflow,
 output [10:0] source_width_debug,source_height_debug,
 output catalog_ready,active_video,video_present,photo_present,
 output reg media_ready,audio_present,output reg [31:0] audio_start,audio_frames,
 output playback_started,output [31:0] video_frame_number,video_total_frames,video_late_frames,video_dropped_frames,
 output [3:0] state_code,player_error,output [11:0] sd_debug,
 output [1:0] album_index_sd,output [2:0] album_count_sd,
 output sd_card_write_req,input sd_card_write_req_ack,frame_write_toggle_mem,
 output [1:0] write_buf_idx,output sd_card_write_en,input write_ready,
 output [20:0] write_pixel_addr,output [31:0] sd_card_write_data,
 output swap_valid,input swap_ready,swap_done,output swap_bank
);
 wire catalog_req,photo_audio_present;wire [31:0] catalog_addr;
 wire [31:0] video_base,media_photo_start,media_photo_max,photo_audio_start,photo_audio_frames;
 wire [2:0] media_photo_count;wire [3:0] catalog_error,video_error;
 wire video_media_ready,video_audio_present;wire [31:0] video_audio_start,video_audio_frames;
 wire player_req;wire [31:0] player_addr;wire [23:0] jpeg_rgb;
 wire album_req;wire [31:0] album_addr;
 wire album_write_req,album_pixel_valid,album_swap_valid,album_swap_bank,album_remote_ready,album_auto,album_display_valid;
 wire [31:0] album_pixel_data;wire [PHOTO_ADDR_BITS-1:0] album_pixel_addr;
 wire [1:0] album_write_bank,album_display_bank,album_index;wire [2:0] album_count;
 wire [3:0] album_state,video_state;wire [11:0] album_debug;
 wire video_write_req,video_pixel_valid,video_swap_valid,video_swap_bank;
 wire [1:0] video_write_bank;wire [20:0] video_pixel_addr;
 reg metadata_pending;
 (* ASYNC_REG="TRUE" *)reg [1:0] ready_sync;
 always @(posedge clk or posedge rst)
  if(rst)ready_sync<=0;else ready_sync<={ready_sync[0],sd_ready};
 assign player_error=catalog_error!=0?catalog_error:video_error;
generate if(ENABLE_VIDEO)begin:enabled_video
mjpeg_video_player #(.WIDTH(640),.HEIGHT(480)) video_player(
 .clk(clk),.rst(rst || !catalog_ready || !active_video),.sd_ready(ready_sync[1] && catalog_ready && active_video),.play_enable(play_enable),.playhead_samples(playhead_samples),
 .sec_req(player_req),.sec_addr(player_addr),.sec_data(player_byte),.sec_valid(player_byte_valid && catalog_ready && active_video),.sec_end(player_end && catalog_ready && active_video),
 .media_ready(video_media_ready),.audio_present(video_audio_present),.audio_start(video_audio_start),.audio_frames(video_audio_frames),
 .playback_started(playback_started),.frame_number(video_frame_number),.total_frames(video_total_frames),.late_frames(video_late_frames),.dropped_frames(video_dropped_frames),
 .state_code(video_state),.error_code(video_error),
 .write_req(video_write_req),.write_req_ack(sd_card_write_req_ack),.write_finish_toggle(frame_write_toggle_mem),
 .write_bank(video_write_bank),.pixel_valid(video_pixel_valid),.pixel_ready(write_ready && active_video),.pixel_addr(video_pixel_addr),.pixel_rgb(jpeg_rgb),
 .swap_valid(video_swap_valid),.swap_ready(swap_ready),.swap_done(swap_done),.swap_bank(video_swap_bank));
end else begin:disabled_video
 assign player_req=0,player_addr=0,video_media_ready=0,video_audio_present=0,video_audio_start=0,video_audio_frames=0;
 assign playback_started=0,video_frame_number=0,video_total_frames=0,video_late_frames=0,video_dropped_frames=0;
 assign video_state=0,video_error=0,video_write_req=0,video_write_bank=0,video_pixel_valid=0,video_pixel_addr=0,jpeg_rgb=0;
 assign video_swap_valid=0,video_swap_bank=0;
end endgenerate

media_catalog catalog(.clk(clk),.rst(rst),.sd_ready(ready_sync[1]),.want_video(ENABLE_VIDEO && want_video),
 .sec_req(catalog_req),.sec_addr(catalog_addr),.sec_data(player_byte),
 .sec_valid(player_byte_valid && !catalog_ready),.sec_end(player_end && !catalog_ready),
 .ready(catalog_ready),.active_video(active_video),.video_present(video_present),.photo_present(photo_present),
 .video_base(video_base),.photo_start(media_photo_start),.photo_max(media_photo_max),.photo_count(media_photo_count),
 .photo_audio_present(photo_audio_present),.photo_audio_start(photo_audio_start),.photo_audio_frames(photo_audio_frames),.error_code(catalog_error));
// Register request and address together. The bridge's100MHz sampler therefore
// captures a held32-bit payload, not the segment-base addition in flight.
always @(posedge clk or posedge rst)begin
 if(rst)begin merged_req<=0;merged_addr<=0;end
 else begin
  merged_req<=!catalog_ready?catalog_req:(active_video?player_req:album_req);
  merged_addr<=!catalog_ready?catalog_addr:(active_video?(video_base+player_addr):album_addr);
 end
end
sd_card_bmp #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.WIDTH(PHOTO_WIDTH),.HEIGHT(PHOTO_HEIGHT),.PIXEL_ADDR_BITS(PHOTO_ADDR_BITS)) album(
 .source_width_debug(source_width_debug),.source_height_debug(source_height_debug),
 .clk(clk),.rst(rst || !catalog_ready || active_video),.key_next(key1),.key_auto(key2),
 .remote_next(photo_next_cmd),.remote_auto_valid(photo_auto_valid_cmd),.remote_auto_enable(photo_auto_enable_cmd),.remote_ready(album_remote_ready),
 .key_inhibit(edit_mode!=0),.pixel_ready(write_ready && !active_video),.write_pixel_addr(album_pixel_addr),
 .swap_valid(album_swap_valid),.swap_ready(swap_ready),.swap_done(swap_done),.swap_bank(album_swap_bank),
 .state_code(album_state),.debug_status(album_debug),.displayed_image_index(album_index),.detected_image_count(album_count),.auto_play_enabled(album_auto),
 .bmp_width(PHOTO_WIDTH),.bmp_height(PHOTO_HEIGHT),.display_valid(album_display_valid),
 .write_finish_toggle(frame_write_toggle_mem),.write_buf_idx(album_write_bank),.disp_buf_idx(album_display_bank),
 .write_req(album_write_req),.write_req_ack(sd_card_write_req_ack),.write_en(album_pixel_valid),.write_data(album_pixel_data),
 .sd_init_done(ready_sync[1] && catalog_ready && photo_present),.media_ready(catalog_ready),
 .media_photo_start(media_photo_start),.media_photo_max(media_photo_max),.media_photo_count(media_photo_count),
 .sd_sec_read(album_req),.sd_sec_read_addr(album_addr),.sd_sec_read_data(player_byte),
 .sd_sec_read_data_valid(player_byte_valid && catalog_ready && !active_video),.sd_sec_read_end(player_end && catalog_ready && !active_video));
assign sd_card_write_data=active_video?{jpeg_rgb,8'd0}:album_pixel_data;
assign sd_card_write_en=catalog_ready && (active_video?video_pixel_valid:album_pixel_valid);
assign sd_card_write_req=catalog_ready && (active_video?video_write_req:album_write_req);
assign write_pixel_addr=active_video?video_pixel_addr:{{(21-PHOTO_ADDR_BITS){1'b0}},album_pixel_addr};
assign write_buf_idx=active_video?video_write_bank:album_write_bank;
assign swap_valid=catalog_ready && (active_video?video_swap_valid:album_swap_valid);
assign swap_bank=active_video?video_swap_bank:album_swap_bank;
assign remote_album_ready=active_video?video_media_ready:album_remote_ready;
assign auto_state=active_video?play_enable:album_auto;
assign album_index_sd=album_index;
assign album_count_sd=album_count;
assign state_code=catalog_error!=0?4'hf:(!catalog_ready?4'd0:(active_video?video_state:album_state));
assign sd_debug=catalog_error!=0?{4'hf,4'd0,catalog_error}:!catalog_ready?12'd0:active_video?{bridge_overflow,(video_dropped_frames!=0),2'b00,player_error,video_state}:album_debug;
always @(posedge clk or posedge rst)begin
 if(rst)begin media_ready<=0;metadata_pending<=0;audio_present<=0;audio_start<=0;audio_frames<=0;end
 else if(metadata_pending)begin media_ready<=1;metadata_pending<=0;end
 else if(catalog_ready && !media_ready && (active_video?video_media_ready:photo_present))begin
  audio_present<=active_video?video_audio_present:photo_audio_present;
  audio_start<=active_video?(video_base+video_audio_start):photo_audio_start;
  audio_frames<=active_video?video_audio_frames:photo_audio_frames;metadata_pending<=1;
 end
end

endmodule
