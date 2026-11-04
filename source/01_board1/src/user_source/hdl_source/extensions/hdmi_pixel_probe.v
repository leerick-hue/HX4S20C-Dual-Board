// hdmi_pixel_probe.v — diagnostic-only pixel-path selector (Verilog-2001).
// Hold physical KEY2 (pattern_key_n low) during the KEY1 reset (rst_n low) to
// select downstream native color-bar output; default is normal media passthrough.
// Tests and top-level integration are owned by the lead.
module hdmi_pixel_probe #(
    parameter WIDTH = 1280
) (
    input  wire        ref_clk,
    input  wire        pixel_clk,
    input  wire        rst_n,
    input  wire        pixel_reset,
    input  wire        pattern_key_n,
    input  wire        native_hs,
    input  wire        native_vs,
    input  wire        native_de,
    input  wire        media_hs,
    input  wire        media_vs,
    input  wire        media_de,
    input  wire [23:0] media_rgb,
    output wire        enabled_ref,
    output wire        enabled_pixel,
    output wire        out_hs,
    output wire        out_vs,
    output wire        out_de,
    output wire [23:0] out_rgb
);

    localparam integer XW = $clog2(WIDTH);

    // ------------------------------------------------------------------
    // Boot selector: sampled on ref_clk only while rst_n is held low,
    // then frozen (held) for the rest of the run.
    // ------------------------------------------------------------------
    reg boot_pattern = 1'b0;
    always @(posedge ref_clk) begin
        if (!rst_n)
            boot_pattern <= ~pattern_key_n;
    end

    assign enabled_ref = boot_pattern;

    // ------------------------------------------------------------------
    // Two-FF asynchronous-assert / synchronous-release CDC into pixel_clk.
    // ------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_ff = 2'b00;
    always @(posedge pixel_clk or posedge pixel_reset) begin
        if (pixel_reset)
            sync_ff <= 2'b00;
        else
            sync_ff <= {sync_ff[0], boot_pattern};
    end

    assign enabled_pixel = sync_ff[1];

    // ------------------------------------------------------------------
    // Fixed full-height vertical RGB bars generated from native timing.
    // Eight equal slices, left to right:
    //   ffffff, ffff00, 00ffff, 00ff00, ff00ff, ff0000, 0000ff, 000000
    // Seven constant threshold comparisons, no variable div/mul.
    // ------------------------------------------------------------------
    function [23:0] bar_color;
        input [XW-1:0] x;
        begin
            if      (x < (1 * WIDTH) / 8) bar_color = 24'hffffff;
            else if (x < (2 * WIDTH) / 8) bar_color = 24'hffff00;
            else if (x < (3 * WIDTH) / 8) bar_color = 24'h00ffff;
            else if (x < (4 * WIDTH) / 8) bar_color = 24'h00ff00;
            else if (x < (5 * WIDTH) / 8) bar_color = 24'hff00ff;
            else if (x < (6 * WIDTH) / 8) bar_color = 24'hff0000;
            else if (x < (7 * WIDTH) / 8) bar_color = 24'h0000ff;
            else                            bar_color = 24'h000000;
        end
    endfunction

    reg [XW-1:0] x_cnt;
    reg          bar_hs;
    reg          bar_vs;
    reg          bar_de;
    reg  [23:0]  bar_rgb;

    always @(posedge pixel_clk or posedge pixel_reset) begin
        if (pixel_reset) begin
            x_cnt   <= {XW{1'b0}};
            bar_hs  <= 1'b1;
            bar_vs  <= 1'b1;
            bar_de  <= 1'b0;
            bar_rgb <= 24'd0;
        end else begin
            if (native_de)
                x_cnt <= (x_cnt == WIDTH - 1) ? {XW{1'b0}} : x_cnt + 1'b1;
            else
                x_cnt <= {XW{1'b0}};

            bar_hs  <= native_hs;
            bar_vs  <= native_vs;
            bar_de  <= native_de;
            bar_rgb <= native_de ? bar_color(x_cnt) : 24'd0;
        end
    end

    // ------------------------------------------------------------------
    // Output mux: registered bars when selected; otherwise media stream
    // passes through combinationally with zero added latency.
    // No frame-memory reads; incoming stream is never modified.
    // ------------------------------------------------------------------
    assign out_hs   = enabled_pixel ? bar_hs  : media_hs;
    assign out_vs   = enabled_pixel ? bar_vs  : media_vs;
    assign out_de   = enabled_pixel ? bar_de  : media_de;
    assign out_rgb  = enabled_pixel ? bar_rgb : media_rgb;

endmodule
