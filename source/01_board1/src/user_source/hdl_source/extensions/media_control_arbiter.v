`timescale 1ns/1ps
// Preserve all sixteen matrix shortcuts alongside IR. UART events cross once;
// local physical keys win in the controls, then IR, then the held UART event.
module media_control_arbiter(input sd_clk,sd_rst_n,input video_mode,input uart_valid,output uart_ready,input[3:0]uart_code,
 input video_clk,video_rst_n,input ir_valid,output ir_ready,input[7:0]ir_id,
 output control_valid,input control_ready,output[7:0]control_id);
 reg[7:0]mapped;
 always @*case(uart_code)
  0,3:mapped=13;1:mapped=video_mode?17:13;2:mapped=video_mode?18:13;
  4:mapped=6;5:mapped=5;6:mapped=4;7:mapped=16;
  8:mapped=9;9:mapped=8;10:mapped=7;11:mapped=14;
  12:mapped=10;13:mapped=12;14:mapped=11;15:mapped=15;
  default:mapped=13;
 endcase
 wire pending,ready;wire[7:0]pending_id;
 media_command_cdc keyboard_mailbox(.src_clk(sd_clk),.src_rst_n(sd_rst_n),.src_valid(uart_valid),.src_ready(uart_ready),.src_code(mapped),
  .dst_clk(video_clk),.dst_rst_n(video_rst_n),.dst_valid(pending),.dst_ready(ready),.dst_code(pending_id));
 assign control_valid=ir_valid || pending;
 assign control_id=ir_valid?ir_id:pending_id;
 assign ir_ready=control_ready;
 assign ready=control_ready && !ir_valid;
endmodule
