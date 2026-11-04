`timescale 1ns/1ps
// Two frame slots: one serializing and one pending. No active sample overwrite.
// At50MHz/1Mbps each UART byte takes501 clocks including the handoff cycle;
// 6*501=3006 clocks per frame, below the3125-clock16kHz sample period.
module pcm_uart_stream #(
    parameter integer CLK_HZ=50000000,BAUD=1000000
)(
    input wire clk,rst_n,pcm_valid,input wire signed [15:0] pcm_sample,
    output wire tx,output reg [31:0] drop_count
);
    reg [7:0] sample_sequence;
    reg active_valid,pending_valid;
    reg [31:0] active,pending;
    reg [2:0] byte_index;
    wire byte_ready;
    reg [7:0] byte_data;
    function [7:0] crc_byte;
        input [7:0] previous,value;
        reg [7:0] c;integer k;
        begin
            c=previous^value;
            for(k=0;k<8;k=k+1)c=c[7]?((c<<1)^8'h07):(c<<1);
            crc_byte=c;
        end
    endfunction
    wire [7:0] sample_crc=crc_byte(crc_byte(crc_byte(0,pcm_sample[7:0]),pcm_sample[15:8]),sample_sequence);
    wire [31:0] incoming={sample_crc,sample_sequence,pcm_sample};
    wire frame_sent=active_valid && byte_ready && byte_index==5;
    always @*begin
        case(byte_index)
            0:byte_data=8'ha5;1:byte_data=8'h5a;
            2:byte_data=active[7:0];3:byte_data=active[15:8];
            4:byte_data=active[23:16];default:byte_data=active[31:24];
        endcase
    end
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) serial(.clk(clk),.rst_n(rst_n),
        .byte_valid(active_valid),.byte_ready(byte_ready),.byte_data(byte_data),.tx(tx),.busy());
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            sample_sequence<=0;active_valid<=0;pending_valid<=0;active<=0;pending<=0;
            byte_index<=0;drop_count<=0;
        end else begin
            if(pcm_valid)sample_sequence<=sample_sequence+1'b1;
            if(!active_valid || frame_sent)begin
                byte_index<=0;
                if(pending_valid)begin
                    active<=pending;active_valid<=1;
                    if(pcm_valid)begin pending<=incoming;pending_valid<=1;end
                    else pending_valid<=0;
                end else if(pcm_valid)begin active<=incoming;active_valid<=1;end
                else active_valid<=0;
            end else begin
                if(byte_ready)byte_index<=byte_index+1'b1;
                if(pcm_valid)begin
                    if(!pending_valid)begin pending<=incoming;pending_valid<=1;end
                    else drop_count<=drop_count+1'b1;
                end
            end
        end
    end
endmodule
