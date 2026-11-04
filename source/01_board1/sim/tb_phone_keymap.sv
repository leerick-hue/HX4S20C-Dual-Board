`timescale 1ns/1ps
// Unit scope: public decoded frame/repeat inputs, not an IR waveform.
module tb_phone_keymap;
 reg clk=0; always #6.734007 clk=~clk;
 reg rst_n=0,frame_valid=0,repeat_frame=0,cmd_ready=1;
 reg [15:0] address=0; reg [7:0] command=0;
 wire cmd_valid,disabled_valid; wire [7:0] cmd_id,disabled_id;
 wire [31:0] last_raw_code,dropped_count,disabled_raw,disabled_drops;
 ir_keymap #(.CLK_HZ(74250000)) dut(.*);
 ir_keymap #(.CLK_HZ(74250000),.PHONE_ENABLE(0)) disabled(.clk(clk),.rst_n(rst_n),
  .frame_valid(frame_valid),.repeat_frame(repeat_frame),.address(address),.command(command),
  .cmd_valid(disabled_valid),.cmd_ready(cmd_ready),.cmd_id(disabled_id),
  .last_raw_code(disabled_raw),.dropped_count(disabled_drops));
 integer count=0,disabled_count=0; reg [7:0] ids[0:63];
 always @(posedge clk) if(rst_n) begin
  if(cmd_valid && cmd_ready) begin ids[count]=cmd_id;count=count+1;end
  if(disabled_valid && cmd_ready) disabled_count=disabled_count+1;
 end
 task frame(input [15:0] a,input [7:0] c);
  begin
   @(negedge clk);address=a;command=c;frame_valid=1;
   @(negedge clk);frame_valid=0;repeat(4) @(negedge clk);
   if(last_raw_code!=={a,8'h00,c}) $fatal(1,"raw tuple changed");
  end
 endtask
 task repeat_key;
  begin @(negedge clk);repeat_frame=1;@(negedge clk);repeat_frame=0;repeat(4) @(negedge clk);end
 endtask
 task expect_frame(input [15:0] a,input [7:0] c,input [7:0] id);
  integer before_count;
  begin before_count=count;frame(a,c);
   if(count!=before_count+1 || ids[before_count]!==id)
    $fatal(1,"address%h key%h expected ID%0d count%0d",a,c,id,count);
  end
 endtask
 integer n,d;
 initial begin
  repeat(5) @(negedge clk);rst_n=1;
  expect_frame(16'hbf00,8'h44,4);
  expect_frame(16'hbf00,8'h43,6);
  expect_frame(16'hbf00,8'h0d,5);n=count;
  #130000000;repeat_key();if(count!=n) $fatal(1,"mute repeated");
  expect_frame(16'hbf00,8'h4a,1);n=count;
  #130000000;repeat_key();if(count!=n) $fatal(1,"next repeated");
  expect_frame(16'hbf00,8'h4b,20);n=count;
  #130000000;repeat_key();if(count!=n) $fatal(1,"auto repeated");
  n=count;frame(16'hbf00,8'h47);frame(16'hbe00,8'h44);
  if(count!=n || disabled_count!=0) $fatal(1,"unmapped or disabled phone acted");
  expect_frame(16'h0000,8'h43,1);expect_frame(16'h0000,8'h40,6);
  if(disabled_count!=2) $fatal(1,"disabled phone broke legacy");
  expect_frame(16'hbf00,8'h44,4);n=count;
  #119000000;repeat_key();if(count!=n) $fatal(1,"volume repeated too early");
  #2000000;repeat_key();if(count!=n+1 || ids[n]!=4) $fatal(1,"volume hold did not repeat");
  cmd_ready=0;frame(16'hbf00,8'h43);
  if(!cmd_valid || cmd_id!=6) $fatal(1,"pending volume missing");
  d=dropped_count;frame(16'hbf00,8'h44);
  if(!cmd_valid || cmd_id!=6 || dropped_count!=d+1) $fatal(1,"backpressure overwrote pending");
  n=count;cmd_ready=1;repeat(4) @(negedge clk);
  if(count!=n+1 || ids[n]!=6 || cmd_valid) $fatal(1,"pending was not delivered once");
  $display("PASS phone keymap: five mappings, exact address filter, raw diagnostics, legacy and disable option, hold throttle, no repeat of toggles/next, backpressure/drop");
  $finish;
 end
 initial begin #1000000000;$fatal(1,"keymap watchdog");end
endmodule
