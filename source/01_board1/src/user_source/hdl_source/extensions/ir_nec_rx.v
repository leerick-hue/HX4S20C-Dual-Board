`timescale 1ns/1ps
// Demodulated active-low NEC input. One system clock, with a 1us enable.
// A valid repeat extends the250ms hold chain; an orphan repeat never starts it.
module ir_nec_rx #(
    parameter integer CLK_HZ=25000000,
    parameter integer FILTER_US=50
)(
    input wire clk,rst_n,ir_in,
    output reg [15:0] address,
    output reg [7:0] command,
    output reg frame_valid,repeat_frame,
    output reg [31:0] error_count
);
    localparam IDLE=0,LEADER_MARK=1,LEADER_SPACE=2,BIT_MARK=3,
               BIT_SPACE=4,TAIL_MARK=5,REPEAT_MARK=6;
    (* ASYNC_REG="TRUE" *) reg ir_meta,ir_sync;
    wire us_tick;
    us_tick_1m #(.CLK_HZ(CLK_HZ)) u_us(.clk(clk),.rst_n(rst_n),.tick(us_tick));
    reg filtered;
    reg [7:0] filter_count;
    wire edge_now=(ir_sync!=filtered && filter_count==FILTER_US-1);
    wire falling=edge_now && !ir_sync;
    wire rising=edge_now && ir_sync;
    reg [2:0] state;
    reg [14:0] duration;
    wire [15:0] elapsed={1'b0,duration}+16'd1;
    reg [5:0] bit_index;
    reg [31:0] bits;
    reg have_frame;
    reg [17:0] hold_age;
    function in_window;
        input [15:0] value;input integer low,high;
        begin in_window=(value>=low && value<=high);end
    endfunction
    reg us_tick_d,falling_d,rising_d,timeout_d;
    reg leader_mark_ok,leader_space_ok,repeat_space_ok,bit_mark_ok,bit_one_ok;
    reg command_check,address_check;
    // Separate the microsecond filter/width comparisons from the state and
    // variable-bit write decoder. Public decoded pulses move one clock later.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            filtered<=1;filter_count<=0;duration<=0;us_tick_d<=0;
            falling_d<=0;rising_d<=0;timeout_d<=0;
            leader_mark_ok<=0;leader_space_ok<=0;repeat_space_ok<=0;
            bit_mark_ok<=0;bit_one_ok<=0;command_check<=0;address_check<=0;
        end else begin
            us_tick_d<=us_tick;
            if(us_tick)begin
                if(ir_sync==filtered)filter_count<=0;
                else if(edge_now)begin filtered<=ir_sync;filter_count<=0;end
                else filter_count<=filter_count+1'b1;
                if(edge_now)duration<=0;
                else if(duration<20001)duration<=duration+1'b1;
                falling_d<=falling;rising_d<=rising;timeout_d<=duration>=20000;
                leader_mark_ok<=in_window(elapsed,7200,10800);
                leader_space_ok<=in_window(elapsed,3600,5400);
                repeat_space_ok<=in_window(elapsed,1800,2700);
                bit_mark_ok<=in_window(elapsed,448,672);
                bit_one_ok<=in_window(elapsed,1352,2028);
                command_check<=bits[31:24]==~bits[23:16];
                address_check<=bits[15:8]==~bits[7:0];
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin ir_meta<=1;ir_sync<=1;end
        else begin
            ir_meta<=ir_in;ir_sync<=ir_meta;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            address<=0;command<=0;frame_valid<=0;repeat_frame<=0;error_count<=0;
            state<=IDLE;
            bit_index<=0;bits<=0;have_frame<=0;hold_age<=250000;
        end else begin
            frame_valid<=0;repeat_frame<=0;
            if(us_tick_d)begin
                if(hold_age<250000)hold_age<=hold_age+1'b1;
                else have_frame<=0;
                if(state!=IDLE && timeout_d)begin
                    state<=IDLE;error_count<=error_count+1'b1;
                end else case(state)
                    IDLE:if(falling_d)begin state<=LEADER_MARK;bits<=0;bit_index<=0;end
                    LEADER_MARK:if(rising_d)begin
                        if(leader_mark_ok)state<=LEADER_SPACE;
                        else begin state<=IDLE;error_count<=error_count+1'b1;end
                    end
                    LEADER_SPACE:if(falling_d)begin
                        if(leader_space_ok)begin state<=BIT_MARK;bit_index<=0;bits<=0;end
                        else if(repeat_space_ok)state<=REPEAT_MARK;
                        else begin state<=IDLE;error_count<=error_count+1'b1;end
                    end
                    BIT_MARK:if(rising_d)begin
                        if(bit_mark_ok)state<=BIT_SPACE;
                        else begin state<=IDLE;error_count<=error_count+1'b1;end
                    end
                    BIT_SPACE:if(falling_d)begin
                        if(bit_mark_ok || bit_one_ok)begin
                            bits[bit_index]<=bit_one_ok;
                            if(bit_index==31)state<=TAIL_MARK;
                            else begin bit_index<=bit_index+1'b1;state<=BIT_MARK;end
                        end else begin state<=IDLE;error_count<=error_count+1'b1;end
                    end
                    TAIL_MARK:if(rising_d)begin
                        state<=IDLE;
                        if(bit_mark_ok && command_check)begin
                            address<=(address_check)?{8'd0,bits[7:0]}:bits[15:0];
                            command<=bits[23:16];frame_valid<=1;have_frame<=1;hold_age<=0;
                        end else error_count<=error_count+1'b1;
                    end
                    REPEAT_MARK:if(rising_d)begin
                        state<=IDLE;
                        if(bit_mark_ok && have_frame && hold_age<250000)begin
                            repeat_frame<=1;hold_age<=0;
                        end else error_count<=error_count+1'b1;
                    end
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
