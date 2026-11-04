`timescale 1ns/1ps
module tb_replicator_contract;
 reg clk=0,rst=1,aspect=0,start=0,iv=0,ready=0;
 always #12.5 clk=~clk;
 reg[8:0]row=0,col=0;reg[31:0]data=0;
 wire ir,ov;wire[20:0]addr;wire[31:0]out;
 word_replicator dut(.clk(clk),.rst(rst),.aspect_16x9(aspect),.frame_start(start),
 .src_valid(iv),.src_ready(ir),.src_row(row),.src_word(col),.src_data(data),
 .out_valid(ov),.out_ready(ready),.out_addr(addr),.out_data(out));
 integer total=0,in_group=0,out_group=0,nrows=3;
 integer base_row,base_col;reg[31:0]expected[0:3];
 reg stalled=0;reg[52:0]held;
 function automatic[31:0]pattern(input integer y,x);
  pattern={16'(y*173+x*317),16'(y*911+x*127+51)};
 endfunction
 always @(negedge clk)ready=$urandom_range(0,3)!=0;
 always @(posedge clk)if(!rst)begin
  if(start)begin in_group=0;out_group=0;stalled=0;end
  else begin
   if(stalled && (!ov || {addr,out}!==held))$fatal(1,"changed stalled word");
   stalled=ov&&!ready;held={addr,out};
   if(iv&&ir)begin
    if(in_group==0)begin base_row=row;base_col=col;nrows=aspect?4:3;end
    if(row!=base_row || col!=base_col+in_group)$fatal(1,"bad test source group");
    expected[in_group]=data;in_group=in_group+1;
   end
   if(ov&&ready)begin
    if(in_group!=4)$fatal(1,"emitted before fourth source word");
    if(addr!==(base_row*nrows+out_group/4)*160+base_col+out_group%4 || out!==expected[out_group%4])
     $fatal(1,"wrong BL4 output n=%0d addr=%0d data=%h",out_group,addr,out);
    if(out_group%4==0 && addr[1:0]!=0)$fatal(1,"unaligned group");
    out_group=out_group+1;total=total+1;
    if(out_group==nrows*4)begin out_group=0;in_group=0;end
   end
  end
 end
 task send(input integer y,x);
  begin
   repeat($urandom_range(0,2))@(negedge clk);
   row=y;col=x;data=pattern(y,x);iv=1;
   do @(posedge clk);while(!ir);
   @(negedge clk);iv=0;
  end
 endtask
 initial begin
  repeat(10)@(negedge clk);rst=0;
  // Throw away a partial group on a fresh frame.
  send(1,0);send(1,1);start=1;@(negedge clk);start=0;
  for(integer mode=0;mode<2;mode=mode+1)begin
   aspect=mode;
   for(integer y=0;y<(mode?180:240);y=y+1)
    for(integer x=0;x<160;x=x+1)send(y,x);
   wait(!ov && ir && in_group==0);repeat(5)@(negedge clk);
  end
  if(total!=230400)$fatal(1,"lost tail group total=%0d",total);
  $display("PASS replicator_contract 230400 output_words both_aspects random_input_and_output_stalls partial_group_frame_reset adjacent_words_differ");$finish;
 end
 initial begin #100000000;$fatal(1,"replicator timeout");end
endmodule
