`timescale 1ns/1ps
// Endpoint-only fault injection: feature pulses are driven explicitly. Actual
// signal extraction and recognition are covered by the separate PCM replay.
module tb_endpoint_robust;
 reg clk=0,rst_n=0,fv=0;always #10 clk=~clk;
 reg[15:0]energy=0,amplified=0;reg[63:0]tag=0;reg[1:0]train=0;reg[31:0]clips=0;
 wire recording,done,command;wire[2:0]mask;integer trained=0;
 speech_command_core #(.CAL_FRAMES(4),.END_SILENCE(3),.MAX_FRAMES(32),.MIN_VOICED(4),
  .RELEASE_FACTOR(2),.DROP_SILENCE(1),.PREFIX_FRAMES(4),.VERIFY_FULL(1),.ROBUST(1)) dut(
  .clk(clk),.rst_n(rst_n),.pcm_valid(1'b0),.pcm_sample(16'sd0),.reference_pcm(16'sd0),.clip_count(clips),
  .train_request(train),.command_valid(command),.command_ready(1'b1),.command_id(),.template_mask(mask),.train_done(done),
  .result_valid(),.accepted(),.best_score(),.second_score(),.feature_overruns(),.reject_count(),.abort_count(),
  .calibrated(),.recording(recording),.noise_level(),.level(),.feature_valid_debug(),.feature_debug());
 initial begin force dut.fv=fv;force dut.features=tag;force dut.raw_energy=energy;force dut.feature_energy=amplified;end
 always @(posedge clk)if(rst_n)begin if(done)trained=trained+1;if(command)$fatal(1,"unit emitted command");end
 task frame(input integer raw_level,post_level,number);
  begin
   @(negedge clk);energy=raw_level;amplified=post_level;tag=number;fv=1;
   @(negedge clk);fv=0;repeat(126)@(negedge clk);
  end
 endtask
 task arm(input integer n);begin @(negedge clk);train=n;@(negedge clk);train=0;end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(4)frame(0,0,0);
  arm(1);
  for(integer n=1;n<=4;n=n+1)frame(2,50,n); // recover initial weak sounds
  frame(20,100,5);if(recording)$fatal(1,"one-frame onset accepted");
  frame(20,100,6);for(integer n=7;n<=10;n=n+1)frame(20,100,n);
  repeat(3)frame(0,0,0);repeat(1000)@(negedge clk);
  if(trained!=1 || mask!=1 || dut.matcher.template_length[0]!=10 || dut.matcher.templates[0]!==64'd1)
   $fatal(1,"weak prefix lost trained=%0d len=%0d first=%h",trained,dut.matcher.template_length[0],dut.matcher.templates[0]);
  frame(20,100,77);repeat(5)frame(0,0,0);if(recording)$fatal(1,"click latched recording");
  arm(2);frame(20,100,1);frame(20,100,2);
  for(integer n=3;n<=8;n=n+1)begin clips=clips+100;frame(20,100,n);end
  repeat(3)frame(0,0,0);repeat(1000)@(negedge clk);
  if(trained!=1 || mask!=1)$fatal(1,"clipped enrollment accepted");
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  repeat(4)frame(30,1000,0);repeat(20)frame(30,1000,0);
  if(recording || dut.vad_state!=0)$fatal(1,"amplified background triggered VAD");
  $display("PASS tb_endpoint_robust forced_feature_unit weak_prefix_preserved two_frame_onset clipped_enrollment_rejected raw_noise_ratio_not_AGC_level");$finish;
 end
 initial begin #10000000;$fatal(1,"endpoint timeout");end
endmodule
