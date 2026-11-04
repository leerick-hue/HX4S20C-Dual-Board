`timescale 1ns/1ps
module uart_rx #(
    parameter integer CLK_HZ=50000000,BAUD=115200
)(
    input wire clk,rst_n,rx,output reg byte_valid,
    output reg [7:0] byte_data,output reg framing_error
);
    localparam integer BIT_CYCLES=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer CW=(BIT_CYCLES<2)?1:$clog2(BIT_CYCLES);
    localparam [1:0] IDLE=0,START=1,DATA=2,STOP=3;
    (* ASYNC_REG="TRUE" *) reg [1:0] sync_rx;
    reg [1:0] state;
    reg [CW-1:0] ticks;
    reg [2:0] index;
    reg [7:0] shift;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) sync_rx<=2'b11;
        else sync_rx<={sync_rx[0],rx};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=IDLE;ticks<=0;index<=0;shift<=0;byte_valid<=0;byte_data<=0;framing_error<=0;end
        else begin
            byte_valid<=0;framing_error<=0;
            case(state)
                IDLE: begin ticks<=0;if(!sync_rx[1]) state<=START;end
                START: if(ticks==BIT_CYCLES/2-1) begin
                    ticks<=0;
                    if(!sync_rx[1]) begin state<=DATA;index<=0;end
                    else state<=IDLE;
                end else ticks<=ticks+1'b1;
                DATA: if(ticks==BIT_CYCLES-1) begin
                    ticks<=0;shift[index]<=sync_rx[1];
                    if(index==7) state<=STOP;else index<=index+1'b1;
                end else ticks<=ticks+1'b1;
                STOP: if(ticks==BIT_CYCLES-1) begin
                    ticks<=0;state<=IDLE;
                    if(sync_rx[1]) begin byte_data<=shift;byte_valid<=1;end
                    else framing_error<=1;
                end else ticks<=ticks+1'b1;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
