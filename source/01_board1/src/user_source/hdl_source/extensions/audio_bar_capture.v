`timescale 1ns/1ps
// 32 short-window stereo peaks, oldest on the left and newest on the right.
// WINDOW_SAMPLES=1536 at 48 kHz gives 32 ms per bar, about one second in total.
// Use WINDOW_SAMPLES>=64: the 32-clock snapshot copy then completes before the
// next history entry. Audio/history always continue while a display waits.
// Both resets assert together; each domain may release its reset independently.
// Display data uses the same one-cycle synchronous RAM contract as the waveform.
// Four PCM stages accept one sample per clock: abs, stereo max, amplitude
// compression, then window/envelope/history. History is three clocks later than
// the unpipelined implementation, with exactly the same valid-sample windows.
module audio_bar_capture #(
    parameter integer WINDOW_SAMPLES=1536
)(
    input wire audio_clk,audio_rst_n,
    input wire signed [23:0] pcm_left,pcm_right,
    input wire pcm_valid,
    input wire pixel_clk,pixel_rst_n,vblank_start,
    input wire [6:0] wave_addr,
    output wire signed [7:0] wave_sample,
    output reg wave_valid
);
    localparam integer COUNT_BITS=$clog2(WINDOW_SAMPLES);
    localparam integer PCM_LATENCY=3;
    reg [COUNT_BITS-1:0] sample_count;
    reg [23:0] left_abs0,right_abs0,stereo_peak1;
    reg [6:0] sample_level2,window_peak;
    reg [2:0] valid_pipe;
    reg [6:0] envelope;
    // Synchronous RAM plus a32-cycle scrub avoids the224-flop asynchronous
    // clear/mux tree. The first window contains at least64 samples.
    reg [6:0] history[0:31] /* fehdl force_ram=1, ram_style="bram" */;
    reg [5:0] initialize_count;
    reg [6:0] history_q;
    reg copy_valid;
    reg [4:0] copy_destination;
    reg [4:0] write_index,copy_base,copy_index;
    reg copy_active,publish_pending,write_bank,request_toggle;
    reg display_bank,acknowledge_toggle;
    (* ASYNC_REG="TRUE" *) reg [1:0] acknowledge_sync,request_sync;
    reg [7:0] snapshots[0:63] /* fehdl force_ram=1, ram_style="bram" */;
    reg [7:0] read_q;
    integer i;

    wire [6:0] next_peak=(window_peak>sample_level2)?window_peak:sample_level2;
    // Fixed compressed amplitude scale, not automatic gain. Halving a signal
    // changes roughly 16 levels; exact digital silence remains level zero.
    function [6:0] amplitude_level;
        input [23:0] magnitude;
        begin
            if(magnitude[23]) amplitude_level=7'd127;
            else if(magnitude[22]) amplitude_level=7'd112+{3'd0,magnitude[21:18]};
            else if(magnitude[21]) amplitude_level=7'd96+{3'd0,magnitude[20:17]};
            else if(magnitude[20]) amplitude_level=7'd80+{3'd0,magnitude[19:16]};
            else if(magnitude[19]) amplitude_level=7'd64+{3'd0,magnitude[18:15]};
            else if(magnitude[18]) amplitude_level=7'd48+{3'd0,magnitude[17:14]};
            else if(magnitude[17]) amplitude_level=7'd32+{3'd0,magnitude[16:13]};
            else if(magnitude[16]) amplitude_level=7'd16+{3'd0,magnitude[15:12]};
            else amplitude_level={3'd0,magnitude[15:12]};
        end
    endfunction
    // This fixed amplitude mapping is monotone, so compress(max(samples)) is
    // exactly max(compress(samples)). Keep the running window peak at seven
    // bits to avoid a 24-bit comparator followed by this encoder in one stage.
    wire [6:0] target_level=next_peak;
    wire [6:0] decayed=(envelope>7'd6)?envelope-7'd6:7'd0;
    wire [6:0] next_level=(target_level>decayed)?target_level:decayed;
    wire [4:0] copy_address=copy_base+copy_index;
    wire commit=pixel_rst_n && vblank_start && (request_sync[1]!=acknowledge_toggle);
    wire read_bank=commit?~request_sync[1]:display_bank;

    always @(posedge audio_clk) begin
        history_q<=history[copy_address];
        if(audio_rst_n) begin
            if(initialize_count<32) history[initialize_count[4:0]]<=0;
            else if(valid_pipe[2] && sample_count==WINDOW_SAMPLES-1)
                history[write_index]<=next_level;
            if(copy_valid) snapshots[{write_bank,copy_destination}]<={1'b0,history_q};
        end
    end
    always @(posedge pixel_clk)
        read_q<=snapshots[{read_bank,wave_addr[4:0]}];
    assign wave_sample=wave_valid?$signed(read_q):8'sd0;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if(!audio_rst_n) begin
            sample_count<=0;window_peak<=0;envelope<=0;write_index<=0;
            left_abs0<=0;right_abs0<=0;stereo_peak1<=0;sample_level2<=0;valid_pipe<=0;
            copy_base<=0;copy_index<=0;copy_active<=0;publish_pending<=0;
            write_bank<=0;request_toggle<=0;acknowledge_sync<=0;
            initialize_count<=0;copy_valid<=0;copy_destination<=0;
        end else begin
            if(initialize_count<32)initialize_count<=initialize_count+1'b1;
            copy_valid<=copy_active;
            if(copy_active)copy_destination<=copy_index;
            valid_pipe<={valid_pipe[1:0],pcm_valid};
            left_abs0<=pcm_left[23]?(~pcm_left+24'd1):pcm_left;
            right_abs0<=pcm_right[23]?(~pcm_right+24'd1):pcm_right;
            stereo_peak1<=(left_abs0>right_abs0)?left_abs0:right_abs0;
            sample_level2<=amplitude_level(stereo_peak1);
            acknowledge_sync<={acknowledge_sync[0],acknowledge_toggle};
            if(publish_pending && acknowledge_sync[1]==request_toggle) begin
                publish_pending<=0;write_bank<=~write_bank;
            end
            if(copy_active) begin
                if(copy_index==31) begin
                    copy_active<=0;
                end else copy_index<=copy_index+1'b1;
            end
            // The synchronous history read needs one final write/flush clock.
            if(copy_valid && copy_destination==31)begin
                request_toggle<=~request_toggle;publish_pending<=1;
            end
            if(valid_pipe[2]) begin
                if(sample_count==WINDOW_SAMPLES-1) begin
                    sample_count<=0;window_peak<=0;envelope<=next_level;
                    write_index<=write_index+1'b1;
                    if(!publish_pending && !copy_active) begin
                        copy_active<=1;copy_index<=0;copy_base<=write_index+1'b1;
                    end
                end else begin
                    sample_count<=sample_count+1'b1;window_peak<=next_peak;
                end
            end
        end
    end
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            request_sync<=0;display_bank<=1;acknowledge_toggle<=0;wave_valid<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};
            if(commit) begin
                display_bank<=~request_sync[1];acknowledge_toggle<=request_sync[1];wave_valid<=1;
            end
        end
    end
endmodule
