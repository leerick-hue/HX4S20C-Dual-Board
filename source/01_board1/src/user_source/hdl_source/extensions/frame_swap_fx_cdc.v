`timescale 1ns/1ps
// Fade THROUGH BLACK, requiring one framebuffer read stream, not crossfade.
// Bank ownership changes only at a safe vblank. ACK is delayed through fade-in.
module frame_swap_fx_cdc(
    input wire sys_clk, input wire sys_rst_n,
    input wire request_valid, input wire request_bank,
    output wire request_ready, output reg request_done,
    input wire pixel_clk, input wire pixel_rst_n,
    input wire vblank_start, input wire pixel_safe_to_swap, input wire fade_enable,
    output reg display_bank, output reg display_valid, output reg switched,
    output reg [5:0] fade_gain, output wire transition_busy
);
    reg request_toggle,held_bank,ack_toggle,outstanding;
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,bank_sync;
    (* ASYNC_REG="TRUE" *) reg [2:0] request_sync;
    localparam [1:0] IDLE=0,FADE_OUT=1,BLACK=2,FADE_IN=3;
    reg [1:0] state;
    reg transaction_toggle;
    wire pending=request_sync[2]!=ack_toggle;
    assign request_ready=!outstanding;
    assign transition_busy=(state!=IDLE);
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            request_toggle<=0; held_bank<=1; ack_sync<=0; outstanding<=0; request_done<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle}; request_done<=0;
            if(request_valid && request_ready) begin
                held_bank<=request_bank; request_toggle<=!request_toggle; outstanding<=1;
            end
            if(outstanding && ack_sync[1]==request_toggle) begin
                outstanding<=0; request_done<=1;
            end
        end
    end
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            request_sync<=0; bank_sync<=3; ack_toggle<=0; state<=IDLE;
            display_bank<=0; display_valid<=0; switched<=0; fade_gain<=32;
            transaction_toggle<=0;
        end else begin
            request_sync<={request_sync[1:0],request_toggle};
            bank_sync<={bank_sync[0],held_bank}; switched<=0;
            if(vblank_start) case(state)
                IDLE: if(pending) begin
                    transaction_toggle<=request_sync[2];
                    if(display_valid && fade_enable) begin state<=FADE_OUT; fade_gain<=31; end
                    else if(pixel_safe_to_swap) begin
                        display_bank<=bank_sync[1]; display_valid<=1; switched<=1;
                        fade_gain<=32; ack_toggle<=request_sync[2];
                    end
                end
                FADE_OUT: begin
                    fade_gain<=fade_gain-1'b1;
                    if(fade_gain==1) state<=BLACK;
                end
                BLACK: if(pixel_safe_to_swap) begin
                    display_bank<=bank_sync[1]; display_valid<=1; switched<=1;
                    state<=FADE_IN;
                end
                FADE_IN: begin
                    fade_gain<=fade_gain+1'b1;
                    if(fade_gain==31) begin state<=IDLE; ack_toggle<=transaction_toggle; end
                end
            endcase
        end
    end
endmodule
