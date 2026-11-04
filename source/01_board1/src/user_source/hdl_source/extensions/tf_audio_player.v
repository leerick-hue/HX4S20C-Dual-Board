`timescale 1ns/1ps
// Fixed PCM16 stereo/48k format. One sector is 128 frames; no compressed decoder.
module tf_audio_player #(parameter [31:0] MAX_SECTORS=1048576)(
 input sd_clk,input video_clk,input audio_mclk,input rst,input sd_ready,input play_enable,
 output reg sec_req,output reg [31:0] sec_addr,
 input [7:0] sec_data,input sec_valid,input sec_end,
 output reg media_ready,output reg audio_present,output reg [31:0] photo_start,
 output reg [31:0] photo_max,output reg [2:0] photo_count,
 output reg pcm_valid,output reg signed [23:0] pcm_left,output reg signed [23:0] pcm_right,
 output reg [31:0] underrun_count,output playing
);
 localparam PROBE=0,HEADER=1,CHECK=2,FILL=3,READ=4,QUIET=5,VALIDATE=6,APPLY=7;
 reg [2:0] state;
 reg [9:0] byte_idx;
 reg [31:0] header[0:8];
 reg [31:0] audio_start,total_frames,frame_cursor;
 reg [23:0] word_bytes;
 reg header_good,photo_good,format_good,start_good,metadata_good,audio_good;
 reg [32:0] audio_end_sector;
 reg fifo_we;reg [31:0] fifo_word;
 wire fifo_full,fifo_empty,fifo_valid;
 wire [11:0] fifo_wr_level,fifo_rd_level;
 wire [31:0] fifo_out;
 wire fifo_pop;
 integer i;
 audio_pcm_fifo fifo(.wr_clk(sd_clk),.rd_clk(video_clk),.rst(rst),
  .wr_en(fifo_we),.wr_data(fifo_word),.full(fifo_full),.wr_level(fifo_wr_level),
  .rd_en(fifo_pop),.rd_data(fifo_out),.rd_valid(fifo_valid),.empty(fifo_empty),.rd_level(fifo_rd_level));
 always @(posedge sd_clk or posedge rst) begin
  if(rst) begin
   state<=PROBE;sec_req<=0;sec_addr<=0;byte_idx<=0;media_ready<=0;audio_present<=0;
   photo_start<=0;photo_max<=131071;photo_count<=4;
   audio_start<=0;total_frames<=0;frame_cursor<=0;word_bytes<=0;fifo_we<=0;fifo_word<=0;
   header_good<=0;photo_good<=0;format_good<=0;start_good<=0;metadata_good<=0;audio_good<=0;audio_end_sector<=0;
   for(i=0;i<9;i=i+1) header[i]<=0;
  end else begin
   fifo_we<=0;
   case(state)
    PROBE: if(sd_ready) begin sec_addr<=0;sec_req<=1;byte_idx<=0;state<=HEADER;end
    HEADER: begin
      if(sec_valid) begin
       if(byte_idx<36) header[byte_idx[5:2]] <= {sec_data,header[byte_idx[5:2]][31:8]};
       byte_idx<=byte_idx+1'b1;
      end
      if(sec_end) begin sec_req<=0;state<=CHECK;end
    end
    // Header checks run once at boot. Split arithmetic and decisions across
    // clocks so the 100 MHz SD path does not include a long comparator chain.
    CHECK: begin
      header_good<=byte_idx==512 && header[0]==32'h55415848 && header[1]==1;
      photo_good<=header[7]>1 && header[7]<=MAX_SECTORS && header[8]>=1 && header[8]<=4;
      format_good<=header[2]==48000 && header[3]==2 && header[4]==16 && header[6]>=128 && header[6]<=32'h3fffffff;
      start_good<=header[5]>=header[7];
      audio_end_sector<={1'b0,header[5]}+{8'd0,header[6][31:7]}+(|header[6][6:0]);
      state<=VALIDATE;
    end
    VALIDATE: begin
      metadata_good<=header_good && photo_good;
      audio_good<=format_good && start_good && audio_end_sector<={1'b0,MAX_SECTORS};
      state<=APPLY;
    end
    APPLY: begin
      media_ready<=1;state<=QUIET;
      if(metadata_good) begin
        photo_start<=1;photo_max<=header[7]-1'b1;photo_count<=header[8][2:0];
        if(audio_good) begin
          audio_present<=1;audio_start<=header[5];sec_addr<=header[5];total_frames<=header[6];state<=FILL;
        end
      end
    end
    FILL: if(fifo_wr_level<=1024) begin sec_req<=1;byte_idx<=0;state<=READ;end
    READ: begin
      if(sec_valid) begin
       byte_idx<=byte_idx+1'b1;
       word_bytes<={sec_data,word_bytes[23:8]};
       if(byte_idx[1:0]==3 && frame_cursor<total_frames) begin
        fifo_word<={sec_data,word_bytes};fifo_we<=1;frame_cursor<=frame_cursor+1'b1;
       end
      end
      if(sec_end) begin
       sec_req<=0;state<=FILL;
       if(frame_cursor>=total_frames || (sec_valid && byte_idx[1:0]==3 && frame_cursor==total_frames-1'b1)) begin frame_cursor<=0;sec_addr<=audio_start;end
       else sec_addr<=sec_addr+1'b1;
      end
    end
    default: sec_req<=0;
   endcase
  end
 end
 // Preserve the existing audio clock; remove the unnecessary I2S serializer/receiver round trip.
 reg [7:0] sample_div;
 reg sample_toggle;
 always @(posedge audio_mclk or posedge rst) begin
  if(rst) begin sample_div<=0;sample_toggle<=0;end
  else begin sample_div<=sample_div+1'b1;if(sample_div==255) sample_toggle<=~sample_toggle;end
 end
 (* ASYNC_REG="TRUE" *) reg [2:0] tick_sync;
 (* ASYNC_REG="TRUE" *) reg [1:0] present_sync;
 reg primed,tick_pending;
 wire sample_tick=tick_sync[2]^tick_sync[1];
 assign fifo_pop=sample_tick && play_enable && primed && !fifo_empty;
 assign playing=play_enable && primed && present_sync[1];
 always @(posedge video_clk or posedge rst) begin
  if(rst) begin
   tick_sync<=0;present_sync<=0;primed<=0;tick_pending<=0;
   pcm_valid<=0;pcm_left<=0;pcm_right<=0;underrun_count<=0;
  end else begin
   tick_sync<={tick_sync[1:0],sample_toggle};present_sync<={present_sync[0],audio_present};
   if(!primed && present_sync[1] && fifo_rd_level>=256) primed<=1;
   if(sample_tick && play_enable && primed && fifo_empty) begin
    primed<=0;if(underrun_count!=32'hffffffff) underrun_count<=underrun_count+1'b1;
   end
   tick_pending<=sample_tick;pcm_valid<=tick_pending;
   if(tick_pending) begin
    pcm_left<=fifo_valid?{fifo_out[15:0],8'd0}:24'd0;
    pcm_right<=fifo_valid?{fifo_out[31:16],8'd0}:24'd0;
   end
  end
 end
endmodule
