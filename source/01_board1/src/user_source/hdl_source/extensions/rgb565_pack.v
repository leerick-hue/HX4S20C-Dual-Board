`timescale 1ns/1ps
// Even-width raster rows: adjacent even/odd pixels form one SDRAM word.
// The scaler may traverse rows bottom-up, but pixels within each row ascend.
module rgb565_pack(input clk,rst,input pixel_valid,output pixel_ready,
 input[20:0]pixel_addr,input[23:0]pixel_rgb,
 output reg word_valid,input word_ready,output reg[20:0]word_addr,output reg[31:0]word_data);
 reg[15:0]first;
 wire[15:0]encoded={pixel_rgb[23:19],pixel_rgb[15:10],pixel_rgb[7:3]};
 // Break the SDRAM FIFO-full -> scaler row-control combinational path. The
 // single output word drains before accepting another pair (2 pixels/3 clocks
 // without stalls), comfortably faster than the TF byte stream.
 assign pixel_ready=!word_valid;
 always @(posedge clk or posedge rst)begin
  if(rst)begin first<=0;word_valid<=0;word_addr<=0;word_data<=0;end
  else begin
   if(word_valid && word_ready)word_valid<=0;
   if(pixel_valid && pixel_ready)begin
    if(!pixel_addr[0])first<=encoded;
    else begin word_valid<=1;word_addr<={1'b0,pixel_addr[20:1]};word_data<={encoded,first};end
   end
  end
 end
endmodule
