`timescale 1ns/1ps
// 16k PCM -> 256-sample Bartlett-windowed 8-band relative log-power spectrum.
// 24 Goertzel bins share one registered multiplier. This is NOT MFCC.
module speech_features(input clk,input rst_n,input pcm_valid,input signed[15:0]pcm_sample,
 output reg feature_valid,output reg[63:0]feature_data,output reg[15:0]frame_energy,
 output reg[31:0]overrun_count);
 localparam IDLE=0,WINWAIT=1,WINDOW=2,LOAD=3,MULWAIT=4,UPDATE=5,
 PLOAD=6,PWAIT=7,PSAVE=8,LOG=9,NORMALIZE=10;
 reg[3:0]state;reg[7:0]sample_index;reg[4:0]bin;reg[1:0]power_phase;
 reg signed[23:0]s1[0:23],s2[0:23];
 reg signed[26:0]ma,mb;reg signed[53:0]product;
 reg signed[31:0]hp_previous,previous_sample,window_sample;
 reg[23:0]energy_acc;
 reg signed[55:0]power_sum;reg[55:0]band_power;
 reg[7:0]logs[0:7],max_log;reg[2:0]band;
 reg signed[31:0]new_hp;
 reg signed[55:0]next_power;
 reg signed[40:0]recurrence;
 reg[7:0]this_log;reg[8:0]relative_log;
 integer i;
 function signed[15:0]coefficient;input[4:0]n;begin case(n)
   5'd0:coefficient=16'sd32729;
   5'd1:coefficient=16'sd32679;
   5'd2:coefficient=16'sd32610;
   5'd3:coefficient=16'sd32413;
   5'd4:coefficient=16'sd32138;
   5'd5:coefficient=16'sd31786;
   5'd6:coefficient=16'sd31357;
   5'd7:coefficient=16'sd30572;
   5'd8:coefficient=16'sd29622;
   5'd9:coefficient=16'sd28899;
   5'd10:coefficient=16'sd27246;
   5'd11:coefficient=16'sd25330;
   5'd12:coefficient=16'sd23170;
   5'd13:coefficient=16'sd19520;
   5'd14:coefficient=16'sd15447;
   5'd15:coefficient=16'sd12540;
   5'd16:coefficient=16'sd6393;
   5'd17:coefficient=16'sd0;
   5'd18:coefficient=-16'sd6393;
   5'd19:coefficient=-16'sd12540;
   5'd20:coefficient=-16'sd18205;
   5'd21:coefficient=-16'sd23170;
   5'd22:coefficient=-16'sd28899;
   5'd23:coefficient=-16'sd32138;
   default:coefficient=0;
 endcase end endfunction
 function[7:0]logpower;input[55:0]value;integer k,top;reg[1:0]fraction;begin
  top=0;for(k=0;k<56;k=k+1)if(value[k])top=k;
  fraction=(top>=2)?((value>>(top-2))&3):0;
  logpower=value==0?0:top*4+fraction;
 end endfunction
 always @(posedge clk) product<=ma*mb;
 always @* begin
  new_hp=$signed(pcm_sample)-previous_sample+hp_previous-(hp_previous>>>5);
  recurrence=(product>>>14)-s2[bin]+window_sample;
  next_power=power_sum;
  if(power_phase==0 || power_phase==1) next_power=power_sum+product;
  else if(power_phase==3)next_power=power_sum-product;
  this_log=logpower(band_power);
  relative_log={1'b0,max_log}-{1'b0,logs[band]};
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;sample_index<=0;bin<=0;power_phase<=0;ma<=0;mb<=0;
   hp_previous<=0;previous_sample<=0;window_sample<=0;energy_acc<=0;
   feature_valid<=0;feature_data<=0;frame_energy<=0;overrun_count<=0;
   power_sum<=0;band_power<=0;max_log<=0;band<=0;
   for(i=0;i<24;i=i+1)begin s1[i]<=0;s2[i]<=0;end
   for(i=0;i<8;i=i+1)logs[i]<=0;
  end else begin
   feature_valid<=0;
   if(pcm_valid && state!=IDLE)begin
    overrun_count<=overrun_count+1'b1;state<=IDLE;sample_index<=0;energy_acc<=0;
    for(i=0;i<24;i=i+1)begin s1[i]<=0;s2[i]<=0;end
   end else case(state)
   IDLE:if(pcm_valid)begin
    previous_sample<=$signed(pcm_sample);hp_previous<=new_hp;
    // >>4 preserves useful resolution while bounding Goertzel state amplitude.
    ma<=new_hp>>>4;mb<=sample_index[7]?255-sample_index:sample_index;
    energy_acc<=energy_acc+(new_hp<0?-new_hp:new_hp);state<=WINWAIT;
   end
   WINWAIT:state<=WINDOW;
   WINDOW:begin window_sample<=product>>>7;bin<=0;state<=LOAD;end
   LOAD:begin ma<=s1[bin];mb<=coefficient(bin);state<=MULWAIT;end
   MULWAIT:state<=UPDATE;
   UPDATE:begin
    if(recurrence>8388607)s1[bin]<=24'sh7fffff;
    else if(recurrence< -8388608)s1[bin]<=24'sh800000;
    else s1[bin]<=recurrence[23:0];
    s2[bin]<=s1[bin];
    if(bin==23)begin
     if(sample_index==255)begin
      sample_index<=0;frame_energy<=energy_acc>>8;energy_acc<=0;
      bin<=0;power_phase<=0;power_sum<=0;band_power<=0;max_log<=0;state<=PLOAD;
     end else begin sample_index<=sample_index+1'b1;state<=IDLE;end
    end else begin bin<=bin+1'b1;state<=LOAD;end
   end
   PLOAD:begin
    case(power_phase)
    0:begin ma<=s1[bin];mb<=s1[bin];end
    1:begin ma<=s2[bin];mb<=s2[bin];end
    2:begin ma<=s1[bin];mb<=coefficient(bin);end
    3:begin ma<=window_sample;mb<=s2[bin];end
    endcase
    state<=PWAIT;
   end
   PWAIT:state<=PSAVE;
   PSAVE:begin
    if(power_phase==2)window_sample<=product>>>14;
    else power_sum<=next_power;
    if(power_phase==3)begin
     band_power<=band_power+(next_power>0?next_power:56'd0);
     s1[bin]<=0;s2[bin]<=0;power_sum<=0;power_phase<=0;
     if(bin%3==2)begin band<=bin/3;state<=LOG;end
     else begin bin<=bin+1'b1;state<=PLOAD;end
    end else begin power_phase<=power_phase+1'b1;state<=PLOAD;end
   end
   LOG:begin
    logs[band]<=this_log;if(this_log>max_log)max_log<=this_log;
    band_power<=0;
    if(bin==23)begin band<=0;state<=NORMALIZE;end
    else begin bin<=bin+1'b1;state<=PLOAD;end
   end
   NORMALIZE:begin
    feature_data[band*8+:8]<=relative_log>127?8'h80:-relative_log[7:0];
    if(band==7)begin feature_valid<=1;state<=IDLE;end else band<=band+1'b1;
   end
   default:state<=IDLE;
   endcase
  end
 end
endmodule
