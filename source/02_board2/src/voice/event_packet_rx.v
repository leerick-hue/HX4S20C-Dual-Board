`timescale 1ns/1ps
// Nine-byte rolling window. CRC covers version/source/kind/sequence/payload.
module event_packet_rx #(
    parameter integer TIMEOUT_CYCLES=500000
)(
    input wire clk,rst_n,input wire byte_valid,input wire [7:0] byte_data,
    input wire framing_error,output reg event_valid,input wire event_ready,
    output reg [31:0] event_data,output reg [7:0] event_sequence,
    output reg [31:0] error_count
);
    localparam integer TW=(TIMEOUT_CYCLES<2)?1:$clog2(TIMEOUT_CYCLES+1);
    reg [TW-1:0] idle_ticks;
    reg [7:0] window[0:7];
    reg [3:0] filled,partial;
    integer j;
    function [7:0] crc_byte;
        input [7:0] previous,value;
        reg [7:0] c;integer i;
        begin c=previous^value;
            for(i=0;i<8;i=i+1) c=c[7]?(c<<1)^8'h07:c<<1;
            crc_byte=c;
        end
    endfunction
    wire [7:0] crc=crc_byte(crc_byte(crc_byte(crc_byte(crc_byte(crc_byte(
        8'd0,window[2]),window[3]),window[4]),window[5]),window[6]),window[7]);
    wire header=filled==8 && window[0]==8'ha5 && window[1]==8'h5a;
    wire format_ok=window[2]==1 && (window[3]==1 || window[3]==2) &&
        (window[4]==1 || window[4]==2);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            idle_ticks<=0;filled<=0;partial<=0;event_valid<=0;
            event_data<=0;event_sequence<=0;error_count<=0;
        end else begin
            if(event_valid && event_ready) event_valid<=0;
            if(framing_error) begin
                idle_ticks<=0;filled<=0;partial<=0;error_count<=error_count+1'b1;
            end else if(byte_valid) begin
                idle_ticks<=0;
                for(j=0;j<7;j=j+1) window[j]<=window[j+1];
                window[7]<=byte_data;
                if(filled<8) filled<=filled+1'b1;
                if(filled!=0 && window[7]==8'ha5 && byte_data==8'h5a) partial<=2;
                else if(partial!=0) partial<=(partial==8)?4'd0:partial+1'b1;
                if(header) begin
                    if(format_ok && crc==byte_data) begin
                        // A validated frame gives an unambiguous boundary.
                        // Discard its history so header bytes inside its payload
                        // cannot become a spurious candidate in the next frame.
                        partial<=0;filled<=0;
                        if(!event_valid || event_ready) begin
                            event_valid<=1;event_data<={window[3],window[4],window[7],window[6]};
                            event_sequence<=window[5];
                        end else error_count<=error_count+1'b1;
                    end else error_count<=error_count+1'b1;
                end
            end else if(TIMEOUT_CYCLES>0 && filled!=0) begin
                if(idle_ticks==TIMEOUT_CYCLES-1) begin
                    idle_ticks<=0;filled<=0;partial<=0;
                    if(partial!=0) error_count<=error_count+1'b1;
                end else idle_ticks<=idle_ticks+1'b1;
            end
        end
    end
endmodule
