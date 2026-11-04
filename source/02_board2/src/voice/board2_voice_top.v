`timescale 1ns/1ps
// INMP441 + on-board enrollment + keypad + independent PCM diagnostic USB UART.
module board2_voice_top #(parameter CLK_HZ=50000000,BAUD=115200,KEY_CYCLES=1000000,
 WARMUP_CYCLES=15000000,MIC_GAIN_SHIFT=1)(
 input clk,rst_n,input[2:0]key_n,input mic_sd,output mic_sck,mic_ws,
 output[3:0]keypad_row_n,input[3:0]keypad_col_n,
 output link_tx,input link_ack_rx,output debug_tx,output[3:0]led_n);
 wire reset_n;reset_sync release_reset(.clk(clk),.arst_n(rst_n),.rst_n(reset_n));
 wire recording;wire signed[15:0]reference_pcm;wire[31:0]clip_count;
 wire pcm_valid,raw_valid;wire signed[15:0]pcm;wire signed[23:0]raw24;wire[31:0]sample_count;
 inmp441_rx #(.CLK_HZ(CLK_HZ),.GAIN_SHIFT(0)) microphone(.clk(clk),.rst_n(reset_n),.mic_sd(mic_sd),
  .mic_sck(mic_sck),.mic_ws(mic_ws),.pcm_valid(raw_valid),.pcm_sample(),.sample_count(sample_count),.pcm24_debug(raw24));
 mic_pcm_conditioner #(.GAIN_SHIFT(MIC_GAIN_SHIFT),.AGC_ENABLE(1)) condition_input(.clk(clk),.rst_n(reset_n),
  .sample_valid(raw_valid),.sample24(raw24),.speech_active(recording),
  .pcm_valid(pcm_valid),.pcm_sample(pcm),.reference_pcm(reference_pcm),.agc_gain(),.clip_count(clip_count));
 reg[23:0]warmup;reg[25:0]heartbeat;
 wire warmed=warmup>=WARMUP_CYCLES;
 always @(posedge clk or negedge reset_n)if(!reset_n)begin warmup<=0;heartbeat<=0;end
 else begin if(!warmed)warmup<=warmup+1'b1;heartbeat<=heartbeat+1'b1;end
 wire[2:0]pressed,down;genvar i;
 generate for(i=0;i<3;i=i+1)begin:buttons
  key_debounce #(.STABLE_CYCLES(KEY_CYCLES)) button(.clk(clk),.rst_n(reset_n),.key_n(key_n[i]),.pressed(pressed[i]),.down(down[i]));
 end endgenerate
 wire[1:0]train_request=pressed[0]?2'd1:pressed[1]?2'd2:pressed[2]?2'd3:2'd0;
 wire voice_valid,voice_ready,train_done,result_valid,accepted,calibrated;
 wire[15:0]voice_id,best_score,second_score,noise,energy;
 wire[2:0]templates;wire[31:0]overruns,rejects,aborts,debug_drops;
 speech_command_core #(.END_SILENCE(20),.MAX_FRAMES(240),.RELEASE_FACTOR(2),.DROP_SILENCE(1),
  .PREFIX_FRAMES(24),.VERIFY_FULL(1),.ROBUST(1)) recognizer(.clk(clk),.rst_n(reset_n),.pcm_valid(pcm_valid && warmed),.pcm_sample(pcm),.reference_pcm(reference_pcm),.clip_count(clip_count),.train_request(train_request),
  .command_valid(voice_valid),.command_ready(voice_ready),.command_id(voice_id),.template_mask(templates),.train_done(train_done),
  .result_valid(result_valid),.accepted(accepted),.best_score(best_score),.second_score(second_score),.feature_overruns(overruns),.reject_count(rejects),.abort_count(aborts),
  .calibrated(calibrated),.recording(recording),.noise_level(noise),.level(energy),.feature_valid_debug(),.feature_debug());
 pcm_uart_stream diagnostic(.clk(clk),.rst_n(reset_n),.pcm_valid(pcm_valid && warmed),.pcm_sample(reference_pcm),.tx(debug_tx),.drop_count(debug_drops));
 wire[3:0]scan_rows,key_code;wire key_valid,key_ready,key_overflow;
 generate for(i=0;i<4;i=i+1)begin:rows
  assign keypad_row_n[i]=scan_rows[i]?1'bz:1'b0;
 end endgenerate
 keypad_scan_4x4 matrix(.clk(clk),.rst_n(reset_n),.row_n(scan_rows),.col_n(keypad_col_n),
  .key_valid(key_valid),.key_ready(key_ready),.key_code(key_code),.key_overflow(key_overflow));
 wire merged_valid,merged_ready,queued_valid,queued_ready,byte_valid,byte_ready,uart_busy;
 wire[31:0]merged_data,queued_data;wire[7:0]byte_data;wire[4:0]queue_level;
 event_arbiter merge(.clk(clk),.rst_n(reset_n),.key_valid(key_valid),.key_ready(key_ready),.key_data({8'h01,8'h01,12'd0,key_code}),
  .voice_valid(voice_valid),.voice_ready(voice_ready),.voice_data({8'h02,8'h02,voice_id}),.out_valid(merged_valid),.out_ready(merged_ready),.out_data(merged_data));
 event_fifo queue(.clk(clk),.rst_n(reset_n),.in_valid(merged_valid),.in_ready(merged_ready),.in_data(merged_data),
  .out_valid(queued_valid),.out_ready(queued_ready),.out_data(queued_data),.level(queue_level));
 wire link_waiting,link_confirmed,link_failed;
 reliable_event_link #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.RETRY_CYCLES(CLK_HZ/5)) transport(
  .clk(clk),.rst_n(reset_n),.event_valid(queued_valid),.event_ready(queued_ready),.event_data(queued_data),
  .link_tx(link_tx),.ack_rx(link_ack_rx),.waiting(link_waiting),.confirmed(link_confirmed),.failed(link_failed),.retry_count(),.delivery_count());
 voice_status_leds #(.SHOW_CYCLES(CLK_HZ)) recognition_lights(.clk(clk),.rst_n(reset_n),
  .template_mask(templates),.command_valid(voice_valid),.command_ready(voice_ready),
  .command_id(voice_id),.leds(led_n[2:0]));
 // After enrollment LED4 reports packet delivery; before it retains mic status.
 assign led_n[3]=templates==3'b111 ? (link_failed?heartbeat[21]:(link_waiting?heartbeat[23]:link_confirmed)) :
  !(recording || (!calibrated && heartbeat[22]) || ((overruns!=0 || debug_drops!=0 || key_overflow) && heartbeat[20]));
endmodule
