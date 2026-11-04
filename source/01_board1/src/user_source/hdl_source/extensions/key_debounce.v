`timescale 1ns/1ps
module key_debounce #(
    parameter integer STABLE_CYCLES = 1_000_000 // 20 ms at 50 MHz
)(
    input wire clk, input wire rst_n, input wire key_n,
    output reg pressed, output reg down
);
    localparam integer CW = (STABLE_CYCLES < 2) ? 1 : $clog2(STABLE_CYCLES);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_n;
    localparam integer LIMIT_VALUE=STABLE_CYCLES-1;
    localparam [CW-1:0] LIMIT=LIMIT_VALUE[CW-1:0];
    reg [CW-1:0] count;
    wire sampled_down = !sync_n[1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_n <= 2'b11; count <= 0; pressed <= 0; down <= 0;
        end else begin
            sync_n <= {sync_n[0], key_n};
            pressed <= 0;
            if (sampled_down == down) count <= 0;
            else if (count == LIMIT) begin
                count <= 0;
                down <= sampled_down;
                pressed <= sampled_down;
            end else count <= count + 1'b1;
        end
    end
endmodule
