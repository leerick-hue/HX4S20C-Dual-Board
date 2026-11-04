`timescale 1ns/1ps
module tb_agc;
 reg clk=0,rst_n=0,valid=0,active=0;reg signed[23:0]sample=0;
 wire pv,bv;wire signed[15:0]pcm,reference_pcm,baseline;
 wire[2:0]gain;wire[31:0]clips;
 always #10 clk=~clk;
 mic_pcm_conditioner #(.AGC_ENABLE(1)) dut(.clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample24(sample),
  .speech_active(active),.pcm_valid(pv),.pcm_sample(pcm),.reference_pcm(reference_pcm),.agc_gain(gain),.clip_count(clips));
 mic_pcm_conditioner legacy(.clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample24(sample),
  .speech_active(1'b0),.pcm_valid(bv),.pcm_sample(baseline),.reference_pcm(),.agc_gain(),.clip_count());
 integer n=0,measure=0;longint sum=0,bsum=0,normal_sum,weak_sum,weak_base;
 always @(negedge clk)if(rst_n)begin
  if(pv!==bv || (pv && reference_pcm!==baseline))$fatal(1,"VAD reference changed by AGC");
  if(pv&&measure)begin sum=sum+(pcm<0?-integer'(pcm):integer'(pcm));bsum=bsum+(baseline<0?-integer'(baseline):integer'(baseline));end
 end
 task send(input integer value);begin @(negedge clk);sample=value;valid=1;@(negedge clk);valid=0;repeat(5)@(negedge clk);end endtask
 task block(input integer amplitude,count);
  begin for(integer i=0;i<count;i=i+1)begin send(((n%40)<20?amplitude:-amplitude)+20000);n=n+1;end end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  block(128,2048);block(262144,2048);sum=0;bsum=0;measure=1;block(262144,1024);measure=0;normal_sum=sum;
  block(128,2048);block(16384,2048);sum=0;bsum=0;measure=1;block(16384,1024);measure=0;weak_sum=sum;weak_base=bsum;
  if(weak_sum<weak_base*8 || weak_sum<normal_sum/4 || weak_sum>normal_sum*4)$fatal(1,"gain range inadequate normal=%0d weak=%0d base=%0d",normal_sum,weak_sum,weak_base);
  active=1;block(7000000,1024);if(gain>1)$fatal(1,"loud attack did not reduce gain");
  active=0;block(128,2048);if(gain!=1)$fatal(1,"silence did not restore base gain");
  $display("LEVEL normal=%0d weak=%0d weak_fixed=%0d clips=%0d",normal_sum,weak_sum,weak_base,clips);
  $display("PASS tb_agc fixed_reference_exact weak_signal_gain loud_attack quiet_gain_reset");$finish;
 end
 initial begin #100000000;$fatal(1,"AGC timeout");end
endmodule
