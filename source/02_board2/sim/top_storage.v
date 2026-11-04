`timescale 1ns/1ps
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input[10:0]addr,
 input[1:0]ba,inout[31:0]dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 sdram_retention_model #(.READ_LATENCY_CYCLES(2)) storage(.clk(clk),.rst(!tb_motion_top.dut.mem_rst_n),
  .ras(ras_n),.cas(cas_n),.we(we_n),.ba(ba),.addr(addr),.dm({dm3,dm2,dm1,dm0}),.dq(dq),.writes(),.reads());
endmodule
