`timescale 1ns/1ps
`include "sim/voice_data/conditioner_count.vh"
// Exercise the actual board top, driving only microphone pins and decoding USB UART.
module tb_frontend_compat;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0;
    reg [2:0] key_n=3'b111;
    reg [3:0] keypad_col_n=4'hf;
    reg mic_sd=1'bz;
    wire mic_sck,mic_ws,link_tx,debug_tx;
    wire [3:0] keypad_row_n,led_n;
    reg [40:0] vectors[0:`CONDITIONER_COUNT-1];
    wire link_ack_rx=1;
    board2_voice_top #(.WARMUP_CYCLES(0)) dut(.*);
    integer slot=0,frame_no=0,byte_no=0,packets=0;
    reg [7:0] bytes[0:5];
    reg [7:0] received;
    reg [23:0] word24;

    function automatic [7:0] crc(input [23:0] payload);
        reg [7:0] c;
        begin
            c=0;
            for(integer n=23;n>=0;n=n-1)
                c=(c[7]^payload[n])?((c<<1)^8'h07):(c<<1);
            crc=c;
        end
    endfunction
    always @(posedge mic_sck)if(rst_n)begin
        if(mic_ws!==(slot>=32))$fatal(1,"microphone WS frame length");
        if(slot==63)begin slot=0;frame_no=frame_no+1;end
        else slot=slot+1;
    end
    always @(negedge mic_sck)if(rst_n)begin
        word24=vectors[frame_no%512][39:16];
        #20;
        if(slot>=1 && slot<=24)mic_sd=word24[24-slot];
        else mic_sd=1'bz;
    end
    initial begin
        $readmemh("sim/voice_data/conditioner.mem",vectors);
        repeat(8)@(negedge clk);rst_n=1;
        forever begin
            @(negedge debug_tx);#500;
            if(debug_tx!==0)$fatal(1,"UART false start");
            for(integer bitno=0;bitno<8;bitno=bitno+1)begin
                #1000;received[bitno]=debug_tx;
            end
            #1000;if(debug_tx!==1)$fatal(1,"UART bad stop bit");
            bytes[byte_no]=received;byte_no=byte_no+1;
            if(byte_no==6)begin
                byte_no=0;
                if(bytes[0]!==8'ha5 || bytes[1]!==8'h5a ||
                   bytes[5]!==crc({bytes[2],bytes[3],bytes[4]}))$fatal(1,"UART header/CRC");
                if({bytes[3],bytes[2]}!==vectors[packets][15:0] || bytes[4]!==8'(packets))
                    $fatal(1,"frontend packet%0d got%h seq%0d expected%h",packets,{bytes[3],bytes[2]},bytes[4],vectors[packets][15:0]);
                packets=packets+1;
                if(packets==512)begin
                    if(link_tx!==1)$fatal(1,"untrained voice emitted a command");
                    $display("PASS tb_frontend_compat actual board top, 512 physical I2S samples through raw24/DC-filter/gain2/PCM16/1Mbps UART, exact samples/CRC/sequence wrap");
                    $finish;
                end
            end
        end
    end
    initial begin #80000000;$fatal(1,"frontend timeout packets%0d",packets);end
endmodule
