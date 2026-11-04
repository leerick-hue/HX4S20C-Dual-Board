`timescale 1ns/1ps
// Registered round-robin arbitration. Sources hold valid/data until ready.
module event_arbiter(
    input wire clk, input wire rst_n,
    input wire key_valid, output wire key_ready, input wire [31:0] key_data,
    input wire voice_valid, output wire voice_ready, input wire [31:0] voice_data,
    output reg out_valid, input wire out_ready, output reg [31:0] out_data
);
    reg prefer_voice;
    wire room = !out_valid || out_ready;
    wire select_voice = voice_valid && (!key_valid || prefer_voice);
    assign key_ready = room && !select_voice;
    assign voice_ready = room && select_voice;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            out_valid <= 0; out_data <= 0; prefer_voice <= 0;
        end else if(room) begin
            out_valid <= key_valid || voice_valid;
            if(select_voice) begin
                out_data <= voice_data; prefer_voice <= 0;
            end else if(key_valid) begin
                out_data <= key_data; prefer_voice <= 1;
            end
        end
    end
endmodule
