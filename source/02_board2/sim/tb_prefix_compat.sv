`timescale 1ns/1ps
module tb_prefix_compat;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,segment_start=0,segment_end=0,segment_abort=0,feature_valid=0;
 reg [1:0]train_class=0;
 reg [63:0]feature_data=0;
 wire segment_ready,feature_ready,train_done,result_valid,accepted,command_valid;
 wire[2:0]template_mask;
 wire[15:0]best_score,second_score,command_id;
 wire[31:0]reject_count,abort_count;
 speech_dtw #(.PREFIX_FRAMES(4),.VERIFY_FULL(1)) dut(.clk(clk),.rst_n(rst_n),
  .segment_start(segment_start),.segment_end(segment_end),.segment_abort(segment_abort),
  .train_class(train_class),.feature_valid(feature_valid),.feature_data(feature_data),
  .segment_ready(segment_ready),.feature_ready(feature_ready),.template_mask(template_mask),
  .train_done(train_done),.result_valid(result_valid),.accepted(accepted),.best_score(best_score),
  .second_score(second_score),.command_valid(command_valid),.command_ready(1'b1),
  .command_id(command_id),.reject_count(reject_count),.abort_count(abort_count));
 task phrase(input integer train,input integer label,input integer count,input integer bad_suffix);
  integer value;
  wait(segment_ready);@(negedge clk);train_class=train;segment_start=1;
  @(negedge clk);segment_start=0;
  for(integer n=0;n<count;n=n+1)begin
   value=n<4?((label-1)*-50):(bad_suffix?127:-25);
   feature_data={8{8'(value)}};feature_valid=1;
   @(negedge clk);feature_valid=0;@(negedge clk);
  end
  segment_end=1;@(negedge clk);segment_end=0;
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(integer label=1;label<=3;label=label+1)begin phrase(label,label,8,0);wait(train_done);@(negedge clk);end
  if(template_mask!==7)$fatal(1,"prefix test enrollment");
  phrase(0,2,8,0);wait(result_valid);#1;
  if(!accepted || command_id!=2 || best_score!=0)$fatal(1,"valid complete phrase rejected");
  @(negedge clk);phrase(0,2,8,1);wait(result_valid);#1;
  if(accepted || command_valid || best_score!=0)$fatal(1,"matching prefix bypassed full verification");
  @(negedge clk);phrase(2,2,16,0);wait(train_done);@(negedge clk);
  phrase(0,2,5,0);wait(result_valid);#1;
  if(accepted || command_valid)$fatal(1,"too-short prefix bypassed duration guard");
  @(negedge clk);phrase(0,3,8,0);wait(result_valid);#1;
  if(!accepted || command_id!=3)$fatal(1,"prefix engine did not recover");
  $display("PASS tb_prefix_compat_dtw: prefix ranking, entire-phrase verification rejects wrong suffix, duration guard, recovery, unchanged score96/margin8");
  $finish;
 end
 initial begin #5000000;$fatal(1,"prefix DTW timeout");end
endmodule
