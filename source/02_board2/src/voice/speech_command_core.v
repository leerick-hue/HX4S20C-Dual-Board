`timescale 1ns/1ps
// First 32 quiet frames calibrate the noise floor. Buttons arm template1/2/3.
module speech_command_core #(parameter CAL_FRAMES=32,END_SILENCE=10,MIN_VOICED=4,MAX_FRAMES=128,MAX_SCORE=96,MIN_MARGIN=8,RECOVERY_FRAMES=128,
 RELEASE_FACTOR=4,DROP_SILENCE=0,PREFIX_FRAMES=0,VERIFY_FULL=0,ROBUST=0)(
 input clk,input rst_n,input pcm_valid,input signed[15:0]pcm_sample,input[1:0]train_request,
 input signed[15:0]reference_pcm,input[31:0]clip_count,
 output command_valid,input command_ready,output[15:0]command_id,
 output[2:0]template_mask,output train_done,output result_valid,output accepted,
 output[15:0]best_score,second_score,output[31:0]feature_overruns,reject_count,abort_count,
 output calibrated,output recording,output[15:0]noise_level,output[15:0]level,
 output feature_valid_debug,output[63:0]feature_debug);
 wire fv;wire[63:0]features;wire[15:0]feature_energy;
 reg[7:0] energy_index;reg[23:0] energy_sum;reg[15:0] raw_energy;
 wire[15:0] reference_abs=reference_pcm[15]?-reference_pcm:reference_pcm;
 wire[15:0]energy=ROBUST?raw_energy:feature_energy;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin energy_index<=0;energy_sum<=0;raw_energy<=0;end
  else if(pcm_valid)begin
   energy_index<=energy_index+1'b1;
   if(energy_index==255)begin raw_energy<=(energy_sum+reference_abs)>>8;energy_sum<=0;end
   else energy_sum<=energy_sum+reference_abs;
  end
 end
 speech_features extract(.clk(clk),.rst_n(rst_n),.pcm_valid(pcm_valid),.pcm_sample(pcm_sample),
  .feature_valid(fv),.feature_data(features),.frame_energy(feature_energy),.overrun_count(feature_overruns));
 assign feature_valid_debug=fv;assign feature_debug=features;assign level=energy;
 reg start_seg,end_seg,abort_seg,push_feature;reg[63:0]push_data;reg[1:0]training,pending_train;
 wire segment_ready,feature_ready;
 speech_dtw #(.MAX_FRAMES(MAX_FRAMES),.MAX_SCORE(MAX_SCORE),.MIN_MARGIN(MIN_MARGIN),
  .PREFIX_FRAMES(PREFIX_FRAMES),.VERIFY_FULL(VERIFY_FULL),.ROBUST_RANK(ROBUST)) matcher(
  .clk(clk),.rst_n(rst_n),.segment_start(start_seg),.segment_end(end_seg),.segment_abort(abort_seg),
  .train_class(training),.feature_valid(push_feature),.feature_data(push_data),
  .segment_ready(segment_ready),.feature_ready(feature_ready),.template_mask(template_mask),.train_done(train_done),
  .result_valid(result_valid),.accepted(accepted),.best_score(best_score),.second_score(second_score),
  .command_valid(command_valid),.command_ready(command_ready),.command_id(command_id),.reject_count(reject_count),.abort_count(abort_count));
 reg[1:0]vad_state;
 reg[7:0]quiet_count,voiced_count,frame_count,cal_count;
 reg[15:0]recovery_count;
 reg[23:0]cal_sum;reg[15:0]noise;
 reg[31:0]previous_overruns;
 wire[17:0]floor_start=ROBUST?18'd8:18'd64;
 wire[17:0]floor_release=ROBUST?18'd4:18'd32;
 wire[17:0]threshold={noise,2'b00}<floor_start?floor_start:{noise,2'b00};
 wire[17:0]release_threshold=RELEASE_FACTOR==2?({1'b0,noise,1'b0}<floor_release?floor_release:{1'b0,noise,1'b0}):threshold;
 reg signed[17:0]noise_delta;
 // Keep both addends signed: an unsigned noise operand makes >>> logical
 // inside the addition, turning a falling noise floor into a ~16384 jump.
 wire signed[18:0]updated_noise=$signed({1'b0,noise})+(noise_delta>>>4);
 assign calibrated=cal_count>=CAL_FRAMES;
 assign recording=vad_state==1 || vad_state==3;assign noise_level=noise;
 always @*noise_delta=$signed({1'b0,energy})-$signed({1'b0,noise});
 generate if(!ROBUST)begin:legacy_endpoint
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   start_seg<=0;end_seg<=0;abort_seg<=0;push_feature<=0;push_data<=0;training<=0;pending_train<=0;
   vad_state<=0;quiet_count<=0;voiced_count<=0;frame_count<=0;cal_count<=0;cal_sum<=0;noise<=16;previous_overruns<=0;recovery_count<=0;
  end else begin
   start_seg<=0;end_seg<=0;abort_seg<=0;push_feature<=0;
   if(train_done && pending_train==training)pending_train<=0;
   if(train_request!=0)pending_train<=train_request;
   previous_overruns<=feature_overruns;
   if(feature_overruns!=previous_overruns && vad_state==1)begin abort_seg<=1;vad_state<=2;quiet_count<=0;recovery_count<=0;end
   else if(fv)begin
    if(!calibrated)begin
     cal_sum<=cal_sum+energy;cal_count<=cal_count+1'b1;
     if(cal_count+1==CAL_FRAMES)noise<=(cal_sum+energy)/CAL_FRAMES;
    end else case(vad_state)
    0:begin
     if(energy<threshold/2)noise<=updated_noise[15:0];
     if(energy>threshold && segment_ready)begin
      training<=train_request!=0?train_request:pending_train;start_seg<=1;push_feature<=1;push_data<=features;
      vad_state<=1;voiced_count<=1;frame_count<=1;quiet_count<=0;
     end
    end
    1:begin
     push_feature<=!DROP_SILENCE || energy>release_threshold;
     push_data<=energy>release_threshold?features:64'd0;
     frame_count<=frame_count+1'b1;
     if(energy>threshold)voiced_count<=voiced_count+1'b1;
     if(energy>release_threshold)quiet_count<=0;
     else quiet_count<=quiet_count+1'b1;
     if(frame_count>=MAX_FRAMES-1)begin abort_seg<=1;push_feature<=0;vad_state<=2;quiet_count<=0;recovery_count<=0;end
     else if(energy<=release_threshold && quiet_count+1>=END_SILENCE)begin
      if(voiced_count<MIN_VOICED)begin abort_seg<=1;push_feature<=0;end else end_seg<=1;
      vad_state<=0;
     end
    end
    2:begin
       recovery_count<=recovery_count+1'b1;
       if(energy<=threshold)begin
        if(quiet_count+1>=END_SILENCE)begin vad_state<=0;quiet_count<=0;end else quiet_count<=quiet_count+1'b1;
       end else quiet_count<=0;
       // A persistent new noise floor must not lock VAD forever. Recalibrate
       // after two seconds while keeping the enrolled DTW templates intact.
       if(recovery_count+1>=RECOVERY_FRAMES)begin
        cal_count<=0;cal_sum<=0;vad_state<=0;quiet_count<=0;recovery_count<=0;
       end
      end
    default:vad_state<=0;
    endcase
   end
  end
 end
 end else begin:robust_endpoint
 reg [1:0] onset_count;
 reg replay_start;
 wire replay_valid,replay_busy,replay_overrun;
 wire [95:0] replay_data;
 wire onset_hit=energy>{noise,2'b00} && feature_energy>64;
 wire release_hit=energy>{1'b0,noise,1'b0} && feature_energy>32;
 wire replay_ready=vad_state==3 && feature_ready;
 reg [31:0] clip_start;
 wire [31:0] segment_clips=clip_count-clip_start;
 voice_feature_preroll #(.DATA_BITS(96)) history(.clk(clk),.rst_n(rst_n),.clear(abort_seg || end_seg || !calibrated),
  .frame_valid(fv && calibrated && vad_state==0 && segment_ready),
  .frame_data({energy,feature_energy,features}),.replay_start(replay_start),
  .replay_ready(replay_ready),.replay_valid(replay_valid),.replay_data(replay_data),
  .busy(replay_busy),.overrun(replay_overrun));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   start_seg<=0;end_seg<=0;abort_seg<=0;push_feature<=0;push_data<=0;
   training<=0;pending_train<=0;vad_state<=0;quiet_count<=0;voiced_count<=0;
   frame_count<=0;cal_count<=0;cal_sum<=0;noise<=16;previous_overruns<=0;
   recovery_count<=0;onset_count<=0;replay_start<=0;clip_start<=0;
  end else begin
   start_seg<=0;end_seg<=0;abort_seg<=0;push_feature<=0;replay_start<=0;
   if(train_done && pending_train==training)pending_train<=0;
   if(train_request!=0)pending_train<=train_request;
   previous_overruns<=feature_overruns;
   if((feature_overruns!=previous_overruns || replay_overrun) && (vad_state==1 || vad_state==3))begin
    abort_seg<=1;vad_state<=2;quiet_count<=0;recovery_count<=0;
   end else if(vad_state==3)begin
    if(replay_valid && replay_ready && replay_data[95:80]>{1'b0,noise,1'b0} && replay_data[79:64]>32)begin
     push_feature<=1;push_data<=replay_data[63:0];frame_count<=frame_count+1'b1;
     if(replay_data[95:80]>{noise,2'b00} && replay_data[79:64]>64)voiced_count<=voiced_count+1'b1;
    end
    if(!replay_busy && !replay_start)vad_state<=1;
   end else if(fv)begin
    if(!calibrated)begin
     cal_sum<=cal_sum+energy;cal_count<=cal_count+1'b1;
     if(cal_count+1==CAL_FRAMES)noise<=(cal_sum+energy)/CAL_FRAMES;
    end else case(vad_state)
    0:begin
     if(energy<threshold/2)noise<=updated_noise[15:0];
     if(onset_hit && segment_ready)begin
      if(onset_count==1)begin
       training<=train_request!=0?train_request:pending_train;
       start_seg<=1;replay_start<=1;vad_state<=3;
       onset_count<=0;voiced_count<=0;frame_count<=0;quiet_count<=0;clip_start<=clip_count;
      end else onset_count<=onset_count+1'b1;
     end else onset_count<=0;
    end
    1:begin
     push_feature<=release_hit;push_data<=features;
     frame_count<=frame_count+1'b1;
     if(onset_hit)voiced_count<=voiced_count+1'b1;
     if(release_hit)quiet_count<=0;else quiet_count<=quiet_count+1'b1;
     if(frame_count>=MAX_FRAMES-1)begin
      abort_seg<=1;push_feature<=0;vad_state<=2;quiet_count<=0;recovery_count<=0;
     end else if(!release_hit && quiet_count+1>=END_SILENCE)begin
      if(voiced_count<MIN_VOICED || segment_clips>{23'd0,frame_count,1'b0})begin
       abort_seg<=1;push_feature<=0;
      end else end_seg<=1;
      vad_state<=0;onset_count<=0;
     end
    end
    2:begin
     recovery_count<=recovery_count+1'b1;
     if(energy<=threshold)begin
      if(quiet_count+1>=END_SILENCE)begin vad_state<=0;quiet_count<=0;end
      else quiet_count<=quiet_count+1'b1;
     end else quiet_count<=0;
     if(recovery_count+1>=RECOVERY_FRAMES)begin
      cal_count<=0;cal_sum<=0;vad_state<=0;quiet_count<=0;recovery_count<=0;onset_count<=0;
     end
    end
    default:vad_state<=0;
    endcase
   end
  end
 end
 end endgenerate
endmodule
