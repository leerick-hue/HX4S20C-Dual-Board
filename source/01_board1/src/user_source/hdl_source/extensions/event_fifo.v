`timescale 1ns/1ps
module event_fifo #(
    parameter integer WIDTH=32,
    parameter integer DEPTH=16,
    parameter integer PTR_BITS=4,
    parameter integer COUNT_BITS=5
)(
    input wire clk, input wire rst_n,
    input wire in_valid, output wire in_ready, input wire [WIDTH-1:0] in_data,
    output wire out_valid, input wire out_ready, output wire [WIDTH-1:0] out_data,
    output reg [COUNT_BITS-1:0] level
);
    reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_BITS-1:0] write_ptr,read_ptr;
    wire pop=out_valid && out_ready;
    wire push=in_valid && in_ready;
    assign out_valid=(level!=0);
    assign out_data=memory[read_ptr];
    assign in_ready=(level<DEPTH) || pop;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin write_ptr<=0;read_ptr<=0;level<=0;end
        else begin
            if(push) begin
                memory[write_ptr]<=in_data;
                write_ptr<=(write_ptr==DEPTH-1) ? 0 : write_ptr+1'b1;
            end
            if(pop) read_ptr<=(read_ptr==DEPTH-1) ? 0 : read_ptr+1'b1;
            case({push,pop})
                2'b10: level<=level+1'b1;
                2'b01: level<=level-1'b1;
                default: ;
            endcase
        end
    end
endmodule
