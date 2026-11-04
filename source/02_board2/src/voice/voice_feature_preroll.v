// voice_feature_preroll
// Synchronous replay-history (pre-roll) buffer.
//   * ring of DEPTH most recent frame_data words, chronological, oldest overwritten
//   * replay_start freezes a snapshot of the occupancy and streams oldest -> newest
//   * single synchronous-read BRAM history: no reset of memory contents
`default_nettype none

module voice_feature_preroll #(
    parameter integer DEPTH     = 8,
    parameter integer DATA_BITS = 80
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 clear,
    input  wire                 frame_valid,
    input  wire [DATA_BITS-1:0] frame_data,
    input  wire                 replay_start,
    input  wire                 replay_ready,
    output reg  [DATA_BITS-1:0] replay_data,
    output reg                  replay_valid,
    output reg                  busy,
    output reg                  overrun
);

    localparam integer ADDR_BITS = $clog2(DEPTH);
    localparam integer CNT_BITS  = ADDR_BITS + 1;

    localparam [CNT_BITS-1:0] FULL_CNT = DEPTH;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_FETCH = 2'd1;
    localparam [1:0] ST_WAIT  = 2'd2;
    localparam [1:0] ST_HOLD  = 2'd3;

    // replay history: contents are never reset, only pointers/counters/flags are
    (* ram_style = "bram" *) reg [DATA_BITS-1:0] history [0:DEPTH-1];

    reg [1:0]           state;
    reg [ADDR_BITS-1:0] wr_ptr;
    reg [CNT_BITS-1:0]  count;
    reg [ADDR_BITS-1:0] rd_ptr;
    reg [ADDR_BITS-1:0] ram_addr;
    reg [CNT_BITS-1:0]  total;
    reg [CNT_BITS-1:0]  idx;
    reg [DATA_BITS-1:0] ram_q;

    wire capturing = frame_valid && !busy && !clear;
    wire handshook = replay_valid && replay_ready;
    wire last_item = (idx + 1'b1 == total);
    // DEPTH is a power of two and count saturates at DEPTH, so the low ADDR_BITS of
    // count is the back-offset from wr_ptr (0 when full == oldest slot).
    wire [ADDR_BITS-1:0] oldest = wr_ptr - count[ADDR_BITS-1:0];

    // ------------------------------------------------------------- history RAM
    always @(posedge clk) begin
        if (capturing) begin
            history[wr_ptr] <= frame_data;
        end
    end

    always @(posedge clk) begin
        ram_q <= history[ram_addr];
    end

    // ------------------------------------------------------------ control path
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            wr_ptr       <= {ADDR_BITS{1'b0}};
            rd_ptr       <= {ADDR_BITS{1'b0}};
            ram_addr     <= {ADDR_BITS{1'b0}};
            count        <= {CNT_BITS{1'b0}};
            total        <= {CNT_BITS{1'b0}};
            idx          <= {CNT_BITS{1'b0}};
            replay_valid <= 1'b0;
            replay_data  <= {DATA_BITS{1'b0}};
            busy         <= 1'b0;
            overrun      <= 1'b0;
        end else if (clear) begin
            state        <= ST_IDLE;
            wr_ptr       <= {ADDR_BITS{1'b0}};
            rd_ptr       <= {ADDR_BITS{1'b0}};
            count        <= {CNT_BITS{1'b0}};
            total        <= {CNT_BITS{1'b0}};
            idx          <= {CNT_BITS{1'b0}};
            replay_valid <= 1'b0;
            replay_data  <= {DATA_BITS{1'b0}};
            busy         <= 1'b0;
            overrun      <= 1'b0;
        end else begin
            if (capturing) begin
                wr_ptr <= wr_ptr + 1'b1;
                if (count < FULL_CNT) begin
                    count <= count + 1'b1;
                end
            end else if (frame_valid && busy) begin
                overrun <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    replay_valid <= 1'b0;
                    if (replay_start && (count != {CNT_BITS{1'b0}})) begin
                        busy     <= 1'b1;
                        total    <= count;
                        idx      <= {CNT_BITS{1'b0}};
                        rd_ptr   <= oldest;
                        ram_addr <= oldest;
                        state    <= ST_FETCH;
                    end
                end

                ST_FETCH: begin
                    // address registered on the previous edge: read is issued now
                    replay_valid <= 1'b0;
                    state        <= ST_WAIT;
                end

                ST_WAIT: begin
                    // synchronous-read latency: ram_q settles at this edge
                    replay_valid <= 1'b0;
                    state        <= ST_HOLD;
                end

                ST_HOLD: begin
                    replay_valid <= 1'b1;
                    replay_data  <= ram_q;
                    if (handshook) begin
                        replay_valid <= 1'b0;
                        if (last_item) begin
                            busy  <= 1'b0;
                            idx   <= {CNT_BITS{1'b0}};
                            state <= ST_IDLE;
                        end else begin
                            idx      <= idx + 1'b1;
                            rd_ptr   <= rd_ptr + 1'b1;
                            ram_addr <= rd_ptr + 1'b1;
                            state    <= ST_FETCH;
                        end
                    end
                end

                default: begin
                    state        <= ST_IDLE;
                    busy         <= 1'b0;
                    replay_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
