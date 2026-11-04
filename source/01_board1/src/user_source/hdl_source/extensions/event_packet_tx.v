`timescale 1ns/1ps
// Event word: source[31:24], kind[23:16], payload[15:0].
// Packet: A5 5A 01 source kind sequence payload_lo payload_hi CRC8.
module event_packet_tx #(parameter USE_EVENT_SEQUENCE=0)(
    input wire clk,input wire rst_n,
    input wire event_valid,output wire event_ready,input wire [31:0] event_data,
    input wire [7:0] event_sequence,
    output wire byte_valid,input wire byte_ready,output reg [7:0] byte_data
);
    reg active;
    reg [3:0] index;
    reg [31:0] held_event;
    reg [7:0] next_sequence,held_sequence,crc;
    function [7:0] crc_byte;
        input [7:0] previous,value;
        reg [7:0] result;
        integer i;
        begin
            result=previous^value;
            for(i=0;i<8;i=i+1)
                result=result[7] ? (result<<1)^8'h07 : result<<1;
            crc_byte=result;
        end
    endfunction
    assign event_ready=!active;
    assign byte_valid=active;
    always @* begin
        case(index)
            0:byte_data=8'ha5;
            1:byte_data=8'h5a;
            2:byte_data=8'h01;
            3:byte_data=held_event[31:24];
            4:byte_data=held_event[23:16];
            5:byte_data=held_sequence;
            6:byte_data=held_event[7:0];
            7:byte_data=held_event[15:8];
            default:byte_data=crc;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin active<=0;index<=0;held_event<=0;next_sequence<=0;held_sequence<=0;crc<=0;end
        else if(!active) begin
            if(event_valid) begin
                active<=1;index<=0;held_event<=event_data;
                held_sequence<=USE_EVENT_SEQUENCE?event_sequence:next_sequence;
                next_sequence<=next_sequence+1'b1;crc<=0;
            end
        end else if(byte_ready) begin
            if(index>=2 && index<=7) crc<=crc_byte(crc,byte_data);
            if(index==8) active<=0;
            else index<=index+1'b1;
        end
    end
endmodule
