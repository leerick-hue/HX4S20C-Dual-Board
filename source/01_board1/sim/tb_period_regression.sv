`timescale 1ns/1ps
// Scheduler/gesture unit only: parser/display readiness and instant consumer
// are forced. Counter, controls and load_start_pulse remain actual RTL.
module tb_period_regression;
 localparam integer F=1000,DB=20,HOLD=1200;
 reg clk=0,rst=1,key_next=1,key_auto=1,key_inhibit=0,pixel_ready=1;
 reg remote_next=0,remote_auto_valid=0,remote_auto_enable=0;
 wire remote_ready,swap_valid,swap_bank,write_req,write_en,sd_sec_read,auto_play_enabled,display_valid;
 wire[10:0]source_width_debug,source_height_debug;wire[19:0]write_pixel_addr;
 wire[3:0]state_code;wire[11:0]debug_status;wire[1:0]displayed_image_index,write_buf_idx,disp_buf_idx;
 wire[2:0]detected_image_count;wire[31:0]write_data,sd_sec_read_addr;
 always #5 clk=~clk;
    sd_card_bmp #(.CLK_FREQ_HZ(F), .WIDTH(1280), .HEIGHT(720)) dut (
        .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
        .remote_next(remote_next), .remote_auto_valid(remote_auto_valid),
        .remote_auto_enable(remote_auto_enable), .remote_ready(remote_ready),
        .key_inhibit(key_inhibit), .pixel_ready(pixel_ready),
        .source_width_debug(source_width_debug), .source_height_debug(source_height_debug),
        .write_pixel_addr(write_pixel_addr), .swap_valid(swap_valid), .swap_ready(1'b1),
        .swap_done(1'b0), .swap_bank(swap_bank), .state_code(state_code),
        .debug_status(debug_status), .displayed_image_index(displayed_image_index),
        .detected_image_count(detected_image_count), .auto_play_enabled(auto_play_enabled),
        .bmp_width(16'd1280), .bmp_height(16'd720), .display_valid(display_valid),
        .write_finish_toggle(1'b0), .write_buf_idx(write_buf_idx), .disp_buf_idx(disp_buf_idx),
        .write_req(write_req), .write_req_ack(1'b1), .write_en(write_en), .write_data(write_data),
        .sd_init_done(1'b1), .media_ready(1'b1),
        .media_photo_start(32'd4), .media_photo_max(32'd4), .media_photo_count(3'd3),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(8'h00), .sd_sec_read_data_valid(1'b0), .sd_sec_read_end(1'b0)
    );

    sd_card_bmp #(.CLK_FREQ_HZ(100000000), .WIDTH(1280), .HEIGHT(720)) wide (
        .clk(clk), .rst(1'b1), .key_next(key_next), .key_auto(key_auto),
        .remote_next(remote_next), .remote_auto_valid(remote_auto_valid),
        .remote_auto_enable(remote_auto_enable), .remote_ready(),
        .key_inhibit(key_inhibit), .pixel_ready(pixel_ready),
        .source_width_debug(), .source_height_debug(),
        .write_pixel_addr(), .swap_valid(), .swap_ready(1'b1),
        .swap_done(1'b0), .swap_bank(), .state_code(),
        .debug_status(), .displayed_image_index(),
        .detected_image_count(), .auto_play_enabled(),
        .bmp_width(16'd1280), .bmp_height(16'd720), .display_valid(),
        .write_finish_toggle(1'b0), .write_buf_idx(), .disp_buf_idx(),
        .write_req(), .write_req_ack(1'b1), .write_en(), .write_data(),
        .sd_init_done(1'b1), .media_ready(1'b1),
        .media_photo_start(32'd4), .media_photo_max(32'd4), .media_photo_count(3'd3),
        .sd_sec_read(), .sd_sec_read_addr(),
        .sd_sec_read_data(8'h00), .sd_sec_read_data_valid(1'b0), .sd_sec_read_end(1'b0)
    );


 integer checks=0,loads=0,steps_seen=0,toggles_seen=0;
 always @(posedge clk)if(!rst)begin
  if(dut.auto_step_pulse)steps_seen=steps_seen+1;
  if(dut.auto_toggle_pulse)toggles_seen=toggles_seen+1;
 end
 always @(posedge clk)begin #1;if(!rst && dut.load_start_pulse)loads=loads+1;end
 task check(input bit ok,input string why);begin
  if(!ok)$fatal(1,"period regression: %s cnt=%0d sel=%0d en=%b load=%b",why,dut.auto_cnt,dut.auto_sel,auto_play_enabled,dut.load_start_pulse);
  checks=checks+1;
 end endtask
 task cycle;begin @(posedge clk);#2;end endtask
 task cycles(input integer n);begin repeat(n)cycle();end endtask
 task reset_case;begin
  @(negedge clk);rst=1;key_auto=1;key_next=1;key_inhibit=0;remote_next=0;remote_auto_valid=0;
  cycles(4);@(negedge clk);rst=0;cycles(4);
  check(dut.auto_sel==0 && !auto_play_enabled && dut.auto_cnt==0,"reset default 1s off");
 end endtask
 task set_auto(input bit en);begin
  @(negedge clk);remote_auto_valid=1;remote_auto_enable=en;cycle();
  check(auto_play_enabled==en && dut.auto_cnt==0 && !dut.load_start_pulse,"remote set atomically resets counter");
  @(negedge clk);remote_auto_valid=0;
 end endtask
 task short_key;begin
  @(negedge clk);key_auto=0;cycles(80);@(negedge clk);key_auto=1;cycles(30);
 end endtask
 task directed_step;begin
  @(negedge clk);dut.hold_busy=1'b1;dut.hold_long=1'b0;force dut.auto_step_pulse=1'b1;cycle();
  check(dut.auto_cnt==0 && !dut.load_start_pulse,"step clears counter and suppresses old-period load");
  @(negedge clk);release dut.auto_step_pulse;dut.hold_busy=0;dut.hold_long=0;dut.hold_cnt=0;
 end endtask
 integer i,j,old_steps,old_toggles,before_loads,secs;
 initial begin
  force dut.scan_done=1'b1;force dut.scan_kicked=1'b1;force dut.scan_found_valid=1'b0;
  force dut.bmp_ready=1'b1;force dut.parser_done=1'b0;force dut.parser_error=1'b0;
  force dut.display_valid=1'b1;force dut.first_image_committed=1'b1;
  force dut.img_found_count=3'd3;force dut.load_busy=1'b0;force dut.load_failed=1'b0;
  force dut.img_idx=2'd1;
  force wide.auto_sel=3'd4;#1;
  check($bits(wide.auto_cnt)==32 && wide.AUTO_MAX_CYCLES==64'd3000000000,"100MHz max cycle width 32 and unsigned 3e9");
  check(wide.auto_limit==32'd2999999999 && wide.HOLD_CYCLES==32'd120000000,"100MHz 30s limit no signed overflow");
  reset_case();
  // Bounces shorter than the actual debounce duration cause no action.
  old_toggles=toggles_seen;@(negedge clk);key_auto=0;cycles(8);@(negedge clk);key_auto=1;cycles(30);
  check(toggles_seen==old_toggles && !auto_play_enabled,"bounce ignored");
  @(negedge clk);key_auto=0;cycles(80);
  check(!auto_play_enabled && dut.hold_busy,"short held: no toggle until debounced release");
  @(negedge clk);key_auto=1;cycles(10);check(!auto_play_enabled,"release must debounce");cycles(20);
  check(auto_play_enabled && dut.auto_sel==0 && toggles_seen==old_toggles+1,"short release toggles exactly once");
  short_key();check(!auto_play_enabled && dut.auto_sel==0,"second actual short release pauses");
  short_key();check(auto_play_enabled && dut.auto_sel==0,"third actual short release resumes");
  set_auto(0);
  for(i=0;i<5;i=i+1)begin
   if(i==0)set_auto(1);
   old_steps=steps_seen;old_toggles=toggles_seen;
   @(negedge clk);key_auto=0;
   while(!dut.hold_busy)cycle();
   check(dut.hold_cnt==0,"debounced press arms hold counter at zero");
   cycles(HOLD-1);
   check(steps_seen==old_steps && dut.hold_cnt==HOLD-1,"no step before full debounced 1.2s hold");
   cycle();
   check(dut.auto_sel==((i+1)%5) && steps_seen==old_steps+1,"long hold steps one tier");
   cycles(HOLD+30);check(steps_seen==old_steps+1,"continued long hold cannot repeat");
   @(negedge clk);key_auto=1;cycles(30);
   check(auto_play_enabled==(i==0) && toggles_seen==old_toggles,"long release preserves enabled or disabled state");
   if(i==0)set_auto(0);
  end
  $display("PERIOD_CASE real_debounce_short_long_wrap=PASS");
  // Cancel halfway through a gesture, return still held, then release.
  old_steps=steps_seen;old_toggles=toggles_seen;
  @(negedge clk);key_auto=0;cycles(600);@(negedge clk);key_inhibit=1;cycles(5);
  check(!dut.hold_busy,"inhibit cancels active gesture");
  @(negedge clk);key_inhibit=0;cycles(HOLD+50);@(negedge clk);key_auto=1;cycles(30);
  check(steps_seen==old_steps && toggles_seen==old_toggles && dut.auto_sel==0,"inhibit cancellation cannot rearm or compensate release");
  // Exact threshold plus release must step, never toggle. Directional force
  // establishes a simultaneous debounced-release boundary, not a fake counter.
  @(negedge clk);force dut.hold_busy=1;force dut.hold_long=0;force dut.hold_cnt=HOLD-1;force dut.key_auto_release=1;
  old_steps=steps_seen;old_toggles=toggles_seen;cycle();
  check(dut.auto_sel==1 && steps_seen==old_steps+1 && toggles_seen==old_toggles,"threshold/release same edge chooses step");
  @(negedge clk);release dut.hold_busy;release dut.hold_long;release dut.hold_cnt;release dut.key_auto_release;
  reset_case();
  // Each natural counter interval is checked cycle by cycle, with actual load
  // output at exactly 1/2/5/10/30 logical seconds. Instant consumer is forced.
  for(i=0;i<5;i=i+1)begin
   set_auto(1);case(i)0:secs=1;1:secs=2;2:secs=5;3:secs=10;default:secs=30;endcase
   check(dut.auto_sel==i && dut.auto_limit==F*secs-1,"tier limit");before_loads=loads;
   for(j=1;j<=F*secs;j=j+1)begin
    cycle();
    if(j<F*secs)check(!dut.load_start_pulse && dut.auto_cnt==j,"no early load; exact natural count");
    else check(dut.load_start_pulse && dut.auto_cnt==0 && loads==before_loads+1,"automatic load on exact interval edge");
   end
   $display("PERIOD_CASE natural_period seconds=%0d cycles=%0d PASS",secs,F*secs);
   set_auto(0);if(i<4)directed_step();
  end
  // Pause preserves tier and resets phase; resume starts a complete fresh period.
  set_auto(1);cycles(111);set_auto(0);cycles(100);
  check(dut.auto_sel==4 && dut.auto_cnt==0 && !dut.load_start_pulse,"paused count stays zero");
  set_auto(1);cycles(100);check(dut.auto_cnt==100 && !dut.load_start_pulse,"resume starts fresh 30s phase");
  // Seed near a limit using a deposit; release before tested edge leaves the
  // actual RTL counter free to update. Counter/output are never forced across
  // the asserted scheduler edge.
  @(negedge clk);dut.auto_cnt=dut.auto_limit;
  remote_auto_valid=1;remote_auto_enable=0;cycle();
  check(!auto_play_enabled && dut.auto_cnt==0 && !dut.load_start_pulse,"tick+pause suppresses stale automatic load");
  @(negedge clk);remote_auto_valid=0;
  set_auto(1);@(negedge clk);dut.auto_cnt=dut.auto_limit;dut.hold_busy=1'b1;dut.hold_long=1'b0;force dut.auto_step_pulse=1;
  cycle();check(dut.auto_sel==0 && dut.auto_cnt==0 && !dut.load_start_pulse,"tick+step resets once without NBA overwrite");
  @(negedge clk);release dut.auto_step_pulse;dut.hold_busy=0;dut.hold_long=0;dut.hold_cnt=0;cycle();check(dut.auto_cnt==1 && !dut.load_start_pulse,"new tier starts at one next cycle");
  // Already-pending manual next takes priority over due auto and still executes
  // when pause is delivered on that edge; no duplicate next remains queued.
  @(negedge clk);dut.auto_cnt=dut.auto_limit;dut.next_req_pending=1;remote_auto_valid=1;remote_auto_enable=0;
  before_loads=loads;cycle();check(dut.load_start_pulse && !auto_play_enabled && dut.load_idx==2 && dut.auto_cnt==0,"manual pending beats auto; pause still applies");
  @(negedge clk);remote_auto_valid=0;cycle();check(!dut.load_start_pulse && loads==before_loads+1 && !dut.next_req_pending,"manual consumed exactly once");
  // Manual request arriving together with pause is queued and then serviced.
  @(negedge clk);remote_next=1;remote_auto_valid=1;remote_auto_enable=0;cycle();check(!dut.load_start_pulse && dut.next_req_pending,"manual+pause arrival queues one request");
  @(negedge clk);remote_next=0;remote_auto_valid=0;cycle();check(dut.load_start_pulse && !auto_play_enabled,"manual next works while paused");
  cycle();check(!dut.load_start_pulse && dut.auto_cnt==0,"off state cannot time");
  force dut.img_found_count=3'd1;set_auto(1);cycles(1100);
  check(dut.auto_cnt==0 && !dut.load_start_pulse,"single photo cannot time or auto advance");
  $display("PASS period_regression checks=%0d actual_debounce=1 periods=1/2/5/10/30 threshold_release_priority=1 inhibit_cancel=1 pause_step_tick_priority=1 manual_pause=1 unsigned100MHz30s=1 scope=scheduler_unit_forced_ready_display_consumer",checks);
  $finish;
 end
 initial begin #5000000;$fatal(1,"period regression watchdog timeout");end
endmodule
