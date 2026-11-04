`timescale 1ns/1ps
// Functional-only clock models. Real production PLL files remain in TD build.
module video_hd_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,locked=0);
 integer count=0;
 always #6.734006734 clk0_out=~clk0_out;
 always #1.346801347 clk1_out=~clk1_out;
 always @(posedge refclk or posedge reset)
  if(reset)begin count<=0;locked<=0;end
  else if(count==32)locked<=1;else count<=count+1;
endmodule
module sys_pll(input refclk,reset,output reg clk0_out=0,output reg clk1_out=0,
 output clk2_out,output reg clk3_out=0,output reg locked=0);
 integer count=0;
 always #10 clk1_out=~clk1_out;
 always #5 clk0_out=~clk0_out;
 always #12.5 clk3_out=~clk3_out;
 assign #8.5 clk2_out=clk1_out;
 always @(posedge refclk or posedge reset)
  if(reset)begin count<=0;locked<=0;end
  else if(count==40)locked<=1;else count<=count+1;
endmodule
