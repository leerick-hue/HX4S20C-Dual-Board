`timescale 1ns/1ps
// Default: register read data once. Hold physical KEY3 during KEY1 reset
// to select the unchanged raw path for a comparison in the same bitstream.
module boot_read_alignment(
 input ref_clk,mem_clk,rst_n,mem_reset,key3_n,
 output enabled_mem,selected_ref
);
 reg boot_enable=1'b1;
 always @(posedge ref_clk)if(!rst_n)boot_enable<=key3_n;
 (* ASYNC_REG="TRUE" *)reg[1:0] mode_sync;
 always @(posedge mem_clk or posedge mem_reset)
  if(mem_reset)mode_sync<=0;else mode_sync<={mode_sync[0],boot_enable};
 assign enabled_mem=mode_sync[1];
 assign selected_ref=boot_enable;
endmodule
