`timescale 1ns/1ps
// Exact 1us clock enable: STEP ticks out of every TOP clk cycles, TOP/STEP reduced
// by gcd(CLK_HZ,1000000), so the average enable rate is exactly 1MHz (CLK_HZ>=1MHz).
module us_tick_1m #(
    parameter integer CLK_HZ=25000000
)(
    input wire clk,rst_n,
    output wire tick
);
    function integer cgcd;
        input integer a,b;
        integer x,y,t;
    begin
        x=a;y=b;
        while(y!=0)begin t=x%y;x=y;y=t;end
        cgcd=(x<0)?-x:x;
    end
    endfunction

    localparam integer GCD=cgcd(CLK_HZ,1000000);
    localparam integer TOP=CLK_HZ/GCD;
    localparam integer STEP=1000000/GCD;
    localparam integer PH_BITS=(TOP>1)?$clog2(TOP):1;
    localparam [PH_BITS-1:0] STEP_W=STEP;
    localparam [PH_BITS-1:0] REM_W=TOP-STEP;

    reg [PH_BITS-1:0] phase;
    wire [PH_BITS-1:0] phase_up=phase+STEP_W;
    wire [PH_BITS-1:0] phase_dn=phase-REM_W;
    assign tick=(phase>=REM_W);

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)phase<=0;
        else phase<=tick?phase_dn:phase_up;
    end
endmodule
