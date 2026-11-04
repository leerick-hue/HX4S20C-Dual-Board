`timescale 1ns/1ps
// Viewport mask for the 1280x720 screen. Photo mode lets every pixel through,
// video mode only the centred VIDEO_WIDTH x VIDEO_HEIGHT window.
// Pixel position comes from free-running DE/VS counters: no multipliers, no
// line/frame buffer, and the mask stays combinational so it describes the very
// pixel that is clocked in at the same rising edge. video_mode is re-sampled
// only while VS is active, so one frame always runs on a single mode.
module media_viewport #(
    parameter SCREEN_WIDTH  = 1280,
    parameter SCREEN_HEIGHT = 720,
    parameter VIDEO_WIDTH   = 640,
    parameter VIDEO_HEIGHT  = 480,
    parameter VS_POLARITY   = 1
)(
    input  wire clk,
    input  wire rst,
    input  wire de,
    input  wire vs,
    input  wire video_mode,
    output wire pixel_mask
);
    localparam X_BITS = $clog2(SCREEN_WIDTH  + 1);
    localparam Y_BITS = $clog2(SCREEN_HEIGHT + 1);
    localparam OFF_X = (SCREEN_WIDTH  - VIDEO_WIDTH)  / 2;
    localparam OFF_Y = (SCREEN_HEIGHT - VIDEO_HEIGHT) / 2;
    localparam END_X = OFF_X + VIDEO_WIDTH  - 1;
    localparam END_Y = OFF_Y + VIDEO_HEIGHT - 1;

    reg [X_BITS-1:0] x;
    reg [Y_BITS-1:0] y;     // position of the pixel being clocked in right now
    reg        in_line;      // an active DE run has not ended yet
    reg        mode;         // video_mode held for the whole frame

    wire within_window = (x >= OFF_X) && (x <= END_X) && (y >= OFF_Y) && (y <= END_Y);
    assign pixel_mask = de & (~mode | within_window);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 0; y <= 0; in_line <= 1'b0; mode <= 1'b0;
        end else if (vs == VS_POLARITY) begin
            x <= 0; y <= 0; in_line <= 1'b0; mode <= video_mode;
        end else if (de) begin
            x <= x + 1'b1;
            in_line <= 1'b1;
        end else begin
            x <= 0;
            if (in_line) begin
                y <= y + 1'b1;
                in_line <= 1'b0;
            end
        end
    end
endmodule
