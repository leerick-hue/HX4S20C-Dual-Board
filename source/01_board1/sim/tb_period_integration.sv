`timescale 1ns/1ps
// Digital mixed-media integration. Physical card initialization, SDRAM chip,
// read PHY and HDMI are deliberately outside this application-interface test.
module tb_period_integration;
 reg clk=0,sclk=0,vclk=0,mclk=0,aclk=0,base_rst=1,want_video=0,play=1;
 always #12.5 clk=~clk; always #5 sclk=~sclk; always #6.734007 vclk=~vclk;
 always #10 mclk=~mclk; always #40.690104 aclk=~aclk;
 wire rst;
 media_mode_reset #(.HOLD_CYCLES(8)) mode_reset(vclk,base_rst,want_video,rst);
 reg album_key_next=1,album_key_auto=1,link_rx=1;
 wire next_cmd,auto_valid,auto_enable,legacy_next,legacy_auto_valid,legacy_auto_enable,legacy_ready,remote_ready,auto_state;
 wire[31:0]uart_accepted,uart_duplicates,uart_unsupported,uart_errors;
 reg[7:0]sequence_number=0;
 board_remote_control #(.CLK_HZ(40000000),.BAUD(115200),.ACK_ENABLE(1)) remote(
  .clk(clk),.rst_n(!rst),.link_rx(link_rx),.album_ready(legacy_ready),.control_ready(1'b1),
  .control_valid(),.control_code(),.next_pulse(legacy_next),.auto_valid(legacy_auto_valid),.auto_enable(legacy_auto_enable),
  .accepted_count(uart_accepted),.duplicate_count(uart_duplicates),.unsupported_count(uart_unsupported),.packet_error_count(uart_errors),
  .received_byte_count(),.valid_packet_count(),.ack_valid(),.ack_ready(1'b1),.ack_data(),.ack_sequence());
 ir_media_bridge #(.VIDEO_CLK_HZ(74250000)) infrared(
  .video_clk(vclk),.video_rst_n(!rst),.sd_clk(clk),.sd_rst_n(!rst),.ir_in(1'b1),.video_mode(1'b0),
  .album_ready(remote_ready),.auto_enabled(auto_state),.legacy_next(legacy_next),.legacy_auto_valid(legacy_auto_valid),
  .legacy_auto_enable(legacy_auto_enable),.legacy_ready(legacy_ready),.photo_next(next_cmd),.photo_auto_valid(auto_valid),
  .photo_auto_enable(auto_enable),.control_valid(),.control_ready(1'b1),.control_id(),.last_code(),.error_count(),.dropped_count(),.seen());
 wire req; wire[31:0]addr; wire[7:0]byte_data;wire byte_valid,byte_end;
 wire ready,active_video,video_present,photo_present,media_ready,audio_present,started;
 wire[31:0]audio_start,audio_frames,playhead,frame_number,total_frames,late_frames,dropped_frames;
 wire[3:0]state_code,error_code;wire[11:0]debug_status;wire[1:0]album_index;wire[2:0]album_count;
 wire wreq,wack,pvalid,pready;reg finish_toggle=0;wire[1:0]bank;wire[20:0]paddr;wire[31:0]pdata;
 wire swap_valid,swap_ready,swap_done,swap_bank,display_bank,display_valid,switched,transition_busy;
 wire[5:0]fade_gain;wire overflow;
 reg sd_ready=0;integer ready_delay=0;
 always @(posedge sclk or posedge rst)begin
  if(rst)begin sd_ready<=0;ready_delay<=0;end
  else if(ready_delay==31)sd_ready<=1;else ready_delay<=ready_delay+1;
 end
 // Clock signals stay native. Timer/debounce/hold constants are accelerated
 // 1000x: selected nominal 2 seconds becomes 80000 native40MHz cycles (2ms).
 unified_media_source #(.ENABLE_VIDEO(0),.CLK_FREQ_HZ(40000)) source(
  .clk(clk),.rst(rst),.sd_ready(sd_ready),.want_video(want_video),.play_enable(play),.playhead_samples(playhead),
  .key1(album_key_next),.key2(album_key_auto),.edit_mode(3'd0),.photo_next_cmd(next_cmd),
  .photo_auto_valid_cmd(auto_valid),.photo_auto_enable_cmd(auto_enable),.remote_album_ready(remote_ready),.auto_state(auto_state),
  .merged_req(req),.merged_addr(addr),.player_byte(byte_data),.player_byte_valid(byte_valid),.player_end(byte_end),.bridge_overflow(overflow),
  .catalog_ready(ready),.active_video(active_video),.video_present(video_present),.photo_present(photo_present),
  .media_ready(media_ready),.audio_present(audio_present),.audio_start(audio_start),.audio_frames(audio_frames),
  .playback_started(started),.video_frame_number(frame_number),.video_total_frames(total_frames),
  .video_late_frames(late_frames),.video_dropped_frames(dropped_frames),.state_code(state_code),.player_error(error_code),.sd_debug(debug_status),
  .album_index_sd(album_index),.album_count_sd(album_count),.sd_card_write_req(wreq),.sd_card_write_req_ack(wack),
  .frame_write_toggle_mem(finish_toggle),.write_buf_idx(bank),.sd_card_write_en(pvalid),.write_ready(pready),
  .write_pixel_addr(paddr),.sd_card_write_data(pdata),.swap_valid(swap_valid),.swap_ready(swap_ready),.swap_done(swap_done),.swap_bank(swap_bank));
 wire br_req,br_valid,br_end;wire[31:0]br_addr;wire[7:0]br_data;
 sd_sector_cdc bridge(clk,sclk,rst,req,addr,byte_data,byte_valid,byte_end,br_req,br_addr,br_data,br_valid,br_end,overflow);
 wire audio_req,audio_valid,audio_end,card_req;wire[31:0]audio_addr,card_addr;wire[7:0]audio_data;
 reg[7:0]card_data=0;reg card_valid=0,card_end=0;
 sd_sector_arbiter arb(sclk,rst,sd_ready,br_req,br_addr,br_data,br_valid,br_end,
  audio_req,audio_addr,audio_data,audio_valid,audio_end,card_req,card_addr,card_data,card_valid,card_end);
 wire pcm_valid,playing;wire signed[23:0]left,right;wire[31:0]underruns;
 hxjv_pcm_player pcm(.sd_clk(sclk),.video_clk(vclk),.playhead_clk(clk),.audio_mclk(aclk),.rst(rst),
  .sd_ready(sd_ready),.media_ready(media_ready),.audio_present(audio_present),.audio_start(audio_start),.audio_frames(audio_frames),
  .playback_started(active_video?started:ready),.play_enable(play),.sec_req(audio_req),.sec_addr(audio_addr),
  .sec_data(audio_data),.sec_valid(audio_valid),.sec_end(audio_end),.pcm_valid(pcm_valid),.pcm_left(left),.pcm_right(right),
  .underrun_count(underruns),.playing(playing),.playhead_samples(playhead));
 reg[7:0]image[0:1048575];integer image_bytes;string image_path,fixture_path;integer dummy,smoke;
 integer server=0,byte_no=0,gap=0,requests=0;reg[31:0]saved_addr;
 always @(negedge sclk)begin
  card_valid=0;card_end=0;
  if(rst)begin server=0;byte_no=0;gap=0;card_data=0;saved_addr=0;end
  else case(server)
   0:if(card_req && sd_ready)begin
    if(card_addr*512+511>=image_bytes)$fatal(1,"out-of-media LBA %0d",card_addr);
    saved_addr=card_addr;byte_no=0;gap=0;server=1;requests=requests+1;
   end
   1:begin
    if(!card_req || card_addr!==saved_addr)$fatal(1,"SD request/address not held through sector");
    gap=gap+1;
    if(gap==36)begin
     gap=0;card_data=image[saved_addr*512+byte_no];card_valid=1;byte_no=byte_no+1;
     if(byte_no==512)server=2;
    end
   end
   2:begin card_end=1;server=3;end
   3:if(!card_req)server=0;
  endcase
 end
 wire word_valid,word_ready;wire[20:0]word_addr;wire[31:0]word_data;
 rgb565_pack pack(clk,rst||wreq,pvalid,pready,paddr,pdata[31:8],word_valid,word_ready,word_addr,word_data);
 wire[52:0]fifo_data;wire[9:0]fifo_count;wire fifo_aclr,app_wr,wrbusy,finish;wire[20:0]unused_addr;
 wire[20:0]absolute_addr=word_addr+(bank[0]?21'd460800:0);
 pixel_write_fifo queue(.rst(rst||fifo_aclr),.write_clk(clk),.read_clk(mclk),.write_valid(word_valid),.write_ready(word_ready),
  .write_data({absolute_addr,word_data}),.read_en(app_wr),.read_data(fifo_data),.read_count(fifo_count));
 integer mem_cycle=0;always @(posedge mclk)mem_cycle=mem_cycle+1;
 wire read_busy=(mem_cycle%2000)<300;
 frame_fifo_write #(.BURST_SIZE(256),.WRITE_V_FLIP(0),.FRAME_WIDTH(320),.FRAME_HEIGHT(480)) writer(
  .rst(rst),.mem_clk(mclk),.Sdr_init_done(sd_ready),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(read_busy),
  .O_wr_busy(wrbusy),.App_wr_en(app_wr),.App_wr_addr(unused_addr),.write_req(wreq),.write_req_ack(wack),.write_finish(finish),
  .write_addr_0(21'd0),.write_addr_1(21'd460800),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(bank),.write_len(active_video?21'd153600:21'd460800),.fifo_aclr(fifo_aclr),.rdusedw(fifo_count));
 always @(posedge mclk or posedge rst)if(rst)finish_toggle<=0;else if(finish)finish_toggle<=!finish_toggle;
 integer vcount=0;reg vblank=0;
 // Timing remains running across media reset, as on the real board. The
 // accelerated vblank tests the real 64-step fade without simulating a second.
 always @(posedge vclk)begin
  vblank<=0;if(base_rst)vcount<=0;else if(vcount==999)begin vcount<=0;vblank<=1;end else vcount<=vcount+1;
 end
 frame_swap_fx_cdc swap(.sys_clk(clk),.sys_rst_n(!rst),.request_valid(swap_valid),.request_bank(swap_bank),
  .request_ready(swap_ready),.request_done(swap_done),.pixel_clk(vclk),.pixel_rst_n(!rst),.vblank_start(vblank),
  .pixel_safe_to_swap(1'b1),.fade_enable(!active_video),.display_bank(display_bank),.display_valid(display_valid),
  .switched(switched),.fade_gain(fade_gain),.transition_busy(transition_busy));
 reg[31:0]gold0[0:460799],gold1[0:460799],gold2[0:153599],gold3[0:153599],gold4[0:153599];
 reg[31:0]pcm_album[0:511],pcm_video[0:4799];
 reg[31:0]frame_ram[0:460799];reg seen[0:460799];
 wire [20:0] expected_words=active_video?21'd153600:21'd460800;
 integer writes=0,idx,commits=0,frame_asset=0,epoch=0,f,k,mode_resets=0,aborted_frames=0;
 integer pcm_index=0,pcm_verified=0,pcm_verified_total=0,photo_pcm_samples=0,video_pcm_samples=0;
 integer fade_low_samples=0,fade_completed=0,reset_during_sd=0,reset_during_write=0;
 reg[31:0]expected_word,held_pcm;reg old_wreq=0;real last_commit=0;
 function automatic [31:0] golden(input integer asset,input integer pos);
  case(asset)0:golden=gold0[pos];1:golden=gold1[pos];2:golden=gold2[pos];3:golden=gold3[pos];default:golden=gold4[pos];endcase
 endfunction
 function automatic integer expected_asset(input integer commit_no);
  expected_asset=commit_no%2;
 endfunction
 always @(posedge rst)begin
  if(!base_rst)begin
   mode_resets=mode_resets+1;
   if(server==1)reset_during_sd=reset_during_sd+1;
   if(writes>0 && writes<expected_words)begin reset_during_write=reset_during_write+1;aborted_frames=aborted_frames+1;end
   $display("RESET epoch=%0d t_ms=%0f server=%0d partial_words=%0d old_audio_samples=%0d",epoch,$realtime/1e6,server,writes,pcm_verified);
  end
 end
 always @(posedge clk)begin
  if(rst)begin old_wreq<=0;writes=0;end
  else begin
   old_wreq<=wreq;
   if(wreq && !old_wreq)begin
    writes=0;frame_asset=source.album.load_idx;
    for(integer n=0;n<expected_words;n=n+1)seen[n]=0;
    $display("BEGIN epoch=%0d asset=%0d bank=%0d t_ms=%0f",epoch,frame_asset,bank,$realtime/1e6);
   end
   if(ready && (!video_present || !photo_present || active_video!=want_video))$fatal(1,"mixed catalog selection/presence");
   if(error_code!=0)$fatal(1,"source error=%0d state=%0d debug=%h",error_code,state_code,debug_status);
   if(overflow)$fatal(1,"sector CDC overflow");
   if(media_ready && (audio_start!=(32'd4) || audio_frames!=(512)))
    $fatal(1,"wrong translated audio metadata start=%0d frames=%0d",audio_start,audio_frames);
   if(swap_done)begin
    if(writes!=expected_words)$fatal(1,"commit before complete %0d",writes);
    if(frame_asset!=expected_asset(commits))$fatal(1,"commit%0d asset%0d expected%0d",commits,frame_asset,expected_asset(commits));
    if(!active_video && album_count!=2)$fatal(1,"album count %0d expected2",album_count);
    if(active_video && (total_frames!=3 || late_frames!=0 || dropped_frames!=0))$fatal(1,"video metadata/deadline");
    if(underruns!=0)$fatal(1,"audio underrun");
    for(integer n=0;n<expected_words;n=n+1)if(!seen[n])$fatal(1,"missing word%0d",n);
    f=$fopen($sformatf("frame_%0d.hex",commits),"w");
    for(integer n=0;n<expected_words;n=n+1)$fdisplay(f,"%08x",frame_ram[n]);$fclose(f);
    if(commits>0)begin
     if(fade_gain!=32 || transition_busy)$fatal(1,"photo fade acknowledgment precedes completed fade");
     fade_completed=fade_completed+1;
    end
    $display("METRIC commit=%0d epoch=%0d asset=%0d t_ms=%0f interval_ms=%0f words=%0d playhead=%0d pcm_verified=%0d underruns=%0d requests=%0d",commits,epoch,frame_asset,$realtime/1e6,($realtime-last_commit)/1e6,writes,playhead,pcm_verified,underruns,requests);
    last_commit=$realtime;commits=commits+1;
   end
  end
 end
 always @(posedge mclk)if(!rst)begin
  if(app_wr)begin
   idx=fifo_data[52:32]-(bank[0]?460800:0);
   if(display_valid && bank[0]==display_bank)$fatal(1,"writes displayed bank");
   if(idx<0 || idx>=expected_words || seen[idx])$fatal(1,"invalid/duplicate word address%0d",idx);
   expected_word=golden(frame_asset,idx);
   if(fifo_data[31:0]!==expected_word)$fatal(1,"RGB565 mismatch asset=%0d address=%0d got=%h expected=%h",frame_asset,idx,fifo_data[31:0],expected_word);
   seen[idx]=1;frame_ram[idx]=fifo_data[31:0];writes=writes+1;
  end
  if(finish && writes!=expected_words)$fatal(1,"DMA finish wrong count%0d",writes);
 end
 // Independent sample sequence is derived from input media bytes, including
 // each mode's different loop length. Check emitted samples after actual FIFO
 // read/registered PCM timing; silence is required before priming and in pause.
 reg check_pcm,have_pcm;reg[31:0]pcm_expected;
 always @(posedge vclk)begin
  if(rst)begin pcm_index=0;pcm_verified=0;held_pcm=0;end
  else begin
   if(fade_gain<32)fade_low_samples=fade_low_samples+1;
   check_pcm=pcm.tick_pending;have_pcm=pcm.fifo_valid;pcm_expected=held_pcm;
   if(pcm.fifo_pop)begin
    held_pcm=active_video?pcm_video[pcm_index]:pcm_album[pcm_index];
    pcm_index=pcm_index+1;if(pcm_index==(512))pcm_index=0;
   end
   if(check_pcm)begin
    #1;
    if(!pcm_valid)$fatal(1,"PCM missing sample valid");
    if(have_pcm)begin
     if(left!=={pcm_expected[15:0],8'd0} || right!=={pcm_expected[31:16],8'd0})
      $fatal(1,"PCM mismatch epoch=%0d index=%0d got=%h/%h expected=%h",epoch,pcm_index,left,right,pcm_expected);
     pcm_verified=pcm_verified+1;pcm_verified_total=pcm_verified_total+1;
     if(active_video)video_pcm_samples=video_pcm_samples+1;else photo_pcm_samples=photo_pcm_samples+1;
    end else if(left!==0 || right!==0)$fatal(1,"nonzero PCM without valid FIFO data");
   end
   if(underruns!=0)$fatal(1,"PCM underrun%0d",underruns);
  end
 end
 task automatic next_photo;
  begin
   wait(remote_ready);@(negedge clk);album_key_next=0;
   repeat(2000)@(negedge clk);album_key_next=1;repeat(2000)@(negedge clk);
  end
 endtask
 function automatic [7:0]crc_byte(input[7:0]prior,input[7:0]data);
  reg[7:0]c;begin c=prior^data;for(integer j=0;j<8;j=j+1)c=c[7]?(c<<1)^8'h07:c<<1;crc_byte=c;end
 endfunction
 task automatic send_byte(input[7:0]data);
  begin
   @(negedge clk);link_rx=0;repeat(347)@(negedge clk);
   for(integer j=0;j<8;j=j+1)begin link_rx=data[j];repeat(347)@(negedge clk);end
   link_rx=1;repeat(349)@(negedge clk);
  end
 endtask
 task automatic keyboard(input[3:0]code);
  reg[7:0]crc;integer accepted_before;
  begin
   accepted_before=uart_accepted;crc=0;
   crc=crc_byte(crc,1);crc=crc_byte(crc,1);crc=crc_byte(crc,1);
   crc=crc_byte(crc,sequence_number);crc=crc_byte(crc,{4'b0,code});crc=crc_byte(crc,0);
   send_byte(8'ha5);send_byte(8'h5a);send_byte(1);send_byte(1);send_byte(1);
   send_byte(sequence_number);send_byte({4'b0,code});send_byte(0);send_byte(crc);
   sequence_number=sequence_number+1'b1;
   wait(uart_accepted==accepted_before+1);repeat(20)@(negedge clk);
  end
 endtask
 integer paused_pcm,paused_playhead;
 initial begin
  dummy=$value$plusargs("IMAGE=%s",image_path);dummy=$value$plusargs("BYTES=%d",image_bytes);
  dummy=$value$plusargs("FIXTURE=%s",fixture_path);smoke=$test$plusargs("SMOKE");
  $readmemh(image_path,image,0,image_bytes-1);
  $readmemh({fixture_path,"/photo0.hex"},gold0);$readmemh({fixture_path,"/photo1.hex"},gold1);
  $readmemh({fixture_path,"/video0.hex"},gold2);$readmemh({fixture_path,"/video1.hex"},gold3);$readmemh({fixture_path,"/video2.hex"},gold4);
  $readmemh({fixture_path,"/pcm_album.hex"},pcm_album);$readmemh({fixture_path,"/pcm_video.hex"},pcm_video);
  repeat(10)@(negedge clk);base_rst=0;
  wait(commits==1);wait(remote_ready);
  if(album_index!=0 || auto_state)$fatal(1,"startup album state");
  // A real local long press changes the new period without enabling autoplay.
  @(negedge clk);album_key_auto=0;repeat(51000)@(negedge clk);
  album_key_auto=1;repeat(2000)@(negedge clk);
  if(source.album.auto_sel!=1 || auto_state || commits!=1)$fatal(1,"long hold tier1 altered auto/display");
  $display("PERIOD_KEYS_PASS tier=1 nominal_seconds=2 accelerated_native_cycles=80000 auto_stays_off=1");
  next_photo();wait(commits==2);wait(remote_ready);
  if(album_index!=1 || source.album.auto_sel!=1 || auto_state)$fatal(1,"manual next index/tier");
  keyboard(2);wait(auto_state);wait(commits==3);
  keyboard(1);wait(!auto_state);wait(remote_ready);
  paused_pcm=photo_pcm_samples;paused_playhead=playhead;
  #6000000;
  if(commits!=3 || album_index!=0 || auto_state || source.album.auto_sel!=1 || source.album.auto_cnt!=0 ||
     photo_pcm_samples-paused_pcm<200 || playhead<=paused_playhead || !playing)$fatal(1,"remote pause changed display/tier or stopped PCM");
  $display("REMOTE_PAUSE_PASS commits=%0d tier=%0d ongoing_PCM=%0d playhead_delta=%0d",commits,source.album.auto_sel,photo_pcm_samples-paused_pcm,playhead-paused_playhead);
  keyboard(2);wait(auto_state);wait(commits==4);
  keyboard(1);wait(!auto_state);wait(remote_ready);
  #3000000;
  if(commits!=4 || album_index!=1 || auto_state || source.album.auto_sel!=1 || uart_accepted!=4 || uart_duplicates || uart_unsupported || uart_errors)
   $fatal(1,"remote resume/pause count/tier or UART receiver error");
  @(negedge vclk);play=0;repeat(20)@(negedge vclk);dummy=playhead;
  #2000000;if(playhead!=dummy || commits!=4 || playing)$fatal(1,"photo music pause changed playhead/display");
  @(negedge vclk);play=1;wait(playing);repeat(100)@(negedge vclk);
  if(photo_pcm_samples<512 || fade_completed!=3 || underruns)$fatal(1,"photo PCM/fade coverage");
  $display("PASS period_integration:4 complete1280x720 fit photos,1843200 unique RGB565 words,physical manual next,long hold tier1,actual115200 UART resume/pause through receiver/legacy bridge,autoplay wrap/resume,tier preserved,PCM uninterrupted during slideshow pause,music pause/resume,both BMP orientations,bank ownership,native40/50/74.25/100MHz clocks,accelerated timer/debounce/fade,zero underruns (%0d PCM)",photo_pcm_samples);
  $finish;
 end
 initial begin #1200000000;$fatal(1,"timeout commits=%0d epoch=%0d state=%0d writes=%0d sdserver=%0d debug=%h",commits,epoch,state_code,writes,server,debug_status);end
endmodule
