`timescale 1ns/1ps
module tb_coexist #(parameter CARD_BYTES=153088);
 reg clk=0,rclk=0,rst_n=0,key1=1,key2=1,key3=1,mic_sd=0;
 always #10 clk=~clk;
 always #5 rclk=~rclk;
 wire ms,ws,tx,debug_tx;wire[3:0]led,rows;tri1 sda;
 wire hc,h0,h1,h2,scl,ncs,sck,mosi;wire[5:0]sel;wire[7:0]seg;
 wire ack_wire;reg drop_ack=0;wire ack_rx=drop_ack?1'b1:ack_wire;
 top dut(.clk(clk),.rst_n(rst_n),.key1(key1),.key2(key2),.key3(key3),
  .sd_miso(1'b1),.mic_sd(mic_sd),.mic_sck(ms),.mic_ws(ws),
  .link_tx(tx),.link_ack_rx(ack_rx),.debug_tx(debug_tx),.led_n(led),
  .keypad_col_n(4'hf),.keypad_row_n(rows),.seg_sel(sel),.seg_data(seg),
  .HDMI_CLK_P(hc),.HDMI_D0_P(h0),.HDMI_D1_P(h1),.HDMI_D2_P(h2),
  .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda),.sd_ncs(ncs),.sd_dclk(sck),.sd_mosi(mosi));
 defparam dut.control.EDID_DELAY_CYCLES=7425;
 defparam dut.voice.WARMUP_CYCLES=0;
 defparam dut.voice.KEY_CYCLES=32;
 defparam dut.voice.transport.RETRY_CYCLES=150000;
 defparam dut.card.CARD_BYTES=CARD_BYTES;
 wire av,ae,np,cv,ack_valid,ack_ready,bv,br;wire[3:0]code;
 wire[31:0]accepted,duplicates,errors,ack_data;wire[7:0]ack_sequence,byte_data;
 board_remote_control #(.ACK_ENABLE(1)) receiver(.clk(rclk),.rst_n(rst_n),.link_rx(tx),.album_ready(1'b1),
  .control_ready(1'b1),.control_valid(cv),.control_code(code),.next_pulse(np),.auto_valid(av),.auto_enable(ae),
  .accepted_count(accepted),.duplicate_count(duplicates),.unsupported_count(),.packet_error_count(errors),
  .received_byte_count(),.valid_packet_count(),.ack_valid(ack_valid),.ack_ready(ack_ready),.ack_data(ack_data),.ack_sequence(ack_sequence));
 event_packet_tx #(.USE_EVENT_SEQUENCE(1)) ack_packets(.clk(rclk),.rst_n(rst_n),.event_valid(ack_valid),.event_ready(ack_ready),
  .event_data(ack_data),.event_sequence(ack_sequence),.byte_valid(bv),.byte_ready(br),.byte_data(byte_data));
 uart_tx #(.CLK_HZ(100000000)) ack_transport(.clk(rclk),.rst_n(rst_n),.byte_valid(bv),.byte_ready(br),.byte_data(byte_data),.tx(ack_wire),.busy());
 integer next_count=0,pause_count=0,resume_count=0,train_count=0,expected_train=0;
 always @(posedge rclk)if(rst_n)begin
  if(np)next_count=next_count+1;
  if(av && !ae)pause_count=pause_count+1;
  if(av && ae)resume_count=resume_count+1;
 end
 always @(posedge clk)if(rst_n && dut.voice.train_request!=0)begin
  if(dut.voice.train_request!=expected_train)$fatal(1,"wrong key mapping");
  train_count=train_count+1;
 end
 task key_test(input integer n);
 begin
  expected_train=n;
  @(negedge clk);if(n==1)key1=0;else if(n==2)key3=0;else key2=0;
  repeat(50)@(negedge clk);key1=1;key2=1;key3=1;
  repeat(50)@(negedge clk);
  if(train_count!=n || dut.freeze || dut.bypass || dut.tone_enable)$fatal(1,"training/video isolation");
 end endtask
 reg[15:0]inject_id;
 task command(input[15:0]id);
 begin
  @(negedge clk);inject_id=id;force dut.voice.voice_id=inject_id;force dut.voice.voice_valid=1;
  do @(posedge clk);while(!dut.voice.voice_ready);
  @(negedge clk);force dut.voice.voice_valid=0;
  wait(dut.voice.transport.waiting);wait(!dut.voice.transport.waiting);
  repeat(50)@(negedge clk);
 end endtask
 reg link_done=0;
 initial begin
  force dut.voice.voice_valid=0;
  repeat(20)@(negedge clk);rst_n=1;
  repeat(20)@(negedge clk);
  // Exercise all controls only once video is actually being displayed.
  wait(dut.display_valid);
  key_test(1);key_test(2);key_test(3);
  force dut.voice.templates=3'b111;
  command(1);command(2);command(3);
  if(next_count!=1 || pause_count!=1 || resume_count!=1 || led[3]!==1)$fatal(1,"three voice IDs/ACK indicator");
  drop_ack=1;
  fork
   command(1);
   begin wait(dut.voice.transport.retry_count==1);drop_ack=0;end
  join
  if(next_count!=2 || duplicates!=1 || !dut.voice.transport.confirmed || dut.voice.transport.failed || errors!=0)
   $fatal(1,"ACK retry duplicated/lost command");
  link_done=1;
  $display("LINK_PASS key_mapping=3 commands=4 actual_UART=115200 lost_ACK_retry=1 duplicate_suppressed=1 LED_active_high=1");
 end
 // Drive physical I2S pins, then independently decode diagnostic UART bytes.
 reg[40:0]vectors[0:24495];reg[23:0]word24;integer slot=0,frame_no=0,packets=0,byte_no=0,concurrent_packets=0;
 reg sampled_during_display[0:24495];
 reg[7:0]bytes[0:5],received;
 initial $readmemh("../sim/fixtures/conditioner.mem",vectors);
 always @(posedge ms)if(rst_n)begin
  if(ws!==(slot>=32))$fatal(1,"I2S word select");
  // Mark before any of this sample's physical I2S data bits arrive. Merely
  // seeing display_valid when its later UART packet ends can count a straddle.
  if(slot==0)sampled_during_display[frame_no%24496]=dut.display_valid;
  if(slot==63)begin slot=0;frame_no=frame_no+1;end else slot=slot+1;
 end
 always @(negedge ms)if(rst_n)begin
  word24=vectors[frame_no%24496][39:16];#20;
  mic_sd=(slot>=1 && slot<=24)?word24[24-slot]:1'b0;
 end
 function automatic [7:0]crc(input[23:0]payload);
 reg[7:0]c;begin c=0;for(integer n=23;n>=0;n=n-1)c=(c[7]^payload[n])?((c<<1)^8'h07):(c<<1);crc=c;end
 endfunction
 initial begin
  wait(rst_n);
  // Keep checking until 512 complete samples overlap an actually displayed
  // movie. The first continuous reference segment has no reset before 2112.
  while(concurrent_packets<512)begin
   @(negedge debug_tx);#500;if(debug_tx!==0)$fatal(1,"debug start");
   for(integer b=0;b<8;b=b+1)begin #1000;received[b]=debug_tx;end
   #1000;if(debug_tx!==1)$fatal(1,"debug stop");
   bytes[byte_no]=received;byte_no=byte_no+1;
   if(byte_no==6)begin
    byte_no=0;
    if(packets>=2112)$fatal(1,"continuous I2S reference exhausted before displayed-video coverage");
    if(bytes[0]!==8'ha5 || bytes[1]!==8'h5a || bytes[5]!==crc({bytes[2],bytes[3],bytes[4]}) ||
       {bytes[3],bytes[2]}!==vectors[packets][15:0] || bytes[4]!==8'(packets))$fatal(1,"I2S/PCM/UART mismatch packet %0d",packets);
    if(dut.display_valid && sampled_during_display[packets]===1'b1)concurrent_packets=concurrent_packets+1;
    packets=packets+1;
   end
  end
  $display("MIC_PASS physical_I2S_conditioner_debug_UART_samples=%0d concurrent_displayed_video_samples=%0d CRC_sequence_checked=1",packets,concurrent_packets);
 end
 integer frame_words_seen=0,frame_word_checks=0;
 always @(posedge dut.decode_clk)begin
  if(!dut.decode_rst_n || dut.motion.write_req)frame_words_seen=0;
  else begin
   if(dut.motion.frame_words!==21'd153600)$fatal(1,"native 640x480 frame word count");
   if(dut.motion.word_valid && dut.motion.word_ready)begin
    if(dut.motion.word_addr>=153600)$fatal(1,"native write address overflow");
    frame_words_seen=frame_words_seen+1;
   end
   if(dut.motion.swap_valid && dut.motion.swap_ready)begin
    if(frame_words_seen!=153600)$fatal(1,"frame commit words=%0d expected=153600",frame_words_seen);
    frame_word_checks=frame_word_checks+1;
    $display("NATIVE_FRAME_PASS frame=%0d words=%0d RGB565_direct=1",frame_word_checks,frame_words_seen);
   end
  end
 end
 integer x=0,y=0,frames=0,shown_frames=0,visible_pixels=0;reg seen=0,prior_de=0;reg[23:0]prior_rgb=0;
 always @(posedge dut.pixel_clk)begin
  if(dut.pixel_rst)begin x=0;y=0;frames=0;shown_frames=0;seen=0;prior_de=0;prior_rgb=0;end
  else begin
   if(dut.axis_valid!==prior_de || (prior_de && dut.axis_data!==prior_rgb))$fatal(1,"AXIS alignment");
   prior_de=dut.mde;prior_rgb=dut.memory_rgb;
   if(dut.axis_valid)begin
    if(dut.axis_user)begin if(x!=0||y!=0)$fatal(1,"SOF position");seen=1;end
    if(!seen || dut.axis_last!==(x==1279) || (^dut.axis_data===1'bx))$fatal(1,"AXIS geometry/data");
    if(dut.display_valid && (x<320 || x>=960 || y<120 || y>=600) && dut.axis_data!==0)$fatal(1,"640x480 centred borders x=%0d y=%0d RGB=%h",x,y,dut.axis_data);
    if(dut.display_valid && x>=320 && x<960 && y>=120 && y<600 && dut.axis_data!=0)visible_pixels=visible_pixels+1;
    if(x==1279)begin x=0;y=y+1;
     if(y==720)begin y=0;frames=frames+1;if(dut.display_valid)shown_frames=shown_frames+1;
      $display("FRAME n=%0d displayed=%0d id=%0d committed=%0d state=%0d playhead=%0d",frames,shown_frames,dut.display_id,dut.committed_frames,dut.player_state,dut.motion.source.playhead);
     end
    end else x=x+1;
   end
   if(dut.player_error!=0 || dut.bridge_overflow || dut.underruns!=0)$fatal(1,"video error");
   if(dut.hdmi.I_audio_valid || dut.hdmi.I_acr_valid || dut.bypass || dut.freeze)$fatal(1,"silent continuous video");
  end
 end
 initial begin
  wait(shown_frames>=3 && concurrent_packets==512 && link_done && dut.core_video_locked && dut.committed_frames>=2 && dut.display_id!=0 && frame_word_checks>=2 && visible_pixels>0);
  $display("PASS coexist complete_top source=640x480@15 native_center_x320_y120 frame_words=153600 video_frames=%0d committed=%0d I2S_PCM=512 concurrent_displayed_video_samples=%0d UART_ACK_commands=4 forced_recognition_events=1 ideal_PLL_functional_SDRAM=1",frames,dut.committed_frames,concurrent_packets);
  $finish;
 end
 initial begin #160000000;$fatal(1,"coexist timeout frames=%0d shown=%0d mic=%0d",frames,shown_frames,packets);end
endmodule
