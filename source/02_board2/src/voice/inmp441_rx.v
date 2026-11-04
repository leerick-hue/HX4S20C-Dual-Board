// INMP441, 16 kHz mono, 24-bit I2S in two 32-clock channels.
// Source: TDK/InvenSense DS-INMP441-00 Rev1.1, pp10-12.
// L/R=GND selects CHANNEL=0; L/R=VDD selects CHANNEL=1.
// The mic has zero output during its first 2^18 SCKs (~256 ms at 1.024 MHz).
// No PLL/generated FPGA clock: all logic uses clk; output clocks use enables.
module inmp441_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SAMPLE_HZ = 16000,
    parameter integer CHANNEL = 0,
    parameter integer GAIN_SHIFT = 0
)(
    input wire clk,
    input wire rst_n,
    input wire mic_sd,
    output reg mic_sck,
    output reg mic_ws,
    output reg pcm_valid,
    output reg signed [15:0] pcm_sample,
    output reg [31:0] sample_count,
    output reg signed [23:0] pcm24_debug
);
    // Two edges/SCK * 64 SCK/stereo frame. Fractional accumulator avoids the
    // rate error of integer dividing 50 MHz by 1.024/2.048 MHz. Defaults have
    // 24/25 clk per half-SCK and exactly 16000 WS frames per second on average.
    localparam integer EDGE_HZ = 128*SAMPLE_HZ;
    localparam integer GAIN = GAIN_SHIFT<0 ? 0 : (GAIN_SHIFT>8 ? 8 : GAIN_SHIFT);
    reg [31:0] edge_phase;
    wire [32:0] edge_sum = {1'b0,edge_phase} + EDGE_HZ;
    wire edge_enable = edge_sum >= CLK_HZ;
    reg [5:0] bit_slot, sampled_slot;
    (* ASYNC_REG="TRUE" *) reg [1:0] sd_sync;
    reg [2:0] sample_delay;
    reg [23:0] shift;
    wire [23:0] next_word = {shift[22:0],sd_sync[1]};

    // PCM24 signed arithmetic >>>8, optional 0..8-bit gain, then PCM16 saturation.
    // Truncation deliberately ignores low 8 bits at gain=0; no unsigned slicing
    // or rounding can turn -1/negative near-zero into a positive value.
    function signed [15:0] to_pcm16;
        input signed [23:0] word24;
        reg signed [31:0] amplified, scaled;
        begin
            amplified=$signed({{8{word24[23]}},word24}) <<< GAIN;
            scaled=amplified >>> 8;
            if(scaled>32'sd32767) to_pcm16=16'sh7fff;
            else if(scaled < -32'sd32768) to_pcm16=16'sh8000;
            else to_pcm16=scaled[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            edge_phase<=0; mic_sck<=0; mic_ws<=0;
            bit_slot<=0; sampled_slot<=0;
            sd_sync<=0; sample_delay<=0; shift<=0;
            pcm_valid<=0; pcm_sample<=0; pcm24_debug<=0; sample_count<=0;
        end else begin
            sd_sync<={sd_sync[0],mic_sd};
            sample_delay<={sample_delay[1:0],1'b0};
            pcm_valid<=0;
            if(edge_enable) begin
                edge_phase<=edge_sum-CLK_HZ;
                mic_sck<=!mic_sck;
                if(mic_sck) begin
                    // WS changes only on a FALLING SCK edge. Slot 0/32 is the
                    // I2S dummy bit; its following falling edge starts the MSB.
                    bit_slot<=bit_slot+1'b1;
                    mic_ws<=((bit_slot+6'd1) & 6'd32)!=0;
                end else begin
                    // The SD synchronizer is allowed a further three clk before
                    // consumption, still >400 ns ahead of the next SCK falling
                    // edge. The saved slot keeps the data/clock enables aligned.
                    sampled_slot<=bit_slot;
                    sample_delay<=3'b001;
                end
            end else edge_phase<=edge_sum[31:0];

            if(sample_delay[2] && sampled_slot[5]==(CHANNEL!=0) &&
               sampled_slot[4:0]>=1 && sampled_slot[4:0]<=24) begin
                shift<=next_word;
                if(sampled_slot[4:0]==24) begin
                    pcm24_debug<=next_word;
                    pcm_sample<=to_pcm16(next_word);
                    pcm_valid<=1; sample_count<=sample_count+1'b1;
                end
            end
        end
    end
endmodule
