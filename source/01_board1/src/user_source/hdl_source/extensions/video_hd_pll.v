`timescale 1ns/100fs
// 50MHz reference ->742.5MHz VCO. C0=67.5MHz is auxiliary feedback;
// C1/10=74.25MHz pixel, C2/2=371.25MHz serializer. One physical PLL.
module video_hd_pll(input refclk,reset,output clk0_out,clk1_out,locked);
 wire feedback_raw,feedback,pixel_raw,serial_raw;wire[1:0]unused_clock;
 EG_LOGIC_BUFG feedback_buffer(.i(feedback_raw),.o(feedback));
 EG_LOGIC_BUFG pixel_buffer(.i(pixel_raw),.o(clk0_out));
 EG_LOGIC_BUFG serial_buffer(.i(serial_raw),.o(clk1_out));
 EG_PHY_PLL #(.DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000000"),
  .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),.STDBY_ENABLE("DISABLE"),
  .PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),.GMC_GAIN(2),.ICP_CURRENT(9),
  .KVCO(2),.LPF_CAPACITOR(1),.LPF_RESISTOR(8),.REFCLK_DIV(20),.FBCLK_DIV(27),
  .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(11),.CLKC0_CPHASE(10),.CLKC0_FPHASE(0),
  .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(10),.CLKC1_CPHASE(9),.CLKC1_FPHASE(0),
  .CLKC2_ENABLE("ENABLE"),.CLKC2_DIV(2),.CLKC2_CPHASE(2),.CLKC2_FPHASE(5))pll_inst(
  .refclk(refclk),.reset(reset),.stdby(1'b0),.extlock(locked),.load_reg(1'b0),
  .psclk(1'b0),.psdown(1'b0),.psstep(1'b0),.psclksel(3'b000),.psdone(),
  .dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),
  .fbclk(feedback),.clkc({unused_clock,serial_raw,pixel_raw,feedback_raw}));
endmodule
