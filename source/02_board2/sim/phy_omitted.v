// Testbench-only endpoint. Long frontend run checks raster/core/audio sequence,
// not serial PHY. Production build registers the original actual PHY instead.
module hdmi_phy_wrapper #(parameter DEVICE="EG")(
 input I_pixel_clk,I_serial_clk,I_rst,
 input[9:0]I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
 assign O_tmds_ch0_p=0,O_tmds_ch1_p=0,O_tmds_ch2_p=0,O_tmds_clk_p=0;
endmodule
