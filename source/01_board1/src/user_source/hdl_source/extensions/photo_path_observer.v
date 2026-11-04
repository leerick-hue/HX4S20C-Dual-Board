`timescale 1ns/1ps
// Diagnostic only. Frame reports are held until the next frame (>=16ms).
// The destination captures that held bus after a two-flop event synchronizer.
module photo_report_bridge #(parameter WIDTH=32)(
 input clk,rst,input toggle,input[WIDTH-1:0]held,
 output reg[WIDTH-1:0]report,output reg valid);
 (* ASYNC_REG="TRUE" *)reg[1:0]event_sync;
 reg seen;
 always @(posedge clk or posedge rst)
  if(rst)begin event_sync<=0;seen<=0;report<=0;valid<=0;end
  else begin
   event_sync<={event_sync[0],toggle};
   if(event_sync[1]!=seen)begin report<=held;seen<=event_sync[1];valid<=1;end
  end
endmodule

module photo_path_observer #(parameter FRAME_WORDS=460800,PIXEL_HZ=74250000)(
 input ref_clk,ref_rst,next_page,input[23:0]base_code,
 input write_clk,write_rst,write_req,write_finish_toggle,
 input pixel_accept,input[10:0]source_width,source_height,
 input word_accept,input[20:0]word_addr,input[31:0]word_data,
 input read_clk,read_rst,read_req,word_read,word_empty,input[31:0]read_data,
 input acr_in,acr_ack,pcm_in,pcm_out,acr_wait,input[15:0]overflow_count,
 input[19:0]acr_n,acr_cts,
 output reg[23:0]display_code,output reg[4:0]page);
 reg[19:0]pixels,words;
 reg[15:0]wlo,whi,whigh_delta;reg wcarry_pending;
 wire[31:0]write_mix=word_data^{word_addr[15:0],word_addr[20:5]};
 wire[16:0]wladd={1'b0,wlo}+{1'b0,write_mix[15:0]};
 (* ASYNC_REG="TRUE" *)reg[2:0]finish_sync;
 reg finish_seen,w_toggle;
 reg[93:0]wheld;
 always @(posedge write_clk or posedge write_rst)begin
  if(write_rst)begin
   pixels<=0;words<=0;wlo<=0;whi<=0;whigh_delta<=0;wcarry_pending<=0;
   finish_sync<=0;finish_seen<=0;w_toggle<=0;wheld<=0;
  end else begin
   finish_sync<={finish_sync[1:0],write_finish_toggle};
   finish_seen<=finish_sync[2];
   wcarry_pending<=word_accept;
   if(write_req)begin pixels<=0;words<=0;wlo<=0;whi<=0;wcarry_pending<=0;end
   else begin
    if(pixel_accept)pixels<=pixels+1'b1;
    if(word_accept)begin words<=words+1'b1;wlo<=wladd[15:0];whigh_delta<=write_mix[31:16]+wladd[16];end
    if(wcarry_pending)whi<=whi+whigh_delta;
   end
   // Controller completion follows draining the final write burst, long
   // after the two-cycle diagnostic sum pipeline has settled.
   if(finish_sync[2]!=finish_seen)begin
    wheld<={source_width,source_height,pixels,words,whi,wlo};w_toggle<=!w_toggle;
   end
  end
 end
 reg[19:0]read_words;
 reg pending,rfinish0,rfinish1,r_toggle;
 reg[15:0]rlo,rhi,rhigh_delta;reg rcarry_pending;
 reg[51:0]rheld;
 wire[20:0]read_index={1'b0,read_words};
 wire[31:0]read_mix=read_data^{read_index[15:0],read_index[20:5]};
 wire[16:0]rladd={1'b0,rlo}+{1'b0,read_mix[15:0]};
 always @(posedge read_clk or posedge read_rst)begin
  if(read_rst)begin
   read_words<=0;pending<=0;rfinish0<=0;rfinish1<=0;r_toggle<=0;rheld<=0;
   rlo<=0;rhi<=0;rhigh_delta<=0;rcarry_pending<=0;
  end else begin
   pending<=word_read && !word_empty;
   rcarry_pending<=pending;rfinish0<=0;rfinish1<=rfinish0;
   if(read_req)begin
    read_words<=0;pending<=0;rlo<=0;rhi<=0;rcarry_pending<=0;rfinish0<=0;rfinish1<=0;
   end else begin
    // The actual read FIFO data arrives one clock after word_read, exactly
    // as consumed by the existing, physically accepted memory BIST.
    if(pending)begin
     read_words<=read_words+1'b1;rlo<=rladd[15:0];rhigh_delta<=read_mix[31:16]+rladd[16];
     if(read_words==FRAME_WORDS-1)rfinish0<=1;
    end
    if(rcarry_pending)rhi<=rhi+rhigh_delta;
    if(rfinish1)begin rheld<={read_words,rhi,rlo};r_toggle<=!r_toggle;end
   end
  end
 end
 localparam MS_CYCLES=PIXEL_HZ/1000;
 localparam MS_BITS=MS_CYCLES>1?$clog2(MS_CYCLES):1;
 reg[MS_BITS-1:0]ms_div;reg[9:0]milliseconds;
 reg[15:0]ai,ao,pi,po,wait_cycles,max_wait;
 reg[19:0]last_n,last_cts;
 reg a_toggle;reg[135:0]aheld;
 wire ms_tick=ms_div==MS_CYCLES-1;
 wire second_tick=ms_tick && milliseconds==999;
 wire[15:0]wait_next=!acr_wait ? 16'd0 : (wait_cycles==16'hffff ? wait_cycles : wait_cycles+1'b1);
 wire[15:0]max_next=wait_next>max_wait?wait_next:max_wait;
 wire[15:0]ai_next=ai+acr_in,ao_next=ao+acr_ack,pi_next=pi+pcm_in,po_next=po+pcm_out;
 always @(posedge read_clk or posedge read_rst)begin
  if(read_rst)begin
   ms_div<=0;milliseconds<=0;ai<=0;ao<=0;pi<=0;po<=0;wait_cycles<=0;max_wait<=0;
   last_n<=0;last_cts<=0;a_toggle<=0;aheld<=0;
  end else begin
   if(ms_tick)begin ms_div<=0;if(milliseconds==999)milliseconds<=0;else milliseconds<=milliseconds+1'b1;end
   else ms_div<=ms_div+1'b1;
   wait_cycles<=wait_next;max_wait<=max_next;
   if(acr_in)begin last_n<=acr_n;last_cts<=acr_cts;end
   if(second_tick)begin
    aheld<={ai_next,ao_next,pi_next,po_next,overflow_count,max_next,last_n,last_cts};
    a_toggle<=!a_toggle;ai<=0;ao<=0;pi<=0;po<=0;max_wait<=0;
   end else begin
    if(acr_in)ai<=ai+1'b1;if(acr_ack)ao<=ao+1'b1;
    if(pcm_in)pi<=pi+1'b1;if(pcm_out)po<=po+1'b1;
   end
  end
 end
 wire[93:0]wr;wire[51:0]rr;wire[135:0]ar;wire wvalid,rvalid,avalid;
 photo_report_bridge #(.WIDTH(94))write_bridge(ref_clk,ref_rst,w_toggle,wheld,wr,wvalid);
 photo_report_bridge #(.WIDTH(52))read_bridge(ref_clk,ref_rst,r_toggle,rheld,rr,rvalid);
 photo_report_bridge #(.WIDTH(136))audio_bridge(ref_clk,ref_rst,a_toggle,aheld,ar,avalid);
 always @(posedge ref_clk or posedge ref_rst)
  if(ref_rst)page<=0;else if(next_page)page<=page==5'h17 ? 5'd0 : page+1'b1;
 reg[15:0]value;
 always @*begin
  case(page)
   1:value={5'd0,wr[93:83]};2:value={5'd0,wr[82:72]};
   3:value=wr[67:52];4:value={12'd0,wr[71:68]};
   5:value=wr[47:32];6:value={12'd0,wr[51:48]};
   7:value=wr[15:0];8:value=wr[31:16];
   9:value=rr[47:32];10:value={12'd0,rr[51:48]};
   11:value=rr[15:0];12:value=rr[31:16];
   13:value=ar[135:120];14:value=ar[119:104];15:value=ar[103:88];
   16:value=ar[87:72];17:value=ar[71:56];18:value=ar[55:40];
   19:value={13'd0,avalid,rvalid,wvalid};
   20:value=ar[35:20];21:value={12'd0,ar[39:36]};
   22:value=ar[15:0];23:value={12'd0,ar[19:16]};
   default:value=0;
  endcase
  display_code=page==0?base_code:{3'd0,page,value};
 end
endmodule
