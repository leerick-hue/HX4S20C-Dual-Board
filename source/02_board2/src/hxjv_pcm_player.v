`timescale 1ns/1ps
// HXJV soundtrack player: interleaved stereo PCM16 at 48 kHz, fetched from the
// TF card a sector (128 sample frames) at a time and played through the HDMI
// audio channel.
//
// Two clocks are involved on purpose. Sectors arrive on the 40 MHz decode clock
// (that is where the sector mailbox lives) and samples leave on the 74.25 MHz
// pixel clock, because the HDMI core stamps audio with the pixel clock. An
// asynchronous FIFO joins them. Position is kept against the player's own 48 kHz
// presentation clock, so pause, replay and looping re-seek instead of drifting.
module hxjv_pcm_player (
    input  wire               decode_clk,
    input  wire               decode_rst,
    input  wire               enable,           // catalogue ready and audio_present
    input  wire [31:0]        audio_start_lba,  // first PCM sector
    input  wire [31:0]        audio_frames,     // sample frames in the stream
    input  wire [31:0]        clip_position,    // 48 kHz samples since clip start
    output wire               sec_req,
    output reg  [31:0]        sec_addr,
    input  wire               sec_valid,
    input  wire [7:0]         sec_data,
    input  wire               sec_end,
    output reg                buf_we,
    output reg  [31:0]        buf_di,
    input  wire               buf_full,
    input  wire [8:0]         buf_wrusedw,
    output reg                buf_aclr,
    output reg  [3:0]         fetch_state,

    input  wire               pixel_clk,
    input  wire               pixel_rst,
    input  wire               audio_on,
    input  wire               paused,
    input  wire               buf_empty,
    input  wire [31:0]        buf_dout,
    output reg                buf_re,
    output reg  signed [23:0] pcm_left,
    output reg  signed [23:0] pcm_right,
    output reg                pcm_valid,
    output reg                acr_valid,
    output wire      [19:0]   acr_n,
    output wire      [19:0]   acr_cts,
    output reg  signed [31:0] sync_error
);
    localparam F_IDLE = 2'd0, F_REQ = 2'd1, F_DATA = 2'd2;
    localparam RESYNC = 4'd8;

    // ---------------- fetch side (decode clock) ----------------
    reg [1:0]  fstate;
    reg [2:0]  byte_count;
    reg [31:0] word_build;
    reg [31:0] fetched;      // sample frames pulled from the card
    reg [8:0]  skip;         // frames to drop at the start of a re-seeked sector
    reg [3:0]  flush_left;

    wire [31:0] played = fetched - {22'd0, buf_wrusedw};
    wire signed [32:0] error = {1'b0, played} - {1'b0, clip_position};
    wire too_far   = (error  > 33'sd320);
    wire too_late  = (error < -33'sd320);
    wire [31:0] target = clip_position;
    wire need_room = (buf_wrusedw < 9'd320) && !buf_full;

    assign sec_req = (fstate == F_DATA);

    always @(posedge decode_clk or posedge decode_rst) begin
        if (decode_rst) begin
            fstate <= F_IDLE; sec_addr <= 0; buf_we <= 0; buf_di <= 0;
            fetched <= 0; skip <= 0; byte_count <= 0; word_build <= 0;
            buf_aclr <= 0; flush_left <= 0; sync_error <= 0; fetch_state <= 0;
        end else begin
            buf_we <= 0;
            sync_error <= error[31:0];
            case (fstate)
                F_IDLE: begin
                    if (!enable) begin
                        fetched <= 0; skip <= 0; fetch_state <= 0;
                    end else if ((too_far || too_late) && flush_left == 0) begin
                        // Restart the buffer at the presentation position. The
                        // sector that contains it is re-fetched and its leading
                        // frames are dropped, so the join stays frame accurate.
                        buf_aclr  <= 1;
                        flush_left<= 4;
                        fetched   <= target;
                        skip      <= 9'd0;
                        fetch_state<= RESYNC;
                    end else if (need_room) begin
                        sec_addr  <= audio_start_lba + (fetched >> 7);
                        skip      <= fetched[6:0];
                        fstate    <= F_DATA;
                        fetch_state<= 4'd1;
                    end
                end
                F_DATA: begin
                    if (sec_valid) begin
                        word_build <= {sec_data, word_build[31:8]};
                        byte_count <= byte_count + 3'd1;
                        if (byte_count == 3'd3) begin
                            byte_count <= 0;
                            if (skip != 0) begin
                                skip <= skip - 1'b1;
                            end else if (!buf_full) begin
                                buf_we <= 1;
                                buf_di <= {sec_data, word_build[31:8]};
                            end
                            fetched <= fetched + 1'b1;
                        end
                    end
                    if (sec_end) begin
                        fstate <= F_IDLE;
                        fetch_state <= 4'd2;
                    end
                end
                default: fstate <= F_IDLE;
            endcase
            if (flush_left != 0) begin
                flush_left <= flush_left - 3'd1;
                if (flush_left == 4'd1) begin
                    buf_aclr <= 0;
                    fstate   <= F_IDLE;
                end
            end
        end
    end

    // ---------------- play side (pixel clock) ----------------
    // Same accumulator as the reference tone: +8 per cycle, rollover at 12375
    // gives exactly 48000 ticks per second from a 74.25 MHz clock.
    reg  [13:0] accumulator;
    reg  [5:0]  phase;
    wire [13:0] advanced = accumulator + 14'd8;
    wire        tick     = (advanced >= 14'd12375);

    assign acr_n   = 20'd6144;
    assign acr_cts = 20'd74250;

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst) begin
            accumulator <= 0; phase <= 0; pcm_valid <= 0; acr_valid <= 0;
            pcm_left <= 0; pcm_right <= 0; buf_re <= 0;
        end else if (!audio_on || paused) begin
            accumulator <= 0; phase <= 0; pcm_valid <= 0; acr_valid <= 0;
            pcm_left <= 0; pcm_right <= 0; buf_re <= 0;
        end else begin
            pcm_valid <= 0;
            acr_valid <= 0;
            if (tick) begin
                accumulator <= advanced - 14'd12375;
                buf_re <= !buf_empty;
                if (!buf_empty) begin
                    pcm_valid <= 1;
                    pcm_left  <= {buf_dout[7:0],  buf_dout[15:8],  8'd0};
                    pcm_right <= {buf_dout[23:16], buf_dout[31:24], 8'd0};
                    if (phase == 6'd47) begin
                        phase     <= 0;
                        acr_valid <= 1;
                    end else phase <= phase + 6'd1;
                end
            end else begin
                buf_re <= 0;
                accumulator <= advanced;
            end
        end
    end
endmodule
