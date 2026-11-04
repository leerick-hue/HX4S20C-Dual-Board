`timescale 1ns/1ps
module tb_link_ack;
 reg tclk=0,rclk=0;always #10 tclk=~tclk;always #5 rclk=~rclk;
 reg trst=0,rrst=0,event_valid=0,album_ready=1,forward_fault=0,ack_fault=0,drop_ack=0,stale_ack=0,hold_ack=0;
 reg[31:0]event_data=0;wire event_ready,tx,waiting,confirmed,failed;
 wire[15:0]retries,deliveries;
 wire ack_wire,ack_rx;
 reliable_event_link #(.RETRY_CYCLES(150000),.MAX_ATTEMPTS(3)) sender(.clk(tclk),.rst_n(trst),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),.link_tx(tx),.ack_rx(ack_rx),
  .waiting(waiting),.confirmed(confirmed),.failed(failed),.retry_count(retries),.delivery_count(deliveries));
 wire receiver_wire=tx ^ (forward_fault && sender.packets.active && sender.packets.index==6 && sender.tx.busy && sender.tx.bit_index==4);
 wire av,ae,np,cv,ack_valid,ack_ready,bv,br;wire[3:0]code;wire[31:0]accepted,duplicates,unsupported,errors,ack_data;
 wire[7:0]bytes,good,ack_sequence,byte_data;
 board_remote_control #(.ACK_ENABLE(1)) receiver(.clk(rclk),.rst_n(rrst),.link_rx(receiver_wire),.album_ready(album_ready),
  .control_ready(1'b1),.control_valid(cv),.control_code(code),.next_pulse(np),.auto_valid(av),.auto_enable(ae),
  .accepted_count(accepted),.duplicate_count(duplicates),.unsupported_count(unsupported),.packet_error_count(errors),
  .received_byte_count(bytes),.valid_packet_count(good),.ack_valid(ack_valid),.ack_ready(ack_ready),.ack_data(ack_data),.ack_sequence(ack_sequence));
 wire packet_ready;
 assign ack_ready=packet_ready && !hold_ack;
 event_packet_tx #(.USE_EVENT_SEQUENCE(1)) ack_packets(.clk(rclk),.rst_n(rrst),.event_valid(ack_valid && !hold_ack),.event_ready(packet_ready),
  .event_data(ack_data),.event_sequence(ack_sequence ^ (stale_ack?8'h80:8'd0)),.byte_valid(bv),.byte_ready(br),.byte_data(byte_data));
 uart_tx #(.CLK_HZ(100000000)) ack_transport(.clk(rclk),.rst_n(rrst),.byte_valid(bv),.byte_ready(br),.byte_data(byte_data),.tx(ack_wire),.busy());
 assign ack_rx=drop_ack?1'b1:(ack_wire ^ (ack_fault && ack_packets.active && ack_packets.index==6 && ack_transport.busy && ack_transport.bit_index==4));
 integer next_count=0,auto_count=0;reg auto_state=0;
 always @(posedge rclk)if(rrst)begin
  if(np)next_count=next_count+1;
  if(av)begin auto_count=auto_count+1;auto_state=ae;end
 end
 task send(input[15:0]id);
  begin @(negedge tclk);event_data={8'h02,8'h02,id};event_valid=1;
   do @(posedge tclk);while(!event_ready);
   @(negedge tclk);event_valid=0;
  end
 endtask
 task complete;begin wait(!waiting);repeat(30)@(negedge rclk);end endtask
 initial begin
  repeat(10)@(negedge tclk);trst=1;rrst=1;
  send(1);complete();
  if(!confirmed || failed || deliveries!=1 || retries!=0 || next_count!=1)$fatal(1,"initial round trip failed");
  forward_fault=1;send(1);wait(errors==1);forward_fault=0;complete();
  if(!confirmed || deliveries!=2 || retries!=1 || next_count!=2)$fatal(1,"lost command retry failed");
  ack_fault=1;send(1);wait(sender.ack_errors==1);ack_fault=0;complete();
  if(!confirmed || deliveries!=3 || retries!=2 || next_count!=3 || duplicates!=1)$fatal(1,"lost ACK repeated photo switch");
  album_ready=0;send(1);complete();
  if(!confirmed || deliveries!=4 || accepted!=3)$fatal(1,"ACK must mean queued receipt, not completed photo swap");
  album_ready=1;repeat(50)@(negedge rclk);if(accepted!=4 || next_count!=4)$fatal(1,"busy queued command lost");
  album_ready=0;send(2);complete();send(3);complete();
  if(deliveries!=6 || accepted!=6 || auto_count!=2 || !auto_state)$fatal(1,"pause/resume blocked by loading state");
  album_ready=1;drop_ack=1;send(1);complete();
  if(!failed || confirmed || retries!=4 || deliveries!=6 || next_count!=5 || accepted!=7 || duplicates!=3)
   $fatal(1,"missing ACK must fail after bounded retries without duplicate execution");
  drop_ack=0;send(1);complete();
  if(failed || !confirmed || deliveries!=7 || accepted!=8 || next_count!=6)$fatal(1,"ACK wire reconnection failed");
  stale_ack=1;send(2);wait(sender.ack_valid);@(negedge tclk);
  if(!waiting || deliveries!=7)$fatal(1,"wrong-sequence ACK accepted");
  stale_ack=0;complete();
  if(!confirmed || deliveries!=8 || retries!=5 || accepted!=9 || duplicates!=4 || auto_count!=3 || auto_state)
   $fatal(1,"stale ACK retry or dedup failed delivered%0d retry%0d ex%0d dup%0d",deliveries,retries,accepted,duplicates);
  // Ordered queue semantics: a busy NEXT keeps a later PAUSE pending, although
  // both packets have been acknowledged. Neither may be silently lost.
  album_ready=0;send(1);complete();send(2);complete();
  if(deliveries!=10 || accepted!=9)$fatal(1,"queued receipt confused with execution");
  album_ready=1;repeat(100)@(negedge rclk);
  if(accepted!=11 || next_count!=7 || auto_count!=4 || auto_state)$fatal(1,"ordered NEXT then PAUSE recovery failed");
  // Release the first ACK after a retransmission has already started.
  hold_ack=1;send(1);wait(sender.attempts==2);@(negedge rclk);hold_ack=0;complete();
  repeat(2000)@(negedge rclk);
  if(deliveries!=11 || retries!=6 || next_count!=8 || accepted!=12)$fatal(1,"late ACK/retry executed NEXT twice");
  $display("PASS reliable link: actual50/100MHz 115200, bad command/ACK retry, no duplicate NEXT, busy receipt vs execution, ordered NEXT/PAUSE recovery, disconnect/reconnect, wrong sequence rejection and late ACK after retry start");$finish;
 end
 initial begin #50000000;$fatal(1,"ACK test timeout state%0d ex%0d delivery%0d",sender.state,accepted,deliveries);end
endmodule
