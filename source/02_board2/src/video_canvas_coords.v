`timescale 1ns/1ps
// Map only overlay coordinates to the original640x480 canvas. RGB stays native.
// DDA gives floor(x*640/WIDTH),floor(y*480/HEIGHT), without dividers/multipliers.
module video_canvas_coords #(parameter WIDTH=1280,HEIGHT=720,VS_POLARITY=1)(
 input clk,rst,input de,vs,output reg[9:0]x,output reg[9:0]y);
 reg previous_de;reg[12:0]phase_x,phase_y;
 wire[13:0]next_x={1'b0,phase_x}+14'd640,next_y={1'b0,phase_y}+14'd480;
 always @(posedge clk or posedge rst)begin
  if(rst)begin previous_de<=0;x<=0;y<=0;phase_x<=0;phase_y<=0;end
  else begin
   previous_de<=de;
   if(vs==VS_POLARITY)begin x<=0;y<=0;phase_x<=0;phase_y<=0;end
   else begin
    if(de)begin
     if(next_x>=WIDTH)begin phase_x<=next_x-WIDTH;x<=x+1'b1;end else phase_x<=next_x;
    end else begin
     x<=0;phase_x<=0;
     if(previous_de)begin
      if(next_y>=HEIGHT)begin phase_y<=next_y-HEIGHT;y<=y+1'b1;end else phase_y<=next_y;
     end
    end
   end
  end
 end
endmodule
