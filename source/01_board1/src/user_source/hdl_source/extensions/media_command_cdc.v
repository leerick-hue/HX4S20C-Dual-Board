`timescale 1ns/1ps
// One outstanding command. The source holds payload until destination consume
// is acknowledged. Only the second request synchronizer can enable payload
// capture; its first stage has no fanout to consumer or capture logic.
// Both resets assert together, and may release independently. An in-flight
// command is discarded by reset, as in the original mailbox.
module media_command_cdc(
    input src_clk,src_rst_n,src_valid,output src_ready,input [7:0] src_code,
    input dst_clk,dst_rst_n,output dst_valid,input dst_ready,output [7:0] dst_code
);
    reg request,ack;
    reg [7:0] payload,dst_payload;
    reg dst_pending;
    (* ASYNC_REG="TRUE" *) reg ack_meta,ack_sync,req_meta,req_sync;
    assign src_ready=request==ack_sync;
    assign dst_valid=dst_pending;
    assign dst_code=dst_payload;
    always @(posedge src_clk or negedge src_rst_n)begin
        if(!src_rst_n)begin request<=0;payload<=0;ack_meta<=0;ack_sync<=0;end
        else begin
            ack_meta<=ack;ack_sync<=ack_meta;
            if(src_valid && src_ready)begin payload<=src_code;request<=!request;end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n)begin
        if(!dst_rst_n)begin req_meta<=0;req_sync<=0;ack<=0;dst_pending<=0;dst_payload<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;
            if(dst_pending)begin
                if(dst_ready)begin ack<=req_sync;dst_pending<=0;end
            end else if(req_sync!=ack)begin
                dst_payload<=payload;dst_pending<=1;
            end
        end
    end
endmodule
