`timescale 1ns/1ps
// Signed 24-bit stereo PCM volume with a sample-accurate gain ramp.
//
// Gain is 0..256 (256 = unity). Target is clamped_level*32 and the gain moves one
// step toward target only after the old gain has been published for a pcm_valid
// sample, so the gain is frozen while pcm_valid is low. out_valid is pcm_valid
// delayed by exactly one cycle; output samples hold between samples.
module audio_volume (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               pcm_valid,
    input  wire signed [23:0] pcm_left,
    input  wire signed [23:0] pcm_right,
    input  wire        [3:0]  volume_level,
    output reg                out_valid,
    output reg signed  [23:0] out_left,
    output reg signed  [23:0] out_right
);
    reg [8:0] effective_gain;

    wire [3:0] level_clamped = (volume_level > 4'd8) ? 4'd8 : volume_level;
    wire [8:0] target        = {level_clamped, 5'd0};   // clamped_level * 32

    wire signed [33:0] gain_signed   = $signed({1'b0, effective_gain});
    wire signed [33:0] left_signed   = pcm_left;
    wire signed [33:0] right_signed  = pcm_right;
    wire signed [33:0] product_left  = left_signed * gain_signed;
    wire signed [33:0] product_right = right_signed * gain_signed;

    // Arithmetic shift truncates toward negative infinity. |product| is bounded by
    // 2^23 * 256, so the quotient always fits in signed 24 bits without wrapping.
    wire signed [33:0] shifted_left  = product_left >>> 8;
    wire signed [33:0] shifted_right = product_right >>> 8;
    wire signed [23:0] scaled_left   = shifted_left[23:0];
    wire signed [23:0] scaled_right  = shifted_right[23:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            effective_gain <= 9'd256;
            out_valid      <= 1'b0;
            out_left       <= 24'sd0;
            out_right      <= 24'sd0;
        end else begin
            out_valid <= pcm_valid;
            if (pcm_valid) begin
                out_left  <= scaled_left;
                out_right <= scaled_right;
                if (effective_gain > target)
                    effective_gain <= effective_gain - 9'd1;
                else if (effective_gain < target)
                    effective_gain <= effective_gain + 9'd1;
            end
        end
    end
endmodule
