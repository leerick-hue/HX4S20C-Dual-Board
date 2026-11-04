`timescale 1ns/1ps
// Quiet selection captured from keys during KEY1 (rst_n) reset, then held.
// KEY2 (pattern_key_n) selects the pattern; KEY3 (quiet_key_n) additionally
// selects quiet while KEY1 reset is asserted. Runtime key presses never
// change the held selection. ref domain -> pixel domain via quiet_pixel.
module hdmi_background_quiet(
    input  wire ref_clk,
    input  wire pixel_clk,
    input  wire rst_n,
    input  wire pixel_reset,
    input  wire pattern_key_n,
    input  wire quiet_key_n,
    output wire quiet_ref,
    output wire quiet_pixel
);
    reg boot_quiet = 1'b0;
    always @(posedge ref_clk)
        if (!rst_n) boot_quiet <= !pattern_key_n && !quiet_key_n;

    assign quiet_ref = boot_quiet;

    (* ASYNC_REG = "TRUE" *) reg [1:0] quiet_sync = 2'b00;
    always @(posedge pixel_clk or posedge pixel_reset)
        if (pixel_reset) quiet_sync <= 2'b00;
        else quiet_sync <= {quiet_sync[0], boot_quiet};

    assign quiet_pixel = quiet_sync[1];
endmodule
