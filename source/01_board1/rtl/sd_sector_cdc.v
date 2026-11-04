`timescale 1ns/1ps
// 40 MHz JPEG client <-> 100 MHz SPI sector controller. Current SPI delivers
// bytes at least 36 sd_clk cycles apart (360 ns), longer than this mailbox's
// round trip. The payload is held until the next byte; requests until end.
module sd_sector_cdc(
 input client_clk,sd_clk,rst,
 input client_req,input [31:0] client_addr,
 output reg [7:0] client_data,output reg client_valid,client_end,
 output reg sd_req,output reg [31:0] sd_addr,
 input [7:0] sd_data,input sd_valid,sd_end,output reg overflow
);
 wire client_rst_n,sd_rst_n;
 wire client_rst=!client_rst_n,sd_rst=!sd_rst_n;
 reset_sync client_reset(.clk(client_clk),.arst_n(!rst),.rst_n(client_rst_n));
 reset_sync sd_reset(.clk(sd_clk),.arst_n(!rst),.rst_n(sd_rst_n));
 (* ASYNC_REG="TRUE" *)reg [1:0] req_sync;
 reg [7:0] held_data;
 reg byte_toggle,end_toggle;
 (* ASYNC_REG="TRUE" *)reg [2:0] byte_sync,end_sync;
 (* ASYNC_REG="TRUE" *)reg [1:0] ack_sync;
 reg byte_ack,end_seen,end_pending;
 wire byte_event=byte_sync[2]!=byte_ack;
 always @(posedge sd_clk or posedge sd_rst)begin
  if(sd_rst)begin req_sync<=0;sd_req<=0;sd_addr<=0;held_data<=0;
   byte_toggle<=0;end_toggle<=0;ack_sync<=0;overflow<=0;end
  else begin
   req_sync<={req_sync[0],client_req};ack_sync<={ack_sync[0],byte_ack};
   sd_req<=req_sync[1];if(!sd_req && req_sync[1])sd_addr<=client_addr;
   if(sd_valid)begin
    if(byte_toggle!=ack_sync[1])overflow<=1;
    held_data<=sd_data;byte_toggle<=!byte_toggle;
   end
   if(sd_end)end_toggle<=!end_toggle;
  end
 end
 always @(posedge client_clk or posedge client_rst)begin
  if(client_rst)begin byte_sync<=0;end_sync<=0;byte_ack<=0;end_seen<=0;end_pending<=0;
   client_data<=0;client_valid<=0;client_end<=0;end
  else begin
   byte_sync<={byte_sync[1:0],byte_toggle};end_sync<={end_sync[1:0],end_toggle};
   client_valid<=0;client_end<=0;
   if(byte_event)begin client_data<=held_data;client_valid<=1;byte_ack<=byte_sync[2];end
   if(end_sync[2]!=end_seen)begin end_seen<=end_sync[2];end_pending<=1;end
   if(end_pending && !byte_event && !client_valid)begin client_end<=1;end_pending<=0;end
  end
 end
endmodule
