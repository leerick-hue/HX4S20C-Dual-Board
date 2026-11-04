`timescale 1ns/1ps
`include "sim/voice_data/voice_counts.vh"
module tb_voice_replay;
 reg clk=0,rst_n=0,iv=0;reg signed[23:0]raw=0;reg[1:0]train=0;
 always #10 clk=~clk;
 wire pv,bv;wire signed[15:0]pcm,reference_pcm,base_pcm;
 wire rec,brec,cmd,bcmd,td,btd,res,bres,accepted,baccepted;
 wire[15:0]id,bid,score,second,bscore,bsecond;wire[31:0]clips,overruns,boverruns;
 wire[2:0]mask,bmask,gain;
 mic_pcm_conditioner #(.AGC_ENABLE(1)) agc(.clk(clk),.rst_n(rst_n),.sample_valid(iv),.sample24(raw),.speech_active(rec),
  .pcm_valid(pv),.pcm_sample(pcm),.reference_pcm(reference_pcm),.agc_gain(gain),.clip_count(clips));
 mic_pcm_conditioner original(.clk(clk),.rst_n(rst_n),.sample_valid(iv),.sample24(raw),.speech_active(1'b0),
  .pcm_valid(bv),.pcm_sample(base_pcm),.reference_pcm(),.agc_gain(),.clip_count());
 speech_command_core #(.END_SILENCE(20),.MAX_FRAMES(240),.RELEASE_FACTOR(2),.DROP_SILENCE(1),.PREFIX_FRAMES(24),.VERIFY_FULL(1),.ROBUST(1)) dut(
  .clk(clk),.rst_n(rst_n),.pcm_valid(pv),.pcm_sample(pcm),.reference_pcm(reference_pcm),.clip_count(clips),.train_request(train),
  .command_valid(cmd),.command_ready(1'b1),.command_id(id),.template_mask(mask),.train_done(td),.result_valid(res),.accepted(accepted),
  .best_score(score),.second_score(second),.feature_overruns(overruns),.reject_count(),.abort_count(),.calibrated(),.recording(rec),
  .noise_level(),.level(),.feature_valid_debug(),.feature_debug());
 speech_command_core #(.END_SILENCE(20),.MAX_FRAMES(240),.RELEASE_FACTOR(2),.DROP_SILENCE(1),.PREFIX_FRAMES(24),.VERIFY_FULL(1)) baseline(
  .clk(clk),.rst_n(rst_n),.pcm_valid(bv),.pcm_sample(base_pcm),.reference_pcm(16'sd0),.clip_count(32'd0),.train_request(train),
  .command_valid(bcmd),.command_ready(1'b1),.command_id(bid),.template_mask(bmask),.train_done(btd),.result_valid(bres),.accepted(baccepted),
  .best_score(bscore),.second_score(bsecond),.feature_overruns(boverruns),.reject_count(),.abort_count(),.calibrated(),.recording(brec),
  .noise_level(),.level(),.feature_valid_debug(),.feature_debug());
 reg[23:0]samples[0:`RAW_COUNT-1];reg[71:0]cases[0:`CASE_COUNT-1];
 integer pos=0,current=-1,new_count=0,old_count=0,new_id=0,old_id=0;
 integer trained=0,btrained=0,expected,divisor,training;
 integer correct[0:3],old_correct[0:3],total[0:3],bucket,negative=0;
 always @(posedge clk)if(rst_n)begin
  if(overruns!=0 || boverruns!=0)$fatal(1,"feature overrun");
  if(td)trained=trained+1;if(btd)btrained=btrained+1;
  if(cmd)begin new_count=new_count+1;new_id=id;end
  if(bcmd)begin old_count=old_count+1;old_id=bid;end
 end
 task send(input [23:0]value);
  begin
   @(negedge clk);raw=value;iv=1;
   @(negedge clk);iv=0;repeat(94)@(negedge clk);
   pos=pos+1;
   // Preserve real feature arithmetic while accelerating idle sample spacing.
   // Frame-end processing and DTW have explicit time to finish.
   if(pos%256==0)repeat(1024)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("sim/voice_data/voice_raw.hex",samples);$readmemh("sim/voice_data/voice_cases.hex",cases);
  for(integer k=0;k<4;k=k+1)begin correct[k]=0;old_correct[k]=0;total[k]=0;end
  repeat(10)@(negedge clk);rst_n=1;
  repeat(`INITIAL_SAMPLES)send(samples[pos]);
  for(current=0;current<`CASE_COUNT;current=current+1)begin
   training=cases[current][65:64];expected=cases[current][63:56];divisor=cases[current][55:48];
   new_count=0;old_count=0;new_id=0;old_id=0;
   @(negedge clk);train=training;@(negedge clk);train=0;
   repeat(cases[current][31:0])send(samples[pos]);
   repeat(100000)@(negedge clk);
   if(training!=0)begin
    if(trained!=current+1 || btrained!=current+1)$fatal(1,"enrollment failed new=%0d old=%0d case=%0d",trained,btrained,current);
    $display("TRAIN case=%0d masks=%b/%b",current,mask,bmask);
   end else begin
    $display("RESULT case=%0d expected=%0d divide=%0d new_id=%0d new_n=%0d old_id=%0d old_n=%0d score=%0d second=%0d",current,expected,divisor,new_id,new_count,old_id,old_count,score,second);
    if(new_count>1 || (new_count==1 && new_id!=expected))$fatal(1,"false or duplicate command");
    if(expected==0)begin if(new_count!=0)$fatal(1,"negative accepted");negative=negative+1;end
    else begin
     bucket=divisor==1?0:divisor==4?1:divisor==16?2:3;
     total[bucket]=total[bucket]+1;
     if(new_count==1 && new_id==expected)correct[bucket]=correct[bucket]+1;
     if(old_count==1 && old_id==expected)old_correct[bucket]=old_correct[bucket]+1;
    end
   end
  end
  for(integer k=0;k<4;k=k+1)$display("LEVEL bucket=%0d new=%0d old=%0d total=%0d",k,correct[k],old_correct[k],total[k]);
  if(correct[0]!=6 || correct[1]!=6 || correct[2]!=6 || correct[3]+correct[2]<=old_correct[3]+old_correct[2] || negative!=4)$fatal(1,"robustness acceptance not met");
  $display("PASS tb_voice_replay actual_development_recordings distinct_enrollment_tests digital_level_variation not_physical_distance negative_cases=4");$finish;
 end
 initial begin #(64'd12000000000);$fatal(1,"voice replay timeout case=%0d pos=%0d",current,pos);end
endmodule
