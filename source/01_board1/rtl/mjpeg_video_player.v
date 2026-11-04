`timescale 1ns/1ps
// HXJV v1 indexed Baseline JPEG player. All control and JPEG logic uses sd_clk.
// Bank ownership transfers only after the SDRAM write completion and vblank ACK.
module mjpeg_video_player #(
 parameter WIDTH=640,HEIGHT=480,parameter [31:0] MAX_JPEG_BYTES=131072
)(
 input clk,rst,sd_ready,play_enable,input [31:0] playhead_samples,
 output sec_req,output [31:0] sec_addr,input [7:0] sec_data,input sec_valid,sec_end,
 output reg media_ready,output reg audio_present,output reg [31:0] audio_start,audio_frames,
 output reg playback_started,output reg [31:0] frame_number,total_frames,late_frames,dropped_frames,
 output reg [3:0] state_code,output reg [3:0] error_code,
 output reg write_req,input write_req_ack,input write_finish_toggle,
 output [1:0] write_bank,output pixel_valid,input pixel_ready,
 output [20:0] pixel_addr,output [23:0] pixel_rgb,
 output reg swap_valid,input swap_ready,swap_done,output swap_bank
);
 localparam BOOT=0,HEADER=1,CHECK=2,INDEX=3,INDEX_READ=4,ENTRY_CHECK=5,
  WRITE_BEGIN=6,WRITE_ACK_LOW=7,DECODE=8,DRAIN=9,DUE=10,SWAP_WAIT=11,ERROR=15;
 reg [3:0] state;
 reg req;
 reg [31:0] addr;
 reg [9:0] byte_index;
 reg [31:0] header[0:20];
 reg [31:0] entry[0:3];
 reg [31:0] index_lba,frame_index,duration_samples,epoch,frame_pts,frame_bytes,frame_lba;
 reg [11:0] frame_interval;
 reg bank,stream_start,stream_finished;
 reg [18:0] pixel_count;
 (* ASYNC_REG="TRUE" *)reg [1:0] ack_sync;
 (* ASYNC_REG="TRUE" *)reg [2:0] finish_sync;
 reg finish_seen,write_completed;
 wire stream_req,stream_done,stream_failed,stream_valid,stream_last,stream_accept;
 wire [31:0] stream_addr,stream_data;
 wire [3:0] stream_strb;
 wire decode_active=(state==DECODE || state==DRAIN);
 wire [15:0] jpg_width,jpg_height,jpg_x,jpg_y;
 wire jpg_valid,jpg_idle;
 wire [7:0] jpg_r,jpg_g,jpg_b;
 wire valid_geometry=jpg_width==WIDTH && jpg_height==HEIGHT && jpg_x<WIDTH && jpg_y<HEIGHT;
 assign sec_req=decode_active?stream_req:req;
 assign sec_addr=decode_active?stream_addr:addr;
 assign write_bank={1'b0,bank};assign swap_bank=bank;
 assign pixel_valid=jpg_valid && decode_active && valid_geometry;
 generate if(WIDTH==640)begin: address640
  wire [20:0] y={5'd0,jpg_y};
  assign pixel_addr=(y<<9)+(y<<7)+{5'd0,jpg_x};
 end else begin: address_other
  assign pixel_addr=jpg_y*WIDTH+jpg_x;
 end endgenerate
 assign pixel_rgb={jpg_r,jpg_g,jpg_b};
 jpeg_sector_stream stream(.clk(clk),.rst(rst),.start(stream_start),
  .start_lba(frame_lba),.jpeg_bytes(frame_bytes),.sec_req(stream_req),.sec_addr(stream_addr),
  .sec_data(sec_data),.sec_valid(sec_valid && decode_active),.sec_end(sec_end && decode_active),
  .in_valid(stream_valid),.in_data(stream_data),.in_strb(stream_strb),.in_last(stream_last),
  .in_accept(stream_accept),.done(stream_done),.failed(stream_failed));
 jpeg_core #(.SUPPORT_WRITABLE_DHT(0)) decoder(.clk_i(clk),.rst_i(rst || state==WRITE_BEGIN),
  .inport_valid_i(stream_valid),.inport_data_i(stream_data),.inport_strb_i(stream_strb),
  .inport_last_i(stream_last),.inport_accept_o(stream_accept),
  .outport_valid_o(jpg_valid),.outport_accept_i(pixel_ready && decode_active),
  .outport_width_o(jpg_width),.outport_height_o(jpg_height),
  .outport_pixel_x_o(jpg_x),.outport_pixel_y_o(jpg_y),
  .outport_pixel_r_o(jpg_r),.outport_pixel_g_o(jpg_g),.outport_pixel_b_o(jpg_b),.idle_o(jpg_idle));
 integer i;
 always @(posedge clk or posedge rst) begin
  if(rst)begin
   state<=BOOT;state_code<=BOOT;error_code<=0;req<=0;addr<=0;byte_index<=0;
   media_ready<=0;audio_present<=0;audio_start<=0;audio_frames<=0;playback_started<=0;
   frame_number<=0;total_frames<=0;late_frames<=0;dropped_frames<=0;frame_interval<=1600;index_lba<=0;frame_index<=0;
   duration_samples<=0;epoch<=0;frame_pts<=0;frame_bytes<=0;frame_lba<=0;
   bank<=1;stream_start<=0;stream_finished<=0;pixel_count<=0;ack_sync<=0;
   finish_sync<=0;finish_seen<=0;write_completed<=0;write_req<=0;swap_valid<=0;
   for(i=0;i<21;i=i+1)header[i]<=0;
   for(i=0;i<4;i=i+1)entry[i]<=0;
  end else begin
   state_code<=state;stream_start<=0;
   ack_sync<={ack_sync[0],write_req_ack};finish_sync<={finish_sync[1:0],write_finish_toggle};
   if(finish_sync[2]!=finish_seen)begin finish_seen<=finish_sync[2];write_completed<=1;end
   if(stream_done)stream_finished<=1;
   if(pixel_valid && pixel_ready)pixel_count<=pixel_count+1'b1;
   if(jpg_valid && decode_active && !valid_geometry)begin state<=ERROR;error_code<=4;end
   else case(state)
    BOOT:if(sd_ready)begin req<=1;addr<=0;byte_index<=0;state<=HEADER;end
    HEADER:begin
     if(sec_valid)begin
      if(byte_index<84)header[byte_index[6:2]]<={sec_data,header[byte_index[6:2]][31:8]};
      byte_index<=byte_index+1'b1;
     end
     if(sec_end)begin req<=0;state<=CHECK;end
    end
    CHECK:begin
     if(byte_index!=512 || header[0]!=32'h564a5848 || header[1]!=1 || header[2]!=512 ||
        header[4]!=WIDTH || header[5]!=HEIGHT || header[8]==0 || header[20]!=16 ||
        header[14]!=48000 || header[15]!=2 || header[16]!=16 ||
        !((header[6]==30 || header[6]==25 || header[6]==50 || header[6]==60) && header[7]==1))begin state<=ERROR;error_code<=1;end
     else begin
      media_ready<=1;audio_present<=header[3][0];audio_start<=header[12];audio_frames<=header[13];
      total_frames<=header[8];index_lba<=header[9];duration_samples<=header[19];
      frame_interval<=header[6]==60?800:header[6]==50?960:header[6]==25?1920:1600;state<=INDEX;
     end
    end
    INDEX:begin req<=1;addr<=index_lba+(frame_index>>5);byte_index<=0;state<=INDEX_READ;end
    INDEX_READ:begin
     if(sec_valid)begin
      if(byte_index[8:4]==frame_index[4:0])
       entry[byte_index[3:2]]<={sec_data,entry[byte_index[3:2]][31:8]};
      byte_index<=byte_index+1'b1;
     end
     if(sec_end)begin req<=0;state<=ENTRY_CHECK;end
    end
    ENTRY_CHECK:begin
     if(byte_index!=512 || entry[1]<4 || entry[1]>MAX_JPEG_BYTES)begin state<=ERROR;error_code<=2;end
     // A frame whose entire presentation interval has elapsed is obsolete.
     // Skip it before spending TF bandwidth and decode cycles; this bounds A/V
     // drift with the59.524Hz legacy display clock or a temporary card stall.
     else if(playback_started && play_enable &&
       $signed(playhead_samples-(epoch+entry[2])) >= $signed({20'd0,frame_interval}))begin
      dropped_frames<=dropped_frames+1'b1;
      if(frame_index==total_frames-1'b1)begin frame_index<=0;epoch<=epoch+duration_samples;end
      else frame_index<=frame_index+1'b1;
      state<=INDEX;
     end else begin
      frame_lba<=entry[0];frame_bytes<=entry[1];frame_pts<=epoch+entry[2];
      write_req<=1;write_completed<=0;pixel_count<=0;stream_finished<=0;state<=WRITE_BEGIN;
     end
    end
    WRITE_BEGIN:if(ack_sync[1])begin write_req<=0;state<=WRITE_ACK_LOW;end
    WRITE_ACK_LOW:if(!ack_sync[1])begin stream_start<=1;state<=DECODE;end
    DECODE:begin
     if(stream_failed)begin error_code<=3;state<=ERROR;end
     else if(pixel_count==WIDTH*HEIGHT)state<=DRAIN;
    end
    DRAIN:if(write_completed && stream_finished && jpg_idle)state<=DUE;
    DUE:if(play_enable && (!playback_started || $signed(playhead_samples-frame_pts)>=0) && swap_ready)begin
     // Always show the newest completed decode. Discarding it here can freeze
     // the screen forever when decode time exceeds the source frame interval.
     // INDEX skips stale *unstarted* frames after this safe vblank commit.
     if(playback_started && $signed(playhead_samples-frame_pts)>=$signed({20'd0,frame_interval}))
      late_frames<=late_frames+1'b1;
     swap_valid<=1;state<=SWAP_WAIT;
    end
    SWAP_WAIT:begin
     if(swap_valid && swap_ready)swap_valid<=0;
     if(swap_done)begin
      playback_started<=1;frame_number<=frame_index+1'b1;bank<=!bank;
      if(frame_index==total_frames-1'b1)begin frame_index<=0;epoch<=epoch+duration_samples;end
      else frame_index<=frame_index+1'b1;
      state<=INDEX;
     end
    end
    default:begin req<=0;write_req<=0;swap_valid<=0;end
   endcase
  end
 end
endmodule
