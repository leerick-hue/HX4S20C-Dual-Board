`timescale 1ns/1ps
// Auxiliary PCM queue module with an ACR service window and sample buffering.
module hdmi_acr_pcm_gate #(
 parameter ADDR_BITS=7, parameter MIN_GAP=32
)(
 input clk,rst,pcm_valid,input[23:0]pcm_left,pcm_right,
 input acr_valid,input[19:0]acr_n,acr_cts,input acr_packet_seen,
 output reg out_pcm_valid,output reg[23:0]out_pcm_left,out_pcm_right,
 output reg out_acr_valid,output reg[19:0]out_acr_n,out_acr_cts,
 output waiting_acr,output reg[15:0]overflow_count,
 output[ADDR_BITS:0]queued_samples
);
 localparam DEPTH=1<<ADDR_BITS;
 localparam GAP_BITS=MIN_GAP>1?$clog2(MIN_GAP):1;
 reg[47:0]mem[0:DEPTH-1];
 reg[ADDR_BITS-1:0]wr,rd;
 reg[ADDR_BITS:0]mem_count;
 reg[47:0]prefetch_data;
 reg prefetch_valid,waiting;
 reg[GAP_BITS-1:0]pace;
 assign waiting_acr=waiting;
 assign queued_samples=mem_count+prefetch_valid;
 wire emit_sample=!rst && prefetch_valid && !waiting && !acr_valid && pace==0;
 wire fetch_sample=!rst && !prefetch_valid && mem_count!=0;
 wire accept_sample=!rst && pcm_valid && (queued_samples<DEPTH || emit_sample);
 // Independent synchronous memory ports; RAM and its data register are not reset.
 always @(posedge clk)begin
  if(accept_sample)mem[wr]<={pcm_left,pcm_right};
  if(fetch_sample)prefetch_data<=mem[rd];
 end
 always @(posedge clk)begin
  if(rst)begin
   wr<=0;rd<=0;mem_count<=0;prefetch_valid<=0;waiting<=0;pace<=0;
   out_pcm_valid<=0;out_pcm_left<=0;out_pcm_right<=0;
   out_acr_valid<=0;out_acr_n<=0;out_acr_cts<=0;overflow_count<=0;
  end else begin
   out_pcm_valid<=emit_sample;
   if(emit_sample)begin
    out_pcm_left<=prefetch_data[47:24];out_pcm_right<=prefetch_data[23:0];
    prefetch_valid<=0;pace<=MIN_GAP-1;
   end else begin
    if(fetch_sample)prefetch_valid<=1;
    if(pace!=0)pace<=pace-1'b1;
   end
   if(accept_sample)wr<=wr+1'b1;
   if(fetch_sample)rd<=rd+1'b1;
   case({accept_sample,fetch_sample})
    2'b10:mem_count<=mem_count+1'b1;
    2'b01:mem_count<=mem_count-1'b1;
    default:begin end
   endcase
   // A fresh update wins if its arrival coincides with an earlier packet ack.
   if(acr_valid)waiting<=1;
   else if(acr_packet_seen)waiting<=0;
   out_acr_valid<=acr_valid;
   if(acr_valid)begin out_acr_n<=acr_n;out_acr_cts<=acr_cts;end
   if(pcm_valid && !accept_sample && overflow_count!=16'hffff)
    overflow_count<=overflow_count+1'b1;
  end
 end
endmodule
