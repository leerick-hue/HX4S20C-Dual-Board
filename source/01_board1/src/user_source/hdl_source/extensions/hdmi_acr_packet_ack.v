`timescale 1ns/1ps
// Internal parallel-TMDS scheduling acknowledgement, one pulse per ACR packet.
// Header type only; not a body/BCH or physical receiver validator.
module hdmi_acr_packet_ack(
 input clk,rst,input[9:0]c0,c1,c2,output reg acr_packet_seen
);
 // Only C0 TERC4 validity/header-bit and guard classification are needed.
 function[2:0]classify;input[9:0]v;begin
  case(v)
   10'h29c,10'h263,10'h2e4,10'h2e2,10'h2cc,10'h139,10'h19c,10'h2c6:classify=3'b100;
   10'h171,10'h11e,10'h18e,10'h13c:classify=3'b101;
   10'h28e,10'h271,10'h163,10'h2c3:classify=3'b111;
   default:classify=0;
  endcase
 end endfunction
 wire[2:0]tag=classify(c0);
 wire guard=c1==10'h133 && c2==10'h133 && tag[1];
 reg[1:0]state;reg[3:0]preamble;reg[4:0]index;reg header_ok;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=0;preamble<=0;index<=0;header_ok<=0;acr_packet_seen<=0;end
  else begin
   acr_packet_seen<=0;
   case(state)
    0:begin
     if(c1==10'h0ab && c2==10'h0ab)begin if(preamble!=15)preamble<=preamble+1'b1;end
     else if(preamble>=8 && guard)begin state<=1;preamble<=0;end
     else preamble<=0;
    end
    1:if(!guard)begin
     if(tag[2])begin header_ok<=tag[0];index<=1;state<=2;end
     else state<=0;
    end
    2:if(tag[2])begin
     if(index<8)header_ok<=header_ok && !tag[0];
     if(index==31)begin acr_packet_seen<=header_ok;state<=3;end
     else index<=index+1'b1;
    end else begin state<=0;preamble<=0;end
    3:if(guard)begin state<=0;preamble<=0;end
      else if(tag[2])begin header_ok<=tag[0];index<=1;state<=2;end
      else begin state<=0;preamble<=0;end
   endcase
  end
 end
endmodule
