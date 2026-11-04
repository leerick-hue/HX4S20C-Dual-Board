module board_frame_request # (parameter integer GUARD_CYCLES=16)(
    input wire clk,input wire rst,input wire vblank_start,
    input wire read_req_ack,output reg read_req
);
    reg [1:0] ack_sync;
    reg [1:0] state;
    reg [7:0] guard_count;
    always @(posedge clk or posedge rst) begin
        if(rst) begin ack_sync<=0;state<=0;guard_count<=0;read_req<=0;end
        else begin
            ack_sync<={ack_sync[0],read_req_ack};
            case(state)
            0: if(vblank_start && !ack_sync[1]) begin guard_count<=GUARD_CYCLES-1;state<=1;end
            1: if(guard_count==0) begin read_req<=1;state<=2;end
               else guard_count<=guard_count-1'b1;
            2: if(ack_sync[1]) begin read_req<=0;state<=3;end
            3: if(!ack_sync[1]) state<=0;
            endcase
        end
    end
endmodule
