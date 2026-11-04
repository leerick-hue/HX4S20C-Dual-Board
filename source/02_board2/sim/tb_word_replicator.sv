`timescale 1ns/1ps
// Layout check for the write-side vertical replicator.
// Every source word (two adjacent 565 pixels) must appear once per destination
// row of its block, at (scale*row + block_row)*160 + word_in_row.
module tb_word_replicator;
  parameter integer ASPECT_16X9 = 0;
  localparam integer SRC_H = ASPECT_16X9 ? 180 : 240;
  localparam integer N     = ASPECT_16X9 ? 4 : 3;
  localparam integer TOTAL = SRC_H*160*N;

  reg clk=0, rst=1, aspect, frame_start=0;
  reg src_valid=0, out_ready=1; wire src_ready; reg [31:0] src_data=0;
  wire out_valid; wire [20:0] out_addr;
  always #12.5 clk=~clk;
  reg [8:0] src_row, src_word;
  word_replicator dut(.clk(clk),.rst(rst),.aspect_16x9(aspect),.frame_start(frame_start),
    .src_valid(src_valid),.src_ready(src_ready),.src_row(src_row),.src_word(src_word),
    .out_valid(out_valid),.out_ready(out_ready),.out_addr(out_addr));

  integer accepted=0, emitted=0, errors=0, rnd=11, cycles=0;
  // Distinct content per source word, and the same value held while stalled.
  function automatic [31:0] word_of(input integer sy, input integer j);
    word_of = {8'h5a, sy[7:0], j[7:0], ~sy[7:0]};
  endfunction

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (rst) begin accepted<=0; src_valid<=0; src_row<=0; src_word<=0; end
    else begin
      if (src_valid && src_ready) begin
        // MCU-block order: eight words per block column run, then the next row
        // of the block, so a stream counter can never predict the destination.
        if (src_word == 159) begin src_word <= 0; src_row <= (src_row + 1) % SRC_H; end
        else src_word <= src_word + 1;
        accepted <= (accepted == SRC_H*160-1) ? 0 : accepted+1;
        src_valid <= ($random(rnd) % 8) != 0;
      end else if (!src_valid) src_valid <= ($random(rnd) % 3) != 0;
      src_data <= word_of(src_row, src_word);
      out_ready <= ($random(rnd) % 6) != 0;         // ~17% downstream stalls
      if (out_valid && out_ready && emitted < TOTAL) begin
        integer w, sy, j, dy, want;
        // Emission order: all copies of source word 0, then word 1, ...
        w = emitted/N; dy = emitted%N; sy = w/160; j = w%160;
        want = (N*sy + dy)*160 + j;
        if (out_addr !== want[20:0]) begin
          errors = errors + 1;
          if (errors < 10) $display("REPL ERROR e=%0d sy=%0d j=%0d dy=%0d got=%h want=%h",
            emitted, sy, j, dy, out_addr, want);
        end
        emitted = emitted + 1;
      end
    end
  end

  initial begin
    aspect = ASPECT_16X9;
    repeat (4) @(posedge clk); rst = 0;
    frame_start = 1; @(posedge clk); frame_start = 0;
    while (emitted < TOTAL && cycles < 60*TOTAL) @(posedge clk);
    src_valid <= 0; out_ready <= 1;
    repeat (8) @(posedge clk);
    if (emitted < TOTAL || errors != 0)
      $display("FAIL word_replicator aspect=%0d emitted=%0d/%0d errors=%0d", ASPECT_16X9, emitted, TOTAL, errors);
    else
      $display("PASS word_replicator aspect=%0d words=%0d cycles=%0d ms_at_40MHz=%.3f",
        ASPECT_16X9, emitted, cycles, (cycles*25.0)/1000000.0);
    $finish;
  end
endmodule
