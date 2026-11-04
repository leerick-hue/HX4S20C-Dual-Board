`timescale 1ns/1ps
// Asynchronous assertion, synchronous release. One instance per clock domain.
module reset_sync(input wire clk, input wire arst_n, output wire rst_n);
    (* ASYNC_REG = "TRUE" *) reg [2:0] pipe;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) pipe <= 3'b000;
        else pipe <= {pipe[1:0], 1'b1};
    assign rst_n = pipe[2];
endmodule
