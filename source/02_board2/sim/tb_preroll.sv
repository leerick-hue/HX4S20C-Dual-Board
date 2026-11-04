`timescale 1ns/1ps
module tb_preroll;
 reg clk=0,rst_n=0,clear=0,fv=0,start=0,ready=0;
 reg[79:0]data=0;wire[79:0]out;wire valid,busy,overrun;
 always #10 clk=~clk;
 voice_feature_preroll dut(.clk(clk),.rst_n(rst_n),.clear(clear),.frame_valid(fv),.frame_data(data),
  .replay_start(start),.replay_ready(ready),.replay_valid(valid),.replay_data(out),.busy(busy),.overrun(overrun));
 integer expected=4,received=0;reg stalled=0;reg[79:0]held;
 always @(negedge clk)ready=$urandom_range(0,3)!=0;
 always @(posedge clk)if(rst_n && !clear)begin
  if(stalled && (!valid || out!==held))$fatal(1,"stalled replay changed");
  stalled=valid&&!ready;held=out;
  if(valid&&ready)begin
   if(out!==80'(expected))$fatal(1,"oldest order got=%d expected=%d",out,expected);
   expected=expected+1;received=received+1;
  end
 end else stalled=0;
 task push(input integer n);begin @(negedge clk);data=n;fv=1;@(negedge clk);fv=0;end endtask
 task replay;begin @(negedge clk);start=1;@(negedge clk);start=0;wait(!busy);repeat(5)@(negedge clk);end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(integer n=0;n<12;n=n+1)push(n);
  replay();if(received!=8)$fatal(1,"missing replay tail");
  clear=1;@(negedge clk);clear=0;expected=100;
  push(100);push(101);replay();if(received!=10)$fatal(1,"clear leaked old history");
  expected=100;@(negedge clk);start=1;@(negedge clk);start=0;wait(busy);
  push(999);wait(!busy);if(!overrun)$fatal(1,"busy write not reported");
  // Reset while a replay is waiting, then prove that no stale word is emitted.
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  repeat(10)@(negedge clk);if(valid||busy||overrun)$fatal(1,"clear failed");
  $display("PASS tb_preroll chronological_wrap random_backpressure clear busy_overrun");$finish;
 end
 initial begin #1000000;$fatal(1,"preroll timeout");end
endmodule
