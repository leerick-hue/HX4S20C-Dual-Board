`timescale 1ns/1ps
// Two complete sectors decouple a non-stallable SD response from JPEG stalls.
// core_jpeg consumes byte zero first. Its last flag flushes immediately, so
// every real word has last=0, followed by a separate dummy last=1 transfer.
module jpeg_sector_stream(
 input clk,rst,start,input [31:0] start_lba,jpeg_bytes,
 output reg sec_req,output reg [31:0] sec_addr,
 input [7:0] sec_data,input sec_valid,sec_end,
 output reg in_valid,output reg [31:0] in_data,output [3:0] in_strb,
 output reg in_last,input in_accept,output reg done,output reg failed
);
 reg [31:0] ram[0:255];
 reg [1:0] full;
 reg fill_bank,send_bank,inflight,gap,active,flush_pending;
 reg [9:0] byte_index;
 reg [6:0] word_index;
 reg [23:0] partial;
 reg [31:0] sectors_left,words_left;
 assign in_strb=in_last?4'b0001:4'b1111;
 always @(posedge clk) begin
  if(sec_valid && inflight && byte_index[1:0]==3)
   ram[{fill_bank,byte_index[8:2]}]<={sec_data,partial};
  if(!in_valid && active && !flush_pending && full[send_bank])
   in_data<=ram[{send_bank,word_index}];
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   sec_req<=0;sec_addr<=0;in_valid<=0;in_last<=0;done<=0;failed<=0;
   full<=0;fill_bank<=0;send_bank<=0;inflight<=0;gap<=0;active<=0;
   flush_pending<=0;byte_index<=0;word_index<=0;partial<=0;
   sectors_left<=0;words_left<=0;
  end else begin
   done<=0;
   if(start) begin
    sec_req<=0;sec_addr<=start_lba;in_valid<=0;in_last<=0;failed<=0;
    full<=0;fill_bank<=0;send_bank<=0;inflight<=0;gap<=0;active<=1;
    flush_pending<=0;byte_index<=0;word_index<=0;partial<=0;
    sectors_left<=(jpeg_bytes+511)>>9;words_left<=(jpeg_bytes+3)>>2;
   end else begin
    if(gap)gap<=0;
    if(active && !inflight && !gap && sectors_left!=0 && !full[fill_bank]) begin
     sec_req<=1;inflight<=1;byte_index<=0;
    end
    if(inflight && sec_valid) begin
     partial<={sec_data,partial[23:8]};byte_index<=byte_index+1'b1;
    end
    if(inflight && sec_end) begin
     sec_req<=0;inflight<=0;gap<=1;
     if(byte_index!=512 && !(sec_valid && byte_index==511))failed<=1;
     full[fill_bank]<=1;fill_bank<=!fill_bank;
     sectors_left<=sectors_left-1'b1;sec_addr<=sec_addr+1'b1;
    end
    if(active && !in_valid) begin
     if(flush_pending)begin in_valid<=1;in_last<=1;end
     else if(full[send_bank])begin in_valid<=1;in_last<=0;end
    end
    if(in_valid && in_accept) begin
     in_valid<=0;
     if(in_last)begin active<=0;done<=1;flush_pending<=0;in_last<=0;end
     else begin
      words_left<=words_left-1'b1;word_index<=word_index+1'b1;
      if(word_index==127 || words_left==1)begin
       full[send_bank]<=0;send_bank<=!send_bank;word_index<=0;
      end
      if(words_left==1)flush_pending<=1;
     end
    end
   end
  end
 end
endmodule
