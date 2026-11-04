`timescale 1ns/1ps
// 512 complete {word_address,RGB} transactions. One synchronous read port.
// Gray pointers cross clocks; RAM words stay owned until the consumer advances.
module pixel_write_fifo(
    input wire rst,input wire write_clk,input wire read_clk,
    input wire write_valid,output wire write_ready,input wire [52:0] write_data,
    input wire read_en,output wire [52:0] read_data,output wire [9:0] read_count
);
    wire wrst_n,rrst_n;
    reset_sync wrs(.clk(write_clk),.arst_n(!rst),.rst_n(wrst_n));
    reset_sync rrs(.clk(read_clk),.arst_n(!rst),.rst_n(rrst_n));
    reg [52:0] memory[0:511];
    reg [52:0] data_q;
    reg [9:0] wbin,wgray,rbin,rgray;
    reg [9:0] write_seen,count_base;
    reg last_pop;
    (* ASYNC_REG="TRUE" *) reg [9:0] rgray_meta,rgray_sync,wgray_meta,wgray_sync;
    wire full=wgray=={~rgray_sync[9:8],rgray_sync[7:0]};
    // Decode the synchronized write pointer before occupancy arithmetic. The
    // same registered pointer bounds pops, so the reported count never exceeds
    // owned data even while that pointer is one read clock older.
    wire empty=rbin==write_seen;
    wire push=write_valid && write_ready;
    wire pop=read_en && !empty && rrst_n;
    wire [9:0] wnext=wbin+push,rnext=rbin+pop;
    function [9:0] binary;
        input [9:0] gray;
        integer i;
        begin binary[9]=gray[9];for(i=8;i>=0;i=i-1)binary[i]=binary[i+1]^gray[i];end
    endfunction
    assign write_ready=wrst_n && !full;

    assign read_data=data_q;
    assign read_count=count_base-{9'd0,last_pop};
    always @(posedge write_clk) if(push) memory[wbin[8:0]]<=write_data;
    // Prefetch the next head on a pop, otherwise refresh the current head.
    // Pointer synchronization gives this read time to settle before count > 0.
    always @(posedge read_clk) data_q<=memory[rnext[8:0]];
    always @(posedge write_clk or negedge wrst_n) begin
        if(!wrst_n) begin wbin<=0;wgray<=0;rgray_meta<=0;rgray_sync<=0;end
        else begin
            rgray_meta<=rgray;rgray_sync<=rgray_meta;
            wbin<=wnext;wgray<=(wnext>>1)^wnext;
        end
    end
    always @(posedge read_clk or negedge rrst_n) begin
        if(!rrst_n) begin rbin<=0;rgray<=0;wgray_meta<=0;wgray_sync<=0;write_seen<=0;count_base<=0;last_pop<=0;end
        else begin
            wgray_meta<=wgray;wgray_sync<=wgray_meta;
            rbin<=rnext;rgray<=(rnext>>1)^rnext;
            write_seen<=binary(wgray_sync);
            count_base<=write_seen-rbin;last_pop<=pop;
        end
    end
endmodule
