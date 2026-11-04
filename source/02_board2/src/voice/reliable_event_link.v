`timescale 1ns/1ps
// Stop-and-wait delivery. The peer echoes a CRC-valid packet only after it is
// stored in the receive queue. ACK proves receipt, not a completed photo swap.
module reliable_event_link #(
 parameter CLK_HZ=50000000,BAUD=115200,RETRY_CYCLES=10000000,MAX_ATTEMPTS=5
)(
 input clk,rst_n,input event_valid,output event_ready,input[31:0]event_data,
 output link_tx,input ack_rx,
 output waiting,output reg confirmed,failed,
 output reg[15:0]retry_count,delivery_count
);
 localparam IDLE=0,SEND=1,WAIT_ACK=2;
 localparam TIMER_BITS=$clog2(RETRY_CYCLES+1),ATTEMPT_BITS=$clog2(MAX_ATTEMPTS+1);
 reg[1:0]state;
 reg[31:0]held_data;reg[7:0]held_sequence,next_sequence;
 reg[TIMER_BITS-1:0]timer;reg[ATTEMPT_BITS-1:0]attempts;
 wire byte_valid,byte_ready,packet_ready,ack_byte_valid,framing_error,ack_valid;
 wire[7:0]byte_data,ack_byte,ack_sequence;wire[31:0]ack_data,ack_errors;
 wire ack_match=ack_valid && ack_sequence==held_sequence && ack_data==held_data;
 assign event_ready=state==IDLE;assign waiting=state!=IDLE;
 event_packet_tx #(.USE_EVENT_SEQUENCE(1)) packets(.clk(clk),.rst_n(rst_n),
  .event_valid(state==SEND && !ack_match),.event_ready(packet_ready),.event_data(held_data),.event_sequence(held_sequence),
  .byte_valid(byte_valid),.byte_ready(byte_ready),.byte_data(byte_data));
 uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) tx(.clk(clk),.rst_n(rst_n),
  .byte_valid(byte_valid),.byte_ready(byte_ready),.byte_data(byte_data),.tx(link_tx),.busy());
 uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx(.clk(clk),.rst_n(rst_n),.rx(ack_rx),
  .byte_valid(ack_byte_valid),.byte_data(ack_byte),.framing_error(framing_error));
 event_packet_rx #(.TIMEOUT_CYCLES(CLK_HZ/100)) decoder(.clk(clk),.rst_n(rst_n),
  .byte_valid(ack_byte_valid),.byte_data(ack_byte),.framing_error(framing_error),
  .event_valid(ack_valid),.event_ready(1'b1),.event_data(ack_data),.event_sequence(ack_sequence),.error_count(ack_errors));
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin
   state<=IDLE;held_data<=0;held_sequence<=0;next_sequence<=0;timer<=0;attempts<=0;
   confirmed<=0;failed<=0;retry_count<=0;delivery_count<=0;
  end else if(state!=IDLE && ack_match)begin
   state<=IDLE;confirmed<=1;failed<=0;delivery_count<=delivery_count+1'b1;
  end else case(state)
   IDLE:if(event_valid)begin
    held_data<=event_data;held_sequence<=next_sequence;next_sequence<=next_sequence+1'b1;
    attempts<=1;timer<=0;confirmed<=0;failed<=0;state<=SEND;
   end
   SEND:if(packet_ready)begin timer<=0;state<=WAIT_ACK;end
   WAIT_ACK:if(timer==RETRY_CYCLES-1)begin
    timer<=0;
    if(attempts==MAX_ATTEMPTS)begin failed<=1;state<=IDLE;end
    else begin attempts<=attempts+1'b1;retry_count<=retry_count+1'b1;state<=SEND;end
   end else timer<=timer+1'b1;
   default:state<=IDLE;
  endcase
endmodule
