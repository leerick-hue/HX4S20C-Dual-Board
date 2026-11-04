`timescale 1ns/1ps
// A source change restarts ALL media state together, including SD command
// logic, SDRAM controller, both swap endpoints and both sides of each FIFO.
// UI controls and HDMI timing are outside this reset and remain running.
module media_mode_reset #(parameter HOLD_CYCLES=1024)(
 input clk,rst,want_video,output media_rst
);
 localparam BITS=(HOLD_CYCLES<2)?1:$clog2(HOLD_CYCLES+1);
 reg [BITS-1:0] hold_count;
 reg selected;
 assign media_rst=rst || (hold_count!=0) || (want_video!=selected);
 always @(posedge clk or posedge rst)begin
  if(rst)begin hold_count<=HOLD_CYCLES;selected<=0;end
  else if(want_video!=selected)begin selected<=want_video;hold_count<=HOLD_CYCLES;end
  else if(hold_count!=0)hold_count<=hold_count-1'b1;
 end
endmodule
