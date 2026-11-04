`timescale 1ns/1ps
// CRC-checked, queued UART commands. This v1 link has no execution ACK/retry.
module board_remote_control #(
    parameter integer CLK_HZ=100000000,BAUD=115200,ACK_ENABLE=0
)(
    input wire clk,rst_n,link_rx,input wire album_ready,
    input wire control_ready,output wire control_valid,output wire [3:0] control_code,
    output reg next_pulse,auto_valid,auto_enable,
    output reg [31:0] accepted_count,duplicate_count,unsupported_count,
    output wire [31:0] packet_error_count,
    output wire [7:0] received_byte_count,valid_packet_count,
    output reg ack_valid,input wire ack_ready,output reg[31:0]ack_data,output reg[7:0]ack_sequence
);
    wire byte_valid,framing_error,event_valid,event_ready;
    wire [7:0] byte_data,event_sequence;
    wire [31:0] event_data;
    uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) remote_uart(.clk(clk),.rst_n(rst_n),.rx(link_rx),
        .byte_valid(byte_valid),.byte_data(byte_data),.framing_error(framing_error));
    event_packet_rx #(.TIMEOUT_CYCLES(CLK_HZ/100)) decoder(.clk(clk),.rst_n(rst_n),
        .byte_valid(byte_valid),.byte_data(byte_data),.framing_error(framing_error),
        .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),
        .event_sequence(event_sequence),.error_count(packet_error_count),
        .received_byte_count(received_byte_count),.valid_packet_count(valid_packet_count));
    reg queued_valid;
    reg [39:0] queued;
    wire queued_ready,fifo_valid;
    wire queue_in_ready;
    wire ack_room=!ACK_ENABLE || !ack_valid || ack_ready;
    assign event_ready=queue_in_ready && ack_room;
    wire [39:0] fifo_data;
    // Registered command stage breaks RAM -> compare/decode -> FIFO count
    // feedback. A two-cycle command throughput is ample at 115200 baud.
    wire fifo_pop=!queued_valid;
    wire [4:0] level;
    event_fifo #(.WIDTH(40)) queue(.clk(clk),.rst_n(rst_n),
        .in_valid(event_valid && ack_room),.in_ready(queue_in_ready),.in_data({event_sequence,event_data}),
        .out_valid(fifo_valid),.out_ready(fifo_pop),.out_data(fifo_data),.level(level));
    wire keyboard=(fifo_data[31:24]==8'h01 && fifo_data[23:16]==8'h01);
    wire command=(fifo_data[23:16]==8'h02);
    wire decoded_known=(keyboard && fifo_data[15:0]<16) ||
               (command && fifo_data[15:0]>=1 && fifo_data[15:0]<=16);
    wire [3:0] decoded_code=keyboard ? fifo_data[3:0] : fifo_data[3:0]-4'd1;
    reg known,duplicate;
    reg [3:0] code;
    assign control_code=code;
    wire is_next=known && control_code==0;
    wire is_pause=known && control_code==1;
    wire is_resume=known && control_code==2;
    wire album_command=is_next || is_pause || is_resume;
    reg last_valid;
    reg [39:0] last_packet;
    reg [31:0] idle_count;
    // Register decode and duplicate comparison separately from execution.
    // This avoids RAM -> wide compare -> command gate -> output feedback.

    // The next pulse is registered: reserve one cycle for the album controller
    // to latch its pending request, otherwise back-to-back NEXTs could coalesce.
    wire can_execute=!is_next || (album_ready && !next_pulse);
    assign control_valid=queued_valid && !duplicate && known && can_execute;
    assign queued_ready=duplicate || !known || (can_execute && control_ready);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            next_pulse<=0;auto_valid<=0;auto_enable<=0;
            accepted_count<=0;duplicate_count<=0;unsupported_count<=0;
            last_valid<=0;last_packet<=0;idle_count<=0;
            queued_valid<=0;queued<=0;known<=0;duplicate<=0;code<=0;
            ack_valid<=0;ack_data<=0;ack_sequence<=0;
        end else begin
            next_pulse<=0;auto_valid<=0;
            if(ack_valid && ack_ready)ack_valid<=0;
            // Echo only after the complete CRC-valid event enters the queue.
            // This ACK confirms delivery; queued photo commands may still wait.
            if(ACK_ENABLE && event_valid && event_ready)begin
                ack_valid<=1;ack_data<=event_data;ack_sequence<=event_sequence;
            end
            if(!queued_valid && fifo_valid) begin
                queued<=fifo_data;queued_valid<=1;
                known<=decoded_known;code<=decoded_code;
                duplicate<=last_valid && fifo_data==last_packet;
            end
            // Expire only consecutive-packet duplicate history, allowing a
            // restarted sender (sequence resets to zero) after three seconds.
            if(idle_count<CLK_HZ*3) idle_count<=idle_count+1'b1;
            else last_valid<=0;
            if(queued_valid && queued_ready) begin
                queued_valid<=0;
                idle_count<=0;
                if(duplicate) duplicate_count<=duplicate_count+1'b1;
                else if(known) begin
                    last_valid<=1;last_packet<=queued;accepted_count<=accepted_count+1'b1;
                    if(is_next) next_pulse<=1;
                    else if(is_pause || is_resume) begin auto_valid<=1;auto_enable<=is_resume;end
                end else unsupported_count<=unsupported_count+1'b1;
            end
        end
    end
endmodule
