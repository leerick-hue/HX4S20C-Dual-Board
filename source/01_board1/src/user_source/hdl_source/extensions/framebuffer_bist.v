`timescale 1ns/1ps
// Boot-selected framebuffer check. Known nonzero words use the normal write
// FIFO, SDRAM controller, display FIFO and raster. Normal media mode bypasses it.
module framebuffer_bist #(parameter FRAME_WORDS=460800)(
 input decode_clk,decode_rst_n,pixel_clk,pixel_rst_n,enable,
 output reg write_req,input write_ack,
 output word_valid,input word_ready,output [20:0]word_addr,output [31:0]word_data,
 input write_finish_toggle,output reg swap_valid,input swap_ready,swap_done,
 input read_req,word_read,word_empty,input [31:0]read_data,
 output [15:0] status
);
 function [31:0] pattern;
  input [20:0] a;
  begin pattern={a[15:0],a[20:5]}^32'hfc0083e0;end
 endfunction
 localparam IDLE=0,REQUEST=1,SEND=2,WAIT_WRITE=3,SWAP=4,WAIT_SWAP=5,HOLD=6;
 reg [2:0]state;
 reg [20:0]write_addr;
 reg finish_baseline,write_done;
 (* ASYNC_REG="TRUE" *)reg [1:0]enable_sync;
 (* ASYNC_REG="TRUE" *)reg [2:0]finish_sync;
 assign word_valid=state==SEND;
 assign word_addr=write_addr;
 assign word_data=pattern(write_addr);
 always @(posedge decode_clk or negedge decode_rst_n)begin
  if(!decode_rst_n)begin
   enable_sync<=0;finish_sync<=0;state<=IDLE;write_req<=0;swap_valid<=0;
   write_addr<=0;finish_baseline<=0;write_done<=0;
  end else begin
   enable_sync<={enable_sync[0],enable};
   finish_sync<={finish_sync[1:0],write_finish_toggle};
   case(state)
    IDLE:if(enable_sync[1])begin
     write_req<=1;finish_baseline<=finish_sync[2];state<=REQUEST;
    end
    REQUEST:if(write_ack)begin write_req<=0;state<=SEND;end
    SEND:if(word_ready)begin
     if(write_addr==FRAME_WORDS-1)state<=WAIT_WRITE;
     else write_addr<=write_addr+1'b1;
    end
    WAIT_WRITE:if(finish_sync[2]!=finish_baseline)begin
     write_done<=1;swap_valid<=1;state<=SWAP;
    end
    SWAP:if(swap_ready)begin swap_valid<=0;state<=WAIT_SWAP;end
    WAIT_SWAP:if(swap_done)state<=HOLD;
    default:begin write_req<=0;swap_valid<=0;end
   endcase
  end
 end

 (* ASYNC_REG="TRUE" *)reg [1:0]done_sync;
 reg [20:0]read_addr;
 reg [31:0]expected;
 reg pending,last_pending,frame_checked,underflow_seen,error_seen;
 reg [11:0]errors;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin
   done_sync<=0;read_addr<=0;expected<=0;pending<=0;last_pending<=0;
   frame_checked<=0;underflow_seen<=0;error_seen<=0;errors<=0;
  end else begin
   done_sync<={done_sync[0],write_done};
   if(!enable || read_req)begin read_addr<=0;pending<=0;last_pending<=0;end
   else begin
    pending<=word_read && !word_empty;
    last_pending<=word_read && !word_empty && read_addr==FRAME_WORDS-1;
    if(word_read && word_empty)underflow_seen<=1;
    if(word_read && !word_empty)begin
     expected<=pattern(read_addr);read_addr<=read_addr+1'b1;
    end
    if(pending)begin
     if(read_data!==expected)begin
      error_seen<=1;if(errors!=12'hfff)errors<=errors+1'b1;
     end
     if(last_pending)frame_checked<=1;
    end
   end
  end
 end
 assign status={done_sync[1],frame_checked,underflow_seen,error_seen,errors};
endmodule
