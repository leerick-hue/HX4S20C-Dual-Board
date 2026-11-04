`timescale 1ns/1ps
// Progressive parameterized-sync timing, sync -> back porch -> active -> front porch.
module native_video_timing #(parameter WIDTH=1280,HEIGHT=720,HSA=40,HBP=220,HFP=110,VSA=5,VBP=20,VFP=5,HS_POLARITY=0,VS_POLARITY=0)(
 input clk,rst,output hs,vs,de);
 localparam HTOTAL=HSA+HBP+WIDTH+HFP,VTOTAL=VSA+VBP+HEIGHT+VFP;
 reg[11:0]h,v;
 assign hs=(h<HSA)?HS_POLARITY:!HS_POLARITY;assign vs=(v<VSA)?VS_POLARITY:!VS_POLARITY;
 assign de=h>=HSA+HBP && h<HSA+HBP+WIDTH && v>=VSA+VBP && v<VSA+VBP+HEIGHT;
 always @(posedge clk or posedge rst)begin
  if(rst)begin h<=0;v<=0;end
  else if(h==HTOTAL-1)begin h<=0;if(v==VTOTAL-1)v<=0;else v<=v+1'b1;end
  else h<=h+1'b1;
 end
endmodule
