`timescale 1ns/1ps
// Defaults are the common21-key NEC remote, not measured hardware keycodes.
// last_raw_code is a decoded tuple {address,8'h00,command}, not the NEC wire word.
module ir_keymap #(
    parameter integer CLK_HZ=25000000,
    parameter [15:0] ADDR=16'h0000,MASK=16'hffff,
    parameter [7:0] KEY_AUTO=8'h45,KEY_MUSIC=8'h46,KEY_MUTE=8'h47,
    parameter [7:0] KEY_VOL_UP=8'h44,KEY_VOL_DOWN=8'h40,KEY_NEXT=8'h43,
    parameter [7:0] KEY_BRIGHT_UP=8'h07,KEY_BRIGHT_DOWN=8'h15,KEY_BARS=8'h09,
    parameter [7:0] KEY_AUTO_OFF=8'h16,KEY_AUTO_ON=8'h19,KEY_NEUTRAL=8'h0d,
    parameter [7:0] KEY_CONTRAST_DOWN=8'h0c,KEY_CONTRAST_UP=8'h18,
    parameter integer PHONE_ENABLE=1,
    parameter [15:0] PHONE_ADDR=16'hbf00
)(
    input wire clk,rst_n,frame_valid,repeat_frame,
    input wire [15:0] address,input wire [7:0] command,
    output reg cmd_valid,input wire cmd_ready,output reg [7:0] cmd_id,
    output reg [31:0] last_raw_code,dropped_count
);
    wire us_tick;
    us_tick_1m #(.CLK_HZ(CLK_HZ)) u_us(.clk(clk),.rst_n(rst_n),.tick(us_tick));
    reg held_valid;
    reg [15:0] held_address;
    reg [7:0] held_command;
    reg [17:0] hold_age;
    reg [16:0] repeat_age;
    reg repeat_ready;
    function [7:0] decode;
        input [7:0] key;
        begin case(key)
            KEY_AUTO:decode=20;KEY_MUSIC:decode=19;KEY_MUTE:decode=5;
            KEY_VOL_UP:decode=4;KEY_VOL_DOWN:decode=6;KEY_NEXT:decode=1;
            KEY_BRIGHT_UP:decode=7;KEY_BRIGHT_DOWN:decode=9;KEY_BARS:decode=12;
            KEY_AUTO_OFF:decode=2;KEY_AUTO_ON:decode=3;KEY_NEUTRAL:decode=8;
            KEY_CONTRAST_DOWN:decode=10;KEY_CONTRAST_UP:decode=11;
            default:decode=0;
        endcase end
    endfunction
    // Phone remote codes are a separate key space: unknown codes return 0 and
    // must never fall through to decode(), or stray keys would alias onto the
    // common21 mapping.
    function [7:0] decode_phone;
        input [7:0] key;
        begin case(key)
            8'h44:decode_phone=4;8'h43:decode_phone=6;8'h0d:decode_phone=5;
            8'h4a:decode_phone=1;8'h4b:decode_phone=20;
            default:decode_phone=0;
        endcase end
    endfunction
    wire phone_match=PHONE_ENABLE && (address==PHONE_ADDR);
    wire [7:0] mapped_id=phone_match?decode_phone(command):decode(command);
    wire mine=phone_match || ((address&MASK)==(ADDR&MASK));
    // held_valid expires on the same tick that age reaches250000. Keeping the
    // age predicates as state removes wide counter compares from the key mux.
    wire same_press=held_valid && address==held_address && command==held_command;
    wire adjustable=(mapped_id==4 || mapped_id==6 || mapped_id==7 ||
                     mapped_id==9 || mapped_id==10 || mapped_id==11);
    wire fresh_press=frame_valid && !same_press;
    wire actionable=fresh_press || (same_press && adjustable && repeat_ready);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            held_valid<=0;held_address<=0;held_command<=0;
            hold_age<=250000;repeat_age<=120000;repeat_ready<=1;
            cmd_valid<=0;cmd_id<=0;last_raw_code<=0;dropped_count<=0;
        end else begin
            if(us_tick)begin
                if(hold_age<250000)hold_age<=hold_age+1'b1;
                if(hold_age==249999)held_valid<=0;
                if(!repeat_ready)repeat_age<=repeat_age+1'b1;
                if(repeat_age==119999)repeat_ready<=1;
            end
            if(cmd_valid && cmd_ready)cmd_valid<=0;
            if(frame_valid || repeat_frame)begin
                last_raw_code<={address,8'h00,command};
                if(mine)begin
                    if(mapped_id==0)begin
                        if(frame_valid)held_valid<=0;
                    end else if(frame_valid || same_press)begin
                        held_valid<=1;held_address<=address;held_command<=command;hold_age<=0;
                        if(actionable)begin
                            repeat_age<=0;repeat_ready<=0;
                            if(!cmd_valid || cmd_ready)begin cmd_valid<=1;cmd_id<=mapped_id;end
                            else dropped_count<=dropped_count+1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
