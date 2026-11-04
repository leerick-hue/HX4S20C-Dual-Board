`timescale 1ns/1ps
// 8 data bits, no parity, one stop bit. Entirely in clk domain.
module uart_tx #(
    parameter integer CLK_HZ=50000000,
    parameter integer BAUD=115200
)(
    input wire clk,input wire rst_n,
    input wire byte_valid,output wire byte_ready,input wire [7:0] byte_data,
    output reg tx,output reg busy
);
    localparam integer BIT_CYCLES=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer CW=(BIT_CYCLES<2)?1:$clog2(BIT_CYCLES);
    reg [CW-1:0] ticks;
    reg [3:0] bit_index;
    reg [9:0] shift;
    assign byte_ready=!busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin tx<=1;busy<=0;ticks<=0;bit_index<=0;shift<=10'h3ff;end
        else if(!busy) begin
            tx<=1;
            if(byte_valid) begin
                shift<={1'b1,byte_data,1'b0};
                tx<=0;busy<=1;ticks<=0;bit_index<=0;
            end
        end else if(ticks==BIT_CYCLES-1) begin
            ticks<=0;
            if(bit_index==9) begin busy<=0;tx<=1;end
            else begin shift<={1'b1,shift[9:1]};tx<=shift[1];bit_index<=bit_index+1'b1;end
        end else ticks<=ticks+1'b1;
    end
endmodule
