`timescale 1ns/1ps
// HXJV PCM prefetch plus one common audio/video timebase. Without PCM the same
// audio PLL tick clocks video; pausing holds the playhead and emits silence.
module hxjv_pcm_player(
 input sd_clk,video_clk,playhead_clk,audio_mclk,rst,sd_ready,media_ready,audio_present,
 input [31:0] audio_start,audio_frames,input playback_started,play_enable,
 output reg sec_req,output reg [31:0] sec_addr,input [7:0] sec_data,input sec_valid,sec_end,
 output reg pcm_valid,output reg signed [23:0] pcm_left,pcm_right,
 output reg [31:0] underrun_count,output playing,output reg [31:0] playhead_samples
);
 wire sd_rst_n,video_rst_n,head_rst_n,audio_rst_n;
 wire sd_rst=!sd_rst_n,video_rst=!video_rst_n,head_rst=!head_rst_n,audio_rst=!audio_rst_n;
 reset_sync sd_reset(.clk(sd_clk),.arst_n(!rst),.rst_n(sd_rst_n));
 reset_sync video_reset(.clk(video_clk),.arst_n(!rst),.rst_n(video_rst_n));
 reset_sync head_reset(.clk(playhead_clk),.arst_n(!rst),.rst_n(head_rst_n));
 reset_sync audio_reset(.clk(audio_mclk),.arst_n(!rst),.rst_n(audio_rst_n));
 reg configured,reading,gap;
 reg sample_available;
 reg [2:0] advance_pending;
 reg cursor_hi_less,cursor_hi_equal,cursor_lo_less;
 (* ASYNC_REG="TRUE" *)reg [1:0] metadata_sync;
 reg [9:0] byte_index;
 reg [31:0] frame_cursor,base_lba,total_samples;
 reg [23:0] partial;
 reg fifo_we;reg [31:0] fifo_word;
 wire fifo_full,fifo_empty,fifo_valid;wire [11:0] wr_level,rd_level;wire [31:0] fifo_out;
 wire fifo_pop;
 audio_pcm_fifo fifo(.wr_clk(sd_clk),.rd_clk(video_clk),.rst(rst),
  .wr_en(fifo_we),.wr_data(fifo_word),.full(fifo_full),.wr_level(wr_level),
  .rd_en(fifo_pop),.rd_data(fifo_out),.rd_valid(fifo_valid),.empty(fifo_empty),.rd_level(rd_level));
 always @(posedge sd_clk or posedge sd_rst)begin
  if(sd_rst)begin
   sample_available<=0;advance_pending<=0;
   cursor_hi_less<=0;cursor_hi_equal<=0;cursor_lo_less<=0;
   metadata_sync<=0;configured<=0;reading<=0;gap<=0;sec_req<=0;sec_addr<=0;byte_index<=0;frame_cursor<=0;
   base_lba<=0;total_samples<=0;partial<=0;fifo_we<=0;fifo_word<=0;
  end else begin
   // A complete PCM word arrives no faster than once per four SD clocks.
   // Two16-bit comparisons followed by a registered select fit the100MHz
   // domain. The result settles before the next four-byte PCM word arrives.
   cursor_hi_less<=frame_cursor[31:16]<total_samples[31:16];
   cursor_hi_equal<=frame_cursor[31:16]==total_samples[31:16];
   cursor_lo_less<=frame_cursor[15:0]<total_samples[15:0];
   sample_available<=cursor_hi_less || (cursor_hi_equal && cursor_lo_less);
   advance_pending<={advance_pending[1:0],reading && sec_end};
   metadata_sync<={metadata_sync[0],media_ready};
   fifo_we<=0;if(gap)gap<=0;
   if(!configured && metadata_sync[1])begin
    configured<=1;base_lba<=audio_start;sec_addr<=audio_start;total_samples<=audio_frames;
   end
   if(configured && sd_ready && audio_present && total_samples!=0 && !reading && !gap && advance_pending==0 && wr_level<=1024)begin
    sec_req<=1;reading<=1;byte_index<=0;
   end
   if(reading && sec_valid)begin
    byte_index<=byte_index+1'b1;partial<={sec_data,partial[23:8]};
    if(byte_index[1:0]==3 && sample_available)begin
     fifo_word<={sec_data,partial};fifo_we<=1;frame_cursor<=frame_cursor+1'b1;
    end
   end
   if(reading && sec_end)begin
    sec_req<=0;reading<=0;gap<=1;
   end
   // Wait three clocks so both compare stages include a last word delivered
   // in the same cycle as sector end. The LBA mux needs no wide comparison.
   if(advance_pending[2])begin
    if(!sample_available)begin
     frame_cursor<=0;sec_addr<=base_lba;
    end else sec_addr<=sec_addr+1'b1;
   end
  end
 end
 reg [7:0] sample_div;
 reg sample_toggle;
 always @(posedge audio_mclk or posedge audio_rst)begin
  if(audio_rst)begin sample_div<=0;sample_toggle<=0;end
  else begin sample_div<=sample_div+1'b1;if(sample_div==255)sample_toggle<=!sample_toggle;end
 end
 (* ASYNC_REG="TRUE" *)reg [2:0] tick_sync;
 (* ASYNC_REG="TRUE" *)reg [1:0] present_sync,start_sync,ready_sync;
 reg primed,tick_pending;
 reg [31:0] playhead,playhead_gray;
 (* ASYNC_REG="TRUE" *)reg [31:0] gray_meta,gray_sync;
 wire tick=tick_sync[2]^tick_sync[1];
 wire active=ready_sync[1] && start_sync[1] && play_enable && (!present_sync[1] || primed);
 assign fifo_pop=tick && active && present_sync[1] && !fifo_empty;
 assign playing=active;
 function [31:0] binary;input [31:0] gray;integer k;begin
  binary[31]=gray[31];for(k=30;k>=0;k=k-1)binary[k]=binary[k+1]^gray[k];end endfunction
 always @(posedge playhead_clk or posedge head_rst)begin
  if(head_rst)begin gray_meta<=0;gray_sync<=0;playhead_samples<=0;end
  else begin gray_meta<=playhead_gray;gray_sync<=gray_meta;playhead_samples<=binary(gray_sync);end
 end
 always @(posedge video_clk or posedge video_rst)begin
  if(video_rst)begin
   tick_sync<=0;present_sync<=0;start_sync<=0;ready_sync<=0;primed<=0;tick_pending<=0;
   pcm_valid<=0;pcm_left<=0;pcm_right<=0;underrun_count<=0;playhead<=0;playhead_gray<=0;
  end else begin
   tick_sync<={tick_sync[1:0],sample_toggle};present_sync<={present_sync[0],audio_present};
   start_sync<={start_sync[0],playback_started};ready_sync<={ready_sync[0],media_ready};
   if(!primed && present_sync[1] && rd_level>=256)primed<=1;
   tick_pending<=tick;pcm_valid<=tick_pending;
   if(tick && active)begin
    playhead<=playhead+1'b1;playhead_gray<=((playhead+1'b1)>>1)^(playhead+1'b1);
    if(present_sync[1] && fifo_empty)underrun_count<=underrun_count+1'b1;
   end
   if(tick_pending)begin
    pcm_left<=fifo_valid?{fifo_out[15:0],8'd0}:24'd0;
    pcm_right<=fifo_valid?{fifo_out[31:16],8'd0}:24'd0;
   end
  end
 end
endmodule
