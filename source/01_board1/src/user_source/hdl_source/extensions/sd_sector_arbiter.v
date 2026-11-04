`timescale 1ns/1ps
// Audio wins first; pending clients alternate sectors so neither can starve.
// Requests stay high through end. A release cycle prevents duplicate sectors.
module sd_sector_arbiter(
 input clk,input rst,input ready,
 input photo_req,input [31:0] photo_addr,output [7:0] photo_data,output photo_valid,output photo_end,
 input audio_req,input [31:0] audio_addr,output [7:0] audio_data,output audio_valid,output audio_end,
 output reg sd_req,output reg [31:0] sd_addr,input [7:0] sd_data,input sd_valid,input sd_end
);
 reg [1:0] state;reg owner_audio;
 wire choose_audio=audio_req && (!photo_req || !owner_audio);
 assign photo_data=sd_data;assign audio_data=sd_data;
 assign photo_valid=(state==1)&&!owner_audio&&sd_valid;
 assign photo_end=(state==1)&&!owner_audio&&sd_end;
 assign audio_valid=(state==1)&&owner_audio&&sd_valid;
 assign audio_end=(state==1)&&owner_audio&&sd_end;
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=0;sd_req<=0;sd_addr<=0;owner_audio<=0;end
  else case(state)
   0: if(ready && (audio_req || photo_req)) begin
      owner_audio<=choose_audio;sd_addr<=choose_audio?audio_addr:photo_addr;sd_req<=1;state<=1;
   end
   1: if(sd_end) begin sd_req<=0;state<=2;end
   2: if(owner_audio ? !audio_req : !photo_req) state<=0;
   default:state<=0;
  endcase
 end
endmodule
