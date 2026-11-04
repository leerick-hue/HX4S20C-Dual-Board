`timescale 1ns/1ps
// 8 KiB true dual-port PCM FIFO. Gray pointers cross clocks; data stays in RAM.
module audio_pcm_fifo #(parameter AW=11)(
 input wr_clk,input rd_clk,input rst,
 input wr_en,input [31:0] wr_data,output full,output [AW:0] wr_level,
 input rd_en,output reg [31:0] rd_data,output reg rd_valid,output empty,output [AW:0] rd_level
);
 wire wr_rst_n,rd_rst_n;
 wire wr_rst=!wr_rst_n,rd_rst=!rd_rst_n;
 reset_sync wr_reset(.clk(wr_clk),.arst_n(!rst),.rst_n(wr_rst_n));
 reset_sync rd_reset(.clk(rd_clk),.arst_n(!rst),.rst_n(rd_rst_n));
 reg [31:0] mem[0:(1<<AW)-1];
 reg [AW:0] wb,rb,wgray,rgray;
 (* ASYNC_REG="TRUE" *) reg [AW:0] rg_meta,rg_sync,wg_meta,wg_sync;
 function [AW:0] binary; input [AW:0] g; integer i; begin
   binary[AW]=g[AW];for(i=AW-1;i>=0;i=i-1) binary[i]=binary[i+1]^g[i];
 end endfunction
 assign wr_level=wb-binary(rg_sync);
 assign rd_level=binary(wg_sync)-rb;
 assign full=(wgray=={~rg_sync[AW:AW-1],rg_sync[AW-2:0]});
 assign empty=(rgray==wg_sync);
 always @(posedge wr_clk or posedge wr_rst) begin
  if(wr_rst) begin wb<=0;wgray<=0;rg_meta<=0;rg_sync<=0;end
  else begin
   rg_meta<=rgray;rg_sync<=rg_meta;
   if(wr_en && !full) begin wb<=wb+1'b1;wgray<=((wb+1'b1)>>1)^(wb+1'b1);end
  end
 end
 always @(posedge wr_clk) if(wr_en && !full) mem[wb[AW-1:0]]<=wr_data;
 always @(posedge rd_clk or posedge rd_rst) begin
  if(rd_rst) begin rb<=0;rgray<=0;wg_meta<=0;wg_sync<=0;rd_valid<=0;end
  else begin
   wg_meta<=wgray;wg_sync<=wg_meta;rd_valid<=rd_en && !empty;
   if(rd_en && !empty) begin rb<=rb+1'b1;rgray<=((rb+1'b1)>>1)^(rb+1'b1);end
  end
 end
 always @(posedge rd_clk) if(rd_en && !empty) rd_data<=mem[rb[AW-1:0]];
endmodule
