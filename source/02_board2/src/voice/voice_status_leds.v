`timescale 1ns/1ps
// Board LEDs are active high. Before enrollment: lit means template missing.
// After all three templates exist: flash the class of a dispatched voice command.
module voice_status_leds #(parameter integer SHOW_CYCLES=50000000)(
    input wire clk,rst_n,
    input wire [2:0] template_mask,
    input wire command_valid,command_ready,
    input wire [15:0] command_id,
    output wire [2:0] leds
);
    localparam integer CW=$clog2(SHOW_CYCLES+1);
    reg [CW-1:0] remaining;
    reg [2:0] selected;
    assign leds=template_mask!=3'b111 ? ~template_mask :
                remaining!=0 ? selected : 3'b000;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin remaining<=0;selected<=0;end
        else if(template_mask!=3'b111)begin remaining<=0;selected<=0;end
        else if(command_valid && command_ready)begin
            remaining<=SHOW_CYCLES;
            case(command_id)
                1:selected<=3'b001;
                2:selected<=3'b010;
                3:selected<=3'b100;
                default:begin selected<=0;remaining<=0;end
            endcase
        end else if(remaining!=0)remaining<=remaining-1'b1;
    end
endmodule
