`timescale 1ns/1ps
// Read-side expander check. The consumer mimics the scanout: one request every
// two pixel clocks while a line is visible, then blanking. Requests are two
// cycles apart, and the queue must therefore hand over a word and still have it
// present on the next cycle: capture the answer, then require it to hold.
module tb_word_upscaler;
  parameter integer ASPECT_16X9 = 0;
  localparam integer N       = ASPECT_16X9 ? 4 : 3;
  localparam integer WORDS_PER_LINE = ASPECT_16X9 ? 640 : 480;
  localparam integer LINE_CYCLES    = ASPECT_16X9 ? 1650 : 1716;
  localparam integer TOTAL   = 720*WORDS_PER_LINE;

  reg clk=0, rst=1, aspect;
  wire src_read; reg [31:0] src_data=0; reg src_empty=0;
  reg word_read=0; wire [31:0] word_data; wire word_empty;
  always #12.5 clk=~clk;

  word_upscaler dut(.clk(clk),.rst(rst),.aspect_16x9(aspect),
    .src_read(src_read),.src_data(src_data),.src_empty(src_empty),
    .word_read(word_read),.word_data(word_data),.word_empty(word_empty));

  // Distinct halves, so swapping even/odd content cannot pass unnoticed.
  function automatic [31:0] gen(input integer s); gen = {s[15:0], ~s[15:0]}; endfunction
  function automatic [31:0] expect_word(input integer s, input integer p);
    reg [15:0] a, b; begin
      a = gen(s)[15:0]; b = gen(s)[31:16];
      if (ASPECT_16X9) expect_word = (p < 2) ? {a,a} : {b,b};
      else             expect_word = (p == 0) ? {a,a} : (p == 1 ? {b,a} : {b,b});
    end
  endfunction

  integer served=0, src_taken=0, errors=0, underruns=0, cycles=0, line_pos=0;
  reg due=0, hold=0;
  reg [31:0] exp_word=0, ans_word=0;

  // Source FIFO model: the response is valid one clock after the request.
  always @(posedge clk) begin
    if (rst) begin src_data <= 0; src_taken <= 0; end
    else if (src_read) begin src_data <= gen(src_taken); src_taken <= src_taken + 1; end
  end

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (rst) begin word_read <= 0; line_pos <= 0; end
    else begin
      line_pos  <= (line_pos + 1 >= LINE_CYCLES) ? 0 : line_pos + 1;
      // One request every second clock while the line is visible.
      word_read <= (cycles > 40) && (line_pos < 2*WORDS_PER_LINE) && ((cycles % 2) == 0);
    end
  end

  always @(posedge clk) begin
    if (!rst) begin
      due  <= word_read && !word_empty;
      hold <= due;
      if (word_read) begin
        if (word_empty) underruns = underruns + 1;
        exp_word = expect_word(served/N, served%N);
        served   = served + 1;
      end
      if (due) begin
        if (word_data !== exp_word) begin
          errors = errors + 1;
          if (errors < 10) $display("UPSCALE ERROR d=%0d got=%h want=%h", served-1, word_data, exp_word);
        end
        ans_word <= word_data;
      end
      if (hold && word_data !== ans_word) begin
        errors = errors + 1;
        if (errors < 20) $display("UPSCALE HOLD ERROR d=%0d word=%h changed while held", served-2, word_data);
      end
    end
  end

  initial begin
    aspect = ASPECT_16X9;
    repeat (4) @(posedge clk); rst = 0;
    while (served < TOTAL && cycles < 8*LINE_CYCLES*720) @(posedge clk);
    repeat (20) @(posedge clk);
    if (served < TOTAL || errors != 0 || underruns != 0)
      $display("FAIL word_upscaler aspect=%0d served=%0d/%0d errors=%0d underruns=%0d src_words=%0d",
        ASPECT_16X9, served, TOTAL, errors, underruns, src_taken);
    else
      $display("PASS word_upscaler aspect=%0d words=%0d src_words=%0d cycles=%0d ms_at_25ns=%.3f",
        ASPECT_16X9, served, src_taken, cycles, (cycles*25.0)/1000000.0);
    $finish;
  end
endmodule
