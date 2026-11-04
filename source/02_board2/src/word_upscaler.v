`timescale 1ns/1ps
// Read side of the adaptive scaler: horizontal word expansion.
// Each buffered word holds two adjacent source pixels (low half = even column,
// high half = odd column) and becomes 3 destination words for 4:3
// {a,a},{b,a},{b,b} or 4 for 16:9 {a,a},{a,a},{b,b},{b,b}.
// The queue keeps the frame FIFO's read contract (word_data valid one cycle
// after word_read, held until the following request) so rgb565_unpack and
// video_delay downstream need no changes. The next source word is fetched while
// the current group is still being pushed, sustaining one word per clock, which
// the scanout needs: 960 visible pixels consume 480 words in 960 clocks.
module word_upscaler #(
    parameter integer DEPTH = 16
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        aspect_16x9,
    // source side: the read port of the frame FIFO
    output reg         src_read,
    input  wire [31:0] src_data,
    input  wire        src_empty,
    // destination side: towards rgb565_unpack
    input  wire        word_read,
    output reg  [31:0] word_data,
    output wire        word_empty
);
    wire [2:0] n = aspect_16x9 ? 3'd4 : 3'd3;

    reg [31:0] queue [0:DEPTH-1];
    reg [3:0]  wptr, rptr;
    reg [4:0]  count;
    reg [1:0]  fetch;
    reg        have_next;
    reg [31:0] held, next_word;
    reg [2:0]  pending, index;

    // Low half is the even destination pixel, high half the odd one.
    wire [15:0] lo = (index < 3'd2) ? held[15:0] : held[31:16];
    wire [15:0] hi = (index < (aspect_16x9 ? 3'd2 : 3'd1)) ? held[15:0] : held[31:16];
    wire [31:0] expanded = {hi, lo};

    wire push      = (pending != 3'd0) && (count < DEPTH[4:0]);
    wire pop       = word_read && (count != 5'd0);
    wire can_start = (fetch == 2'd0) && !have_next && !src_empty &&
                     ({1'b0, count} + {2'd0, n} <= DEPTH[5:0]);
    assign word_empty = (count == 5'd0);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            src_read  <= 0;
            fetch     <= 0;
            have_next <= 0;
            held      <= 0;
            next_word <= 0;
            pending   <= 0;
            index     <= 0;
            wptr      <= 0;
            rptr      <= 0;
            count     <= 0;
            word_data <= 0;
        end else begin
            // Fetch pipeline: one request clock, then take the response on the
            // following clock. src_read must be high for exactly one cycle.
            case (fetch)
                2'd0: begin src_read <= can_start; if (can_start) fetch <= 2'd1; end
                2'd1: begin src_read <= 1'b0;      fetch <= 2'd2; end
                2'd2: begin next_word <= src_data; have_next <= 1'b1; fetch <= 2'd0; end
            endcase

            // Hand the fetched word over once the current group has drained.
            if (pending == 3'd0) begin
                if (have_next) begin
                    held      <= next_word;
                    pending   <= n;
                    index     <= 0;
                    have_next <= 0;
                end
            end

            if (push) begin
                queue[wptr] <= expanded;
                wptr        <= wptr + 1'b1;
                index       <= index + 1'b1;
                pending     <= pending - 1'b1;
            end
            if (pop) begin
                word_data <= queue[rptr];
                rptr      <= rptr + 1'b1;
            end
            case ({push, pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
