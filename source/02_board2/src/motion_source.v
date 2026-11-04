`timescale 1ns/1ps
// A complete 640x480 RGB565 frame is written before ownership is transferred.
// All producer-side handshakes use mem_clk; the swap mailbox is the only CDC.
module motion_source(
 input clk,rst,init_done,
 output reg write_req,input write_ack,write_finish,
 output word_valid,input word_ready,
 output [20:0] word_addr,output [31:0] word_data,
 output reg write_bank,output reg [15:0] frame_id,
 output reg swap_valid,input swap_ready,swap_done,
 output reg [2:0] state
);
 localparam IDLE=0,REQUEST=1,SEND=2,DRAIN=3,POST=4,WAIT_SWAP=5;
 reg [17:0] address;
 reg [9:0] x;
 reg [8:0] y;
 reg finished;
 function automatic [6:0] segments;
  input [3:0] n;
  begin case(n)
   0:segments=7'b1111110;1:segments=7'b0110000;
   2:segments=7'b1101101;3:segments=7'b1111001;
   4:segments=7'b0110011;5:segments=7'b1011011;
   6:segments=7'b1011111;7:segments=7'b1110000;
   8:segments=7'b1111111;9:segments=7'b1111011;
   10:segments=7'b1110111;11:segments=7'b0011111;
   12:segments=7'b1001110;13:segments=7'b0111101;
   14:segments=7'b1001111;15:segments=7'b1000111;
  endcase end
 endfunction
 function automatic [15:0] pixel;
  input [9:0] px;input [8:0] py;input [15:0] f;
  reg [6:0] s;reg [4:0] dx;reg [5:0] dy;reg lit;
  reg [9:0] bx;
  begin
   bx={1'b0,f[6:0],2'b00};
   pixel={px[7:3],py[7:2],f[4:0]};
   if(px>=bx && px<bx+10'd64 && py>=192 && py<256)pixel=16'hffe0;
   if(px<4 || px>=636 || py<4 || py>=476)pixel=16'hffff;
   // Four hexadecimal digits are stored IN the framebuffer, not overlaid later.
   if(px>=64 && px<192 && py>=64 && py<128)begin
    case(px[6:5])
     2: s=segments(f[15:12]);3:s=segments(f[11:8]);
     0: s=segments(f[7:4]);1:s=segments(f[3:0]);
    endcase
    dx=px[4:0];dy=py[5:0];
    lit=(s[6]&&dy>=4&&dy<8&&dx>=6&&dx<26)||
        (s[5]&&dx>=24&&dx<28&&dy>=6&&dy<32)||
        (s[4]&&dx>=24&&dx<28&&dy>=32&&dy<58)||
        (s[3]&&dy>=56&&dy<60&&dx>=6&&dx<26)||
        (s[2]&&dx>=4&&dx<8&&dy>=32&&dy<58)||
        (s[1]&&dx>=4&&dx<8&&dy>=6&&dy<32)||
        (s[0]&&dy>=30&&dy<34&&dx>=6&&dx<26);
    pixel=lit?16'hffff:16'h0000;
   end
  end
 endfunction
 assign word_valid=state==SEND;
 assign word_addr={3'b0,address};
 assign word_data={pixel(x+10'd1,y,frame_id),pixel(x,y,frame_id)};
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   write_req<=0;swap_valid<=0;write_bank<=1;frame_id<=0;
   address<=0;x<=0;y<=0;state<=IDLE;finished<=0;
  end else begin
   if(write_finish)finished<=1;
   case(state)
    IDLE:if(init_done)begin write_req<=1;finished<=0;state<=REQUEST;end
    REQUEST:if(write_ack)begin write_req<=0;state<=SEND;end
    SEND:if(word_ready)begin
     if(address==153599)state<=DRAIN;
     else begin
      address<=address+1'b1;
      if(x==638)begin x<=0;y<=y+1'b1;end else x<=x+2'd2;
     end
    end
    DRAIN:if(finished)begin swap_valid<=1;state<=POST;end
    POST:if(swap_ready)begin swap_valid<=0;state<=WAIT_SWAP;end
    WAIT_SWAP:if(swap_done)begin
     write_bank<=!write_bank;frame_id<=frame_id+1'b1;
     address<=0;x<=0;y<=0;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
