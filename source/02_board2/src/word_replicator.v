`timescale 1ns/1ps
// Write side of the adaptive scaler: vertical replication only.
// One RGB565 word holds two adjacent source pixels, so a source row is exactly
// 160 words. Each word is written once per destination row of the 3x (4:3) or
// 4x (16:9) block, giving a compact buffer of 115200 words per frame for either
// aspect. Horizontal expansion happens on the read side in word_upscaler, which
// keeps total SDRAM traffic below the board-proven 640x480 path (153600 words
// written plus 153600 read per frame).
// The JPEG core hands out pixels in MCU-block order, so the destination comes
// from the pixel's own row and word column, never from a stream counter.
module word_replicator(
    input  wire        clk,
    input  wire        rst,
    input  wire        aspect_16x9,
    input  wire        frame_start,
    input  wire        src_valid,
    output wire        src_ready,
    input  wire [8:0]  src_row,
    input  wire [8:0]  src_word,
    input  wire [31:0] src_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire [20:0] out_addr,
    output wire [31:0] out_data
);
    reg emitting;
    reg [2:0] n_rows;
    reg [20:0] group_base;
    reg [2:0]  row_in_block;
    reg [1:0] collect_col,emit_col;
    reg [31:0] group_data[0:3];

    // (scale * row) * 160 + word column, as shift and add only.
    // 3x: 480*row = 256+128+64+32.  4x: 640*row = 512+128.
    wire [20:0] scaled_row = aspect_16x9 ? {src_row, 9'd0} + {src_row, 7'd0}
                                         : {src_row, 8'd0} + {src_row, 7'd0} +
                                           {src_row, 6'd0} + {src_row, 5'd0};
    assign src_ready = !out_valid;
    assign out_valid = emitting;
    // The controller samples only the first address of each BL4 transaction.
    // Buffer an aligned eight-pixel JPEG row fragment (four 32-bit words),
    // then emit all four adjacent words before moving to the next output row.
    // Source JPEG 8x8/16x16 blocks always start on a four-word boundary.
    wire [20:0] row_base=group_base + {row_in_block,7'd0} + {row_in_block,5'd0};
    assign out_addr={row_base[20:2],emit_col};
    assign out_data=group_data[emit_col];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            emitting     <= 0;
            row_in_block <= 0;
            group_base   <= 0;
            n_rows       <= 3'd3;
            collect_col  <= 0;
            emit_col     <= 0;
        end else if (frame_start) begin
            emitting     <= 0;
            row_in_block <= 0;
            collect_col  <= 0;
            emit_col     <= 0;
        end else if (!emitting) begin
            if (src_valid) begin
                group_data[collect_col]<=src_data;
                collect_col<=collect_col+1'b1;
                if(collect_col==0)begin
                    n_rows<=aspect_16x9 ? 3'd4 : 3'd3;
                    group_base<=scaled_row + {12'd0,src_word};
                end
                if(collect_col==3)begin
                    emitting<=1;
                    row_in_block<=0;
                    emit_col<=0;
                end
            end
        end else if (out_ready) begin
            emit_col<=emit_col+1'b1;
            if(emit_col==3)begin
                if (row_in_block == n_rows - 3'd1) begin
                    row_in_block <= 0;
                    emitting     <= 0;
                end else row_in_block <= row_in_block + 1'b1;
            end
        end
    end
endmodule
