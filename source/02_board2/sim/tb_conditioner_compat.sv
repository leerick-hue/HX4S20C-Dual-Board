`timescale 1ns/1ps
`include "sim/voice_data/conditioner_count.vh"
module tb_conditioner_compat;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,sample_valid=0;
    reg signed [23:0] sample24=0;
    wire pcm_valid;
    wire signed [15:0] pcm_sample;
    reg [40:0] vectors[0:`CONDITIONER_COUNT-1];
    wire signed[15:0]reference_pcm;wire[2:0]agc_gain;wire[31:0]clip_count;wire speech_active=0;
    mic_pcm_conditioner dut(.*);
    initial begin
        $readmemh("sim/voice_data/conditioner.mem",vectors);
        repeat(4)@(negedge clk);rst_n=1;
        for(integer n=0;n<`CONDITIONER_COUNT;n=n+1)begin
            if(vectors[n][40])begin
                rst_n=0;repeat(2)@(negedge clk);
                if(pcm_valid || pcm_sample!==0)$fatal(1,"conditioner reset failed");
                rst_n=1;
            end
            sample24=vectors[n][39:16];sample_valid=1;
            @(posedge clk);#1;
            if(!pcm_valid || pcm_sample!==vectors[n][15:0])
                $fatal(1,"conditioner sample%0d got%0d expected%0d",n,pcm_sample,$signed(vectors[n][15:0]));
            @(negedge clk);sample_valid=0;
            repeat(1+n%4)begin
                @(posedge clk);#1;if(pcm_valid)$fatal(1,"conditioner leaked valid");
                @(negedge clk);
            end
        end
        $display("PASS tb_conditioner_compat %0d exact samples, DC steps/settling, 10Hz and1kHz response, extrema/saturation, signed rounding, reset and valid gaps",`CONDITIONER_COUNT);
        $finish;
    end
    initial begin #20000000;$fatal(1,"conditioner timeout");end
endmodule
