`timescale 1ns/1ps
// DC removal with optional bounded gain BEFORE PCM16 quantization.
// reference_pcm retains fixed-gain levels for VAD and diagnostic UART, so
// adaptation cannot raise the VAD noise floor by changing its own gain.
module mic_pcm_conditioner #(
 parameter integer GAIN_SHIFT=1, DC_SHIFT=5, AGC_ENABLE=0,
 parameter integer MAX_GAIN_SHIFT=6
)(
 input wire clk,rst_n,sample_valid,
 input wire signed [23:0] sample24,
 input wire speech_active,
 output reg pcm_valid,
 output reg signed [15:0] pcm_sample,
 output reg signed [15:0] reference_pcm,
 output wire [2:0] agc_gain,
 output reg [31:0] clip_count
);
 reg primed;
 reg signed [39:0] dc_q;
 wire signed [39:0] input_q={sample24,16'b0};
 wire signed [40:0] difference=$signed({input_q[39],input_q})-$signed({dc_q[39],dc_q});
 wire signed [40:0] next_dc=$signed({dc_q[39],dc_q})+(difference >>> DC_SHIFT);
 wire signed [40:0] fixed_scaled=difference >>> (24-GAIN_SHIFT);
 wire signed [24:0] raw_difference=difference >>> 16;
 wire [24:0] magnitude=raw_difference[24]?-raw_difference:raw_difference;
 reg [7:0] sample_index;
 reg [24:0] peak,noise_peak;
 reg [2:0] gain_level;
 wire [24:0] frame_peak=magnitude>peak?magnitude:peak;
 wire signed [26:0] noise_delta=$signed({2'b0,frame_peak})-$signed({2'b0,noise_peak});
 wire signed [26:0] next_noise=$signed({2'b0,noise_peak})+(noise_delta >>> 4);
 wire [26:0] triple_noise={1'b0,noise_peak,1'b0}+{2'b0,noise_peak};
 wire [26:0] activity_threshold=triple_noise>512?triple_noise:27'd512;
 reg [2:0] desired,safe_gain;
 integer g;
 always @* begin
  desired=0;safe_gain=0;
  // Constant comparators + priority selection, no additional multiplier.
  for(g=0;g<=MAX_GAIN_SHIFT;g=g+1)begin
   if(frame_peak<=(27'd8192 << (8-g)))desired=g;
   if(magnitude<=(27'd30000 << (8-g)))safe_gain=g;
  end
 end
 wire [2:0] selected_gain=AGC_ENABLE?(gain_level<safe_gain?gain_level:safe_gain):GAIN_SHIFT;
 wire signed [40:0] scaled=difference >>> (24-selected_gain);
 assign agc_gain=AGC_ENABLE?gain_level:GAIN_SHIFT;
 function [15:0] saturate;input signed [40:0] value;
  begin
   if(value>32767)saturate=16'h7fff;
   else if(value< -32768)saturate=16'h8000;
   else saturate=value[15:0];
  end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   primed<=0;dc_q<=0;pcm_valid<=0;pcm_sample<=0;reference_pcm<=0;
   sample_index<=0;peak<=0;noise_peak<=64;gain_level<=GAIN_SHIFT;clip_count<=0;
  end else begin
   pcm_valid<=sample_valid;
   if(sample_valid)begin
    if(!primed)begin
     primed<=1;dc_q<=input_q;pcm_sample<=0;reference_pcm<=0;
    end else begin
     dc_q<=next_dc[39:0];pcm_sample<=saturate(scaled);reference_pcm<=saturate(fixed_scaled);
     if((scaled>32767 || scaled< -32768) && clip_count!=32'hffffffff)clip_count<=clip_count+1'b1;
     peak<=frame_peak;sample_index<=sample_index+1'b1;
     if(sample_index==255)begin
      peak<=0;
      if(frame_peak>activity_threshold)begin
       // Select at utterance onset, then hold upward gain while recording.
       // A louder syllable may always reduce gain to avoid clipping.
       if(speech_active!==1'b1 || desired<gain_level)gain_level<=desired;
      end else if(speech_active!==1'b1)begin
       gain_level<=GAIN_SHIFT;
       noise_peak<=next_noise<16?25'd16:next_noise[24:0];
      end
     end
     // Sample-wise attack handles sudden close/loud input before frame update.
     if(AGC_ENABLE && safe_gain<gain_level)gain_level<=safe_gain;
    end
   end
  end
 end
endmodule
