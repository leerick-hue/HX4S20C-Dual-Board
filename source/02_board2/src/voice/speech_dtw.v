`timescale 1ns/1ps
// Endpoint DTW, rolling row RAM, three on-board enrolled templates. No CPU.
module speech_dtw #(parameter MAX_FRAMES=128,MIN_FRAMES=4,MAX_SCORE=96,MIN_MARGIN=8,
 PREFIX_FRAMES=0,VERIFY_FULL=0,ROBUST_RANK=0)(
 input clk,input rst_n,input segment_start,input segment_end,input segment_abort,
 input[1:0]train_class,input feature_valid,input[63:0]feature_data,
 output segment_ready,output feature_ready,output reg[2:0]template_mask,output reg train_done,
 output reg result_valid,output reg accepted,output reg[15:0]best_score,second_score,
 output reg command_valid,input command_ready,output reg[15:0]command_id,
 output reg[31:0]reject_count,abort_count);
 localparam IDLE=0,CAPTURE=1,ENDCAP=2,COPYADDR=3,COPYWAIT=4,COPYWRITE=5,
 INIT=6,INITROW=7,CELLADDR=8,CELLWAIT=9,CELLDIST=10,CELLWRITE=11,DIVIDE=12,RANK=13,REPORT=14,FULLREPORT=15,COMBINE=16,ROBUST_REPORT=17;
 localparam[23:0]INF=24'h7fffff;
 reg[4:0]state;reg[1:0]training,cls,best_class;
 reg[7:0]length,template_length[0:2],i,j,copy_index;
 reg too_long;
 reg full_verification;
 wire[7:0]match_length=PREFIX_FRAMES!=0 && !full_verification && length>PREFIX_FRAMES?PREFIX_FRAMES:length;
 wire[7:0]match_template_length=PREFIX_FRAMES!=0 && !full_verification && template_length[cls]>PREFIX_FRAMES?PREFIX_FRAMES:template_length[cls];
 wire duration_ok={1'b0,length}<={template_length[cls],1'b0} && {1'b0,template_length[cls]}<={length,1'b0};
 wire confident=best_score<=MAX_SCORE && {1'b0,second_score}>={1'b0,best_score}+MIN_MARGIN;
 reg [15:0]prefix_scores[0:2],full_scores[0:2];
 wire [17:0]weighted_score={2'd0,prefix_scores[cls]}+{1'b0,full_scores[cls],1'b0};
 wire [15:0]bounded_score=weighted_score>65535?16'hffff:weighted_score[15:0];
 reg [15:0]other_prefix,other_full;
 integer competitor;
 always @*begin
  other_prefix=16'hffff;other_full=16'hffff;
  for(competitor=0;competitor<3;competitor=competitor+1)if(competitor+1!=best_class)begin
   if(prefix_scores[competitor]<other_prefix)other_prefix=prefix_scores[competitor];
   if(full_scores[competitor]<other_full)other_full=full_scores[competitor];
  end
 end
 wire [15:0]chosen_prefix=prefix_scores[best_class-1'b1];
 wire [15:0]chosen_full=full_scores[best_class-1'b1];
 wire robust_duration={1'b0,length}<={template_length[best_class-1'b1],1'b0} &&
                      {1'b0,template_length[best_class-1'b1]}<={length,1'b0};
 // Both views must agree (ties allowed), with independent separation evidence.
 // Reported scores are prefix + 2*whole scores; margin12 equals4 average units.
 wire robust_confident=best_score<=144 && {1'b0,second_score}>={1'b0,best_score}+17'd12 &&
  chosen_prefix<=96 && chosen_full<=48 && other_prefix>=chosen_prefix && other_full>=chosen_full &&
  (({1'b0,other_prefix}>={1'b0,chosen_prefix}+17'd8) ||
   ({1'b0,other_full}>={1'b0,chosen_full}+17'd8) ||
   (({1'b0,other_prefix}>={1'b0,chosen_prefix}+17'd4) && ({1'b0,other_full}>={1'b0,chosen_full}+17'd4))) && robust_duration;

 localparam AW=$clog2(MAX_FRAMES),TAW=$clog2(3*MAX_FRAMES);
 (* ram_style="bram" *)reg[63:0]utterance[0:(1<<AW)-1];
 (* ram_style="bram" *)reg[63:0]templates[0:(1<<TAW)-1];
 (* ram_style="bram" *)reg[23:0]row[0:MAX_FRAMES-1];
 reg[7:0]uaddr,caddr;reg[9:0]taddr;
 reg[63:0]udata,tdata;reg[23:0]above,diagonal,left_cost,distance;
 reg[23:0]cost,quotient;reg[9:0]remainder,denominator;
 reg[4:0]div_bit;
 wire[10:0]shift_rem={remainder,quotient[23]};
 wire div_one=shift_rem>={1'b0,denominator};
 wire[23:0]div_next={quotient[22:0],div_one};
 reg[23:0]minimum,new_cost;
 reg[12:0]l1;reg signed[8:0]delta;reg[8:0]magnitude;
 integer k,n;
 assign segment_ready=(state==IDLE)&&!command_valid;
 assign feature_ready=(state==CAPTURE) || (segment_ready && segment_start);
 always @(posedge clk)udata<=utterance[uaddr[AW-1:0]];
 always @(posedge clk)tdata<=templates[taddr[TAW-1:0]];
 always @(posedge clk)above<=row[caddr[AW-1:0]];
 // Each memory has one synchronous write port, with no reset on its contents.
 // Valid lengths/masks protect unread entries; this form maps to physical BRAM.
 wire capture_first=state==IDLE && segment_start && !command_valid && feature_valid;
 wire capture_more=state==CAPTURE && !segment_abort && feature_valid && length<MAX_FRAMES;
 wire[AW-1:0]uwrite=capture_first?{AW{1'b0}}:length[AW-1:0];
 wire[TAW-1:0]twrite=(training-1)*MAX_FRAMES+copy_index;
 always @(posedge clk)if(rst_n && (capture_first || capture_more))utterance[uwrite]<=feature_data;
 always @(posedge clk)if(rst_n && state==COPYWRITE)templates[twrite]<=udata;
 always @(posedge clk)if(rst_n && (state==INIT || state==CELLWRITE))row[j[AW-1:0]]<=state==INIT?INF:new_cost;
 always @*begin
  minimum=(diagonal<left_cost)?diagonal:left_cost;
  if(above<minimum)minimum=above;
  new_cost=(minimum==INF || minimum+distance>=INF)?INF:minimum+distance;
  l1=0;
  for(n=0;n<8;n=n+1)begin
   delta=$signed({udata[n*8+7],udata[n*8+:8]})-$signed({tdata[n*8+7],tdata[n*8+:8]});
   magnitude=delta[8]?(~delta+9'd1):delta;
   l1=l1+{4'd0,magnitude};
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;template_mask<=0;training<=0;cls<=0;best_class<=0;length<=0;i<=0;j<=0;copy_index<=0;
   too_long<=0;full_verification<=0;uaddr<=0;taddr<=0;caddr<=0;diagonal<=INF;left_cost<=INF;distance<=0;cost<=0;
   quotient<=0;remainder<=0;denominator<=1;div_bit<=0;
   train_done<=0;result_valid<=0;accepted<=0;best_score<=16'hffff;second_score<=16'hffff;
   command_valid<=0;command_id<=0;reject_count<=0;abort_count<=0;
   for(k=0;k<3;k=k+1)template_length[k]<=0;
  end else begin
   train_done<=0;result_valid<=0;
   if(command_valid && command_ready)command_valid<=0;
   if(segment_abort && state==CAPTURE)begin state<=IDLE;abort_count<=abort_count+1'b1;end
   else case(state)
   IDLE:if(segment_start && !command_valid)begin
    training<=train_class;too_long<=0;full_verification<=0;
    length<=feature_valid?1:0;
    state<=segment_end?ENDCAP:CAPTURE;
   end
   CAPTURE:begin
    if(feature_valid)begin
     if(length<MAX_FRAMES)begin length<=length+1'b1;end
     else too_long<=1;
    end
    if(segment_end)state<=ENDCAP;
   end
   ENDCAP:begin
    if(too_long || length<MIN_FRAMES)begin abort_count<=abort_count+1'b1;state<=IDLE;end
    else if(training!=0)begin copy_index<=0;template_mask[training-1'b1]<=0;state<=COPYADDR;end
    else if(template_mask!=7)begin reject_count<=reject_count+1'b1;state<=IDLE;end
    else begin cls<=0;best_score<=16'hffff;second_score<=16'hffff;best_class<=0;j<=0;state<=INIT;end
   end
   COPYADDR:begin uaddr<=copy_index;state<=COPYWAIT;end
   COPYWAIT:state<=COPYWRITE;
   COPYWRITE:begin
    if(copy_index+1==length)begin
     template_length[training-1'b1]<=length;template_mask[training-1'b1]<=1;train_done<=1;state<=IDLE;
    end else begin copy_index<=copy_index+1'b1;state<=COPYADDR;end
   end
   INIT:begin if(j+1==match_template_length)begin i<=0;j<=0;state<=INITROW;end else j<=j+1'b1;end
   INITROW:begin diagonal<=i==0?24'd0:INF;left_cost<=INF;j<=0;state<=CELLADDR;end
   CELLADDR:begin uaddr<=i;taddr<=cls*MAX_FRAMES+j;caddr<=j;state<=CELLWAIT;end
   CELLWAIT:state<=CELLDIST;
   CELLDIST:begin distance<=l1;state<=CELLWRITE;end
   CELLWRITE:begin
    diagonal<=above;left_cost<=new_cost;
    if(j+1==match_template_length)begin
     if(i+1==match_length)begin
      cost<=new_cost;quotient<=new_cost;remainder<=0;denominator<={2'd0,match_length}+{2'd0,match_template_length};div_bit<=0;state<=DIVIDE;
     end else begin i<=i+1'b1;state<=INITROW;end
    end else begin j<=j+1'b1;state<=CELLADDR;end
   end
   DIVIDE:begin
    quotient<=div_next;remainder<=div_one?shift_rem-denominator:shift_rem;
    if(div_bit==23)state<=RANK;else div_bit<=div_bit+1'b1;
   end
   RANK:begin
    if(ROBUST_RANK)begin
     if(full_verification)full_scores[cls]<=quotient>65535?16'hffff:quotient[15:0];
     else prefix_scores[cls]<=quotient>65535?16'hffff:quotient[15:0];
     if(cls==2)begin
      cls<=0;j<=0;
      if(!full_verification)begin full_verification<=1;state<=INIT;end
      else begin best_score<=16'hffff;second_score<=16'hffff;state<=COMBINE;end
     end else begin cls<=cls+1'b1;j<=0;state<=INIT;end
    end else if(full_verification)state<=FULLREPORT;
    else begin
     if(quotient<best_score)begin second_score<=best_score;best_score<=quotient;best_class<=cls+1'b1;end
     else if(quotient<second_score)second_score<=quotient;
     if(cls==2)state<=REPORT;else begin cls<=cls+1'b1;j<=0;state<=INIT;end
    end
   end
   REPORT:begin
    if(PREFIX_FRAMES!=0 && VERIFY_FULL && confident)begin
     // Prefix decides the class; the entire utterance must still match it.
     full_verification<=1;cls<=best_class-1'b1;j<=0;state<=INIT;
    end else begin
     result_valid<=1;accepted<=confident;
     if(confident)begin command_id<={14'd0,best_class};command_valid<=1;end
     else reject_count<=reject_count+1'b1;
     state<=IDLE;
    end
   end
   FULLREPORT:begin
    result_valid<=1;accepted<=quotient<=MAX_SCORE && duration_ok;
    if(quotient<=MAX_SCORE && duration_ok)begin command_id<={14'd0,best_class};command_valid<=1;end
    else reject_count<=reject_count+1'b1;
    state<=IDLE;
   end
   COMBINE:begin
    if(bounded_score<best_score)begin second_score<=best_score;best_score<=bounded_score;best_class<=cls+1'b1;end
    else if(bounded_score<second_score)second_score<=bounded_score;
    if(cls==2)state<=ROBUST_REPORT;else cls<=cls+1'b1;
   end
   ROBUST_REPORT:begin
    result_valid<=1;accepted<=robust_confident;
    if(robust_confident)begin command_id<={14'd0,best_class};command_valid<=1;end
    else reject_count<=reject_count+1'b1;
    state<=IDLE;
   end
   default:state<=IDLE;
   endcase
  end
 end
endmodule
