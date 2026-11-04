// Active-low 4x4 matrix keypad scanner with synchronised columns and debounce.
// A key is reported once after a debounced press and is re-armed only after a
// debounced all-keys-released scan. key_valid/key_code form a one-entry buffer.
module keypad_scan_4x4 #(
    parameter integer SCAN_CYCLES = 50000,
    parameter integer DEBOUNCE_SCANS = 5
)(
    input  wire       clk,
    input  wire       rst_n,
    output wire [3:0] row_n,
    input  wire [3:0] col_n,
    output reg        key_valid,
    input  wire       key_ready,
    output reg  [3:0] key_code,
    output reg        key_overflow
);
    function integer clog2;
        input integer value;
        integer temp;
        begin
            temp = value - 1;
            clog2 = 0;
            while (temp > 0) begin
                temp = temp >> 1;
                clog2 = clog2 + 1;
            end
            if (clog2 < 1) clog2 = 1;
        end
    endfunction

    localparam integer SCAN_PERIOD = (SCAN_CYCLES < 1) ? 1 : SCAN_CYCLES;
    localparam integer DEBOUNCE_PERIOD = (DEBOUNCE_SCANS < 1) ? 1 : DEBOUNCE_SCANS;
    localparam integer SCAN_COUNT_WIDTH = clog2(SCAN_PERIOD);
    localparam integer DEBOUNCE_COUNT_WIDTH = clog2(DEBOUNCE_PERIOD + 1);

    reg [SCAN_COUNT_WIDTH-1:0] scan_count;
    reg [1:0] row_select;
    reg [3:0] col_meta;
    reg [3:0] col_sync;
    reg [3:0] sampled_rows [0:2];

    reg candidate_valid;
    reg [3:0] candidate_code;
    reg [DEBOUNCE_COUNT_WIDTH-1:0] candidate_count;
    reg [DEBOUNCE_COUNT_WIDTH-1:0] release_count;
    reg key_down;

    reg [15:0] pressed_keys;
    reg [1:0] complete_key_count;
    reg [3:0] complete_key_code;

    assign row_n = ~(4'b0001 << row_select);

    // The asynchronous keypad inputs pass through two registers before use.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_meta <= 4'hf;
            col_sync <= 4'hf;
        end else begin
            col_meta <= col_n;
            col_sync <= col_meta;
        end
    end

    // Classify the just-completed matrix. Rows are stored in row-major order,
    // and a low column bit represents a closed key switch, so pressed_keys is
    // active high. Only zero/one/multiple is needed downstream; a bitmap with
    // exactly one set bit has no remaining bit after clearing its lowest one.
    always @* begin
        pressed_keys = ~{col_sync, sampled_rows[2], sampled_rows[1], sampled_rows[0]};
        if (pressed_keys == 16'd0) begin
            complete_key_count = 2'd0;
            complete_key_code = 4'd0;
        end else if ((pressed_keys & (pressed_keys - 16'd1)) == 16'd0) begin
            complete_key_count = 2'd1;
            complete_key_code = {|(pressed_keys & 16'hff00), |(pressed_keys & 16'hf0f0),
                                 |(pressed_keys & 16'hcccc), |(pressed_keys & 16'haaaa)};
        end else begin
            complete_key_count = 2'd2;
            complete_key_code = 4'd0;
        end
    end

    // Hold each selected row for SCAN_PERIOD clocks, then sample its columns.
    // A complete matrix is processed when row 3 has just been sampled.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_count <= {SCAN_COUNT_WIDTH{1'b0}};
            row_select <= 2'd0;
            sampled_rows[0] <= 4'hf;
            sampled_rows[1] <= 4'hf;
            sampled_rows[2] <= 4'hf;
            candidate_valid <= 1'b0;
            candidate_code <= 4'd0;
            candidate_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
            release_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
            key_down <= 1'b0;
            key_valid <= 1'b0;
            key_code <= 4'd0;
            key_overflow <= 1'b0;
        end else begin
            if (key_valid && key_ready)
                key_valid <= 1'b0;

            if (scan_count == SCAN_PERIOD - 1) begin
                scan_count <= {SCAN_COUNT_WIDTH{1'b0}};
                case (row_select)
                    2'd0: begin
                        sampled_rows[0] <= col_sync;
                        row_select <= 2'd1;
                    end
                    2'd1: begin
                        sampled_rows[1] <= col_sync;
                        row_select <= 2'd2;
                    end
                    2'd2: begin
                        sampled_rows[2] <= col_sync;
                        row_select <= 2'd3;
                    end
                    2'd3: begin
                        row_select <= 2'd0;

                        if (complete_key_count == 0) begin
                            candidate_valid <= 1'b0;
                            candidate_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
                            if (release_count < DEBOUNCE_PERIOD)
                                release_count <= release_count + 1'b1;
                            if (release_count >= DEBOUNCE_PERIOD - 1) begin
                                release_count <= DEBOUNCE_PERIOD;
                                key_down <= 1'b0;
                            end
                        end else begin
                            release_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
                            if (complete_key_count == 1 && !key_down) begin
                                if (candidate_valid && candidate_code == complete_key_code) begin
                                    if (candidate_count >= DEBOUNCE_PERIOD - 1) begin
                                        candidate_valid <= 1'b0;
                                        candidate_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
                                        key_down <= 1'b1;
                                        if (!key_valid || key_ready) begin
                                            key_valid <= 1'b1;
                                            key_code <= complete_key_code;
                                        end else begin
                                            key_overflow <= 1'b1;
                                        end
                                    end else begin
                                        candidate_count <= candidate_count + 1'b1;
                                    end
                                end else begin
                                    candidate_valid <= 1'b1;
                                    candidate_code <= complete_key_code;
                                    if (DEBOUNCE_PERIOD <= 1) begin
                                        candidate_valid <= 1'b0;
                                        candidate_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
                                        key_down <= 1'b1;
                                        if (!key_valid || key_ready) begin
                                            key_valid <= 1'b1;
                                            key_code <= complete_key_code;
                                        end else begin
                                            key_overflow <= 1'b1;
                                        end
                                    end else begin
                                        candidate_count <= 1;
                                    end
                                end
                            end else begin
                                candidate_valid <= 1'b0;
                                candidate_count <= {DEBOUNCE_COUNT_WIDTH{1'b0}};
                            end
                        end
                    end
                    default: row_select <= 2'd0;
                endcase
            end else begin
                scan_count <= scan_count + 1'b1;
            end
        end
    end
endmodule
