`timescale 1ns/1ps
// One synchronous FIFO word read supplies two consecutive pixel requests.
// pixel_rgb is valid one cycle after pixel_read, as for the original FIFO.
module rgb565_unpack(input clk,rst,input pixel_read,output word_read,
 input[31:0]word_data,input word_empty,output[23:0]pixel_rgb,output reg[31:0]underrun_count);
 reg odd_request,odd_response;
 wire[15:0]value=odd_response?word_data[31:16]:word_data[15:0];
 assign word_read=pixel_read && !odd_request;
 assign pixel_rgb={value[15:11],value[15:13],value[10:5],value[10:9],value[4:0],value[4:2]};
 always @(posedge clk or posedge rst)begin
  if(rst)begin odd_request<=0;odd_response<=0;underrun_count<=0;end
  else begin
   odd_response<=odd_request;
   if(pixel_read)odd_request<=!odd_request;else odd_request<=0;
   if(word_read && word_empty && underrun_count!=32'hffffffff)underrun_count<=underrun_count+1'b1;
  end
 end
endmodule
