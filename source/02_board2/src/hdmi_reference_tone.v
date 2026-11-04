`timescale 1ns/1ps
// HDMI audio reference tone, self-contained, no multiply/divide/ROM/PLL.
//
// Sample tick: accumulator gains 8 every enabled cycle and rolls over at 12375,
// so the tick rate is 74250000 * 8 / 12375 = 48000 Hz exactly.  12375 = 8 * 1546.875,
// hence gaps of 1546/1547 pixel cycles average to 74250000/48000 = 1546.875.
// The remainder is carried in the accumulator, so the phase error never accumulates.
//
// phase counts the 48 samples of one tone period (48000 Hz / 1000 Hz = 48).
// Samples 0..23 are +2^20 and 24..47 are -2^20, i.e. a 1 kHz bipolar square at
// 2^20 / 2^23 = 1/8 full scale.  Every 48th tick (phase 47 -> 0) pulses acr_valid;
// 48 ticks span 48 * 1546.875 = 74250 cycles, matching acr_cts, with acr_n = 6144.
module hdmi_reference_tone (
    input  wire               clk,        // 74.25 MHz pixel clock
    input  wire               rst,        // active high, async
    input  wire               enable,
    output reg                pcm_valid,
    output reg  signed [23:0] pcm_left,
    output reg  signed [23:0] pcm_right,
    output reg                acr_valid,
    output wire      [19:0]   acr_n,
    output wire      [19:0]   acr_cts
);
    reg [13:0] accumulator;
    reg [5:0]  phase;

    wire [13:0] advanced = accumulator + 14'd8;
    wire        tick     = (advanced >= 14'd12375);

    assign acr_n   = 20'd6144;
    assign acr_cts = 20'd74250;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 14'd0;
            phase       <= 6'd0;
            pcm_valid   <= 1'b0;
            acr_valid   <= 1'b0;
            pcm_left    <= 24'sh000000;
            pcm_right   <= 24'sh000000;
        end else if (!enable) begin
            // Same clear as reset, so re-enabling always restarts deterministically.
            accumulator <= 14'd0;
            phase       <= 6'd0;
            pcm_valid   <= 1'b0;
            acr_valid   <= 1'b0;
            pcm_left    <= 24'sh000000;
            pcm_right   <= 24'sh000000;
        end else begin
            pcm_valid <= 1'b0;
            acr_valid <= 1'b0;
            if (tick) begin
                accumulator <= advanced - 14'd12375;
                pcm_valid   <= 1'b1;
                if (phase < 6'd24) begin
                    pcm_left  <= 24'sh100000;
                    pcm_right <= 24'sh100000;
                end else begin
                    pcm_left  <= -24'sh100000;
                    pcm_right <= -24'sh100000;
                end
                if (phase == 6'd47) begin
                    phase     <= 6'd0;
                    acr_valid <= 1'b1;
                end else begin
                    phase <= phase + 6'd1;
                end
            end else begin
                // No-tick cycle: PCM data holds its previous value.
                accumulator <= advanced;
            end
        end
    end
endmodule
