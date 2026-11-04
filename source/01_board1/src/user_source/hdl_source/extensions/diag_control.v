// Standalone HDMI diagnostic control (competition task 1, scratch variant).
`default_nettype none
module diag_control #(
    parameter integer EDID_DELAY_CYCLES = 7425000,
    parameter integer HEARTBEAT_HALF_CYCLES = 25000000
)(
    input  wire        ref_clk,
    input  wire        pixel_clk,
    input  wire        rst_n,
    input  wire        pll_locked,
    input  wire        edid_valid,
    output wire        pixel_rst,
    output reg         edid_trigger,
    output wire [23:0] display_code
);

    localparam integer CNT_W = 24;
    localparam integer HB_W  = 25;

    /* ---- pixel domain: async assertion, two-clock synchronous release ---- */
    reg [1:0] rst_sync;
    always @(posedge pixel_clk or negedge rst_n or negedge pll_locked)
        if (!rst_n || !pll_locked) rst_sync <= 2'b00;
        else                        rst_sync <= {rst_sync[0], 1'b1};

    assign pixel_rst = ~rst_sync[1];

    /* ---- pixel domain: one EDID trigger after fixed delay ---- */
    reg [CNT_W-1:0] edid_cnt;
    reg             edid_done;
    always @(posedge pixel_clk or posedge pixel_rst)
        if (pixel_rst) begin
            edid_cnt     <= {CNT_W{1'b0}};
            edid_done    <= 1'b0;
            edid_trigger <= 1'b0;
        end else if (!edid_done) begin
            edid_trigger <= (edid_cnt == EDID_DELAY_CYCLES[CNT_W-1:0] - 1);
            if (edid_cnt == EDID_DELAY_CYCLES[CNT_W-1:0]) edid_done <= 1'b1;
            else                                         edid_cnt  <= edid_cnt + 1'b1;
        end else edid_trigger <= 1'b0;

    /* ---- pixel domain: latch EDID seen since pixel reset ---- */
    reg edid_seen;
    always @(posedge pixel_clk or posedge pixel_rst)
        if (pixel_rst)    edid_seen <= 1'b0;
        else if (edid_valid) edid_seen <= 1'b1;

    /* ---- ref domain: two-flop synchronizers + free heartbeat ---- */
    reg [1:0] edid_sync, pll_sync;
    always @(posedge ref_clk or negedge rst_n)
        if (!rst_n) begin
            edid_sync <= 2'b00;
            pll_sync  <= 2'b00;
        end else begin
            edid_sync <= {edid_sync[0], edid_seen};
            pll_sync  <= {pll_sync[0],  pll_locked};
        end

    reg [HB_W-1:0] hb_cnt;
    reg            hb;
    always @(posedge ref_clk or negedge rst_n)
        if (!rst_n) begin
            hb_cnt <= {HB_W{1'b0}};
            hb     <= 1'b0;
        end else if (hb_cnt == HEARTBEAT_HALF_CYCLES[HB_W-1:0] - 1) begin
            hb_cnt <= {HB_W{1'b0}};
            hb     <= ~hb;
        end else hb_cnt <= hb_cnt + 1'b1;

    assign display_code = {12'h720, 3'b000, pll_sync[1],
                           3'b000, edid_sync[1], 3'b000, hb};

endmodule
`default_nettype wire
