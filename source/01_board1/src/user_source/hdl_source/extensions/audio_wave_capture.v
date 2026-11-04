`timescale 1ns/1ps
// Capture actual signed PCM as 128-point, 8-bit waveform snapshots.
//
// Reset contract: both resets must assert together from one asynchronous source;
// each may release synchronously in its own domain at a different time.
//
// A full bank is held until the pixel domain selects it at vblank_start. Its
// acknowledgement crosses back before the audio domain reuses the OLD display
// bank. While waiting, PCM samples are ignored. Once acknowledged, the next 128
// pcm_valid samples form a new snapshot; a partial snapshot is never published.
//
// Read latency: wave_addr is sampled at a pixel_clk rising edge; wave_sample is
// available just after that edge (one synchronous RAM read cycle). At a commit
// edge the read uses the new bank immediately. Delay pixel coordinates/control
// by the same cycle. wave_valid stays high after the first commit until reset.
// pcm_sample[23:16] preserves signed amplitude, including -128 and +127.
module audio_wave_capture (
    input  wire               audio_clk,
    input  wire               audio_rst_n,
    input  wire signed [23:0] pcm_sample,
    input  wire               pcm_valid,
    input  wire               pixel_clk,
    input  wire               pixel_rst_n,
    input  wire               vblank_start,
    input  wire [6:0]         wave_addr,
    output wire signed [7:0]  wave_sample,
    output reg                wave_valid
);
    // One independent write clock and one synchronous read clock; no RAM reset.
    reg [7:0] wave_mem [0:255];
    reg [7:0] wave_read;
    reg [6:0] write_index;
    reg write_bank;
    reg publish_pending;
    reg request_toggle;
    reg display_bank;
    reg acknowledge_toggle;
    (* ASYNC_REG = "TRUE" *) reg [1:0] acknowledge_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync;

    wire write_enable = audio_rst_n && !publish_pending && pcm_valid;
    wire commit = pixel_rst_n && vblank_start &&
                  (request_sync[1] != acknowledge_toggle);
    // Initial write bank is 0 and the first request toggle is 1. Thus the
    // published bank is always the complement of the request toggle; no
    // independently synchronized multi-bit bank/address bus is required.
    wire read_bank = commit ? ~request_sync[1] : display_bank;

    always @(posedge audio_clk) begin
        if (write_enable)
            wave_mem[{write_bank, write_index}] <= pcm_sample[23:16];
    end

    always @(posedge pixel_clk) begin
        wave_read <= wave_mem[{read_bank, wave_addr}];
    end
    assign wave_sample = wave_valid ? $signed(wave_read) : 8'sd0;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            acknowledge_sync <= 2'b00;
            write_index <= 7'd0;
            write_bank <= 1'b0;
            publish_pending <= 1'b0;
            request_toggle <= 1'b0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
            if (publish_pending) begin
                if (acknowledge_sync[1] == request_toggle) begin
                    publish_pending <= 1'b0;
                    write_bank <= ~write_bank;
                end
            end else if (pcm_valid) begin
                if (write_index == 7'd127) begin
                    write_index <= 7'd0;
                    request_toggle <= ~request_toggle;
                    publish_pending <= 1'b1;
                end else begin
                    write_index <= write_index + 1'b1;
                end
            end
        end
    end

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            request_sync <= 2'b00;
            display_bank <= 1'b1;
            acknowledge_toggle <= 1'b0;
            wave_valid <= 1'b0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (commit) begin
                display_bank <= ~request_sync[1];
                acknowledge_toggle <= request_sync[1];
                wave_valid <= 1'b1;
            end
        end
    end
endmodule
