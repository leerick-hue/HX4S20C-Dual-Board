`timescale 1ns/1ps
// Actual board buttons: B2 increment/next, C1 decrement/auto, B1 mode.
// Mode 0 album, 1 brightness, 2 contrast, 3 volume, 4 bar visibility, 5 TF music play/pause.
// Parameters and bar visibility commit at vblank.
module board_video_controls #(
    parameter integer KEY_CYCLES=504000
)(
    input wire clk,input wire rst_n,input wire vblank_start,
    input wire [2:0] key_n,
    input wire command_valid,input wire[7:0]command_id,output command_ready,
    output reg [3:0] brightness,output reg [3:0] contrast,
    output reg [2:0] edit_mode,output reg [3:0] volume_level,
    output reg bars_enable,output reg music_play
);
    wire [2:0] pressed,down;
    reg [3:0] bright_pending,contrast_pending,volume_pending;
    reg bars_pending;reg[3:0]last_volume;
    assign command_ready=!(|pressed);
    genvar i;
    generate for(i=0;i<3;i=i+1) begin: keys
        key_debounce #(.STABLE_CYCLES(KEY_CYCLES)) d(
            .clk(clk),.rst_n(rst_n),.key_n(key_n[i]),.pressed(pressed[i]),.down(down[i]));
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            brightness<=4;contrast<=4;volume_level<=8;
            bright_pending<=4;contrast_pending<=4;volume_pending<=8;edit_mode<=0;
            bars_pending<=1;bars_enable<=1;music_play<=1;last_volume<=8;
        end
        else begin
            if(volume_pending!=0)last_volume<=volume_pending;
            if(command_valid && command_ready)begin
             case(command_id)
              4:begin edit_mode<=3;if(volume_pending<8)volume_pending<=volume_pending+1'b1;end
              5:begin edit_mode<=3;volume_pending<=volume_pending==0?last_volume:4'd0;end
              6:begin edit_mode<=3;if(volume_pending>0)volume_pending<=volume_pending-1'b1;end
              7:begin edit_mode<=1;if(bright_pending<8)bright_pending<=bright_pending+1'b1;end
              8:begin bright_pending<=4;contrast_pending<=4;end
              9:begin edit_mode<=1;if(bright_pending>0)bright_pending<=bright_pending-1'b1;end
              10:begin edit_mode<=2;if(contrast_pending>0)contrast_pending<=contrast_pending-1'b1;end
              11:begin edit_mode<=2;if(contrast_pending<8)contrast_pending<=contrast_pending+1'b1;end
              12:begin edit_mode<=4;bars_pending<=!bars_pending;end
              13:edit_mode<=0;14:edit_mode<=1;15:edit_mode<=2;16:edit_mode<=3;
              17:begin edit_mode<=5;music_play<=0;end
              18:begin edit_mode<=5;music_play<=1;end
              19:begin edit_mode<=5;music_play<=!music_play;end
             endcase
            end else if(pressed[2]) edit_mode<=(edit_mode==5)?3'd0:edit_mode+3'd1;
            else if(edit_mode==1) begin
                if(pressed[0] && bright_pending<8) bright_pending<=bright_pending+1'b1;
                else if(pressed[1] && bright_pending>0) bright_pending<=bright_pending-1'b1;
            end else if(edit_mode==2) begin
                if(pressed[0] && contrast_pending<8) contrast_pending<=contrast_pending+1'b1;
                else if(pressed[1] && contrast_pending>0) contrast_pending<=contrast_pending-1'b1;
            end else if(edit_mode==3) begin
                if(pressed[0] && volume_pending<8) volume_pending<=volume_pending+1'b1;
                else if(pressed[1] && volume_pending>0) volume_pending<=volume_pending-1'b1;
            end else if(edit_mode==4) begin
                if(pressed[0]) bars_pending<=1;
                else if(pressed[1]) bars_pending<=0;
            end
            if(edit_mode==5 && !pressed[2]) begin
                if(pressed[0]) music_play<=1;
                else if(pressed[1]) music_play<=0;
            end
            if(vblank_start) begin
                brightness<=bright_pending;contrast<=contrast_pending;volume_level<=volume_pending;
                bars_enable<=bars_pending;
            end
        end
    end
endmodule
