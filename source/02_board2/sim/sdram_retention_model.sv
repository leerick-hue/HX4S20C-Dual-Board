`timescale 1ns/1ps
// Focused functional RETENTION model for BL4/CL3 SDRAM (simulation only).
// Unlike sdram_scan_model, READ returns the ACTUAL stored memory[] contents;
// values are never synthesized from addresses. This is a functional
// data-retention model, NOT a vendor SI/timing/refresh/retention-physics
// proof, and it performs no encryption decoding.
module sdram_retention_model #(
  parameter real CLOCK_FLIGHT_NS = 4.097,
  parameter real READ_DELAY_NS   = 6.453,
  parameter integer MEMORY_WORDS = 2097152,
  // Test-only READ latency knob. Default 3 models the configured CL3; value 2 is
  // deliberate early-return fault injection to reproduce observed one-word-ahead
  // data, not a claim actual SDRAM uses CL2.
  parameter integer READ_LATENCY_CYCLES = 3
)(
  input clk, input rst, input ras, input cas, input we,
  input [1:0] ba,
  input [10:0] addr,
  input [3:0] dm,
  inout [31:0] dq,
  output integer writes = 0,
  output integer reads  = 0
);

  wire memory_clk;
  assign #(CLOCK_FLIGHT_NS) memory_clk = clk;

  // Retained storage: deliberately UNINITIALIZED so untouched words stay X
  // until written. Reset must NOT wipe this array.
  reg [31:0] memory [0:MEMORY_WORDS-1];

  reg [31:0] value = 0;
  reg drive = 0;
  assign dq = drive ? value : 32'bz;

  reg [10:0] row [0:3];
  reg        scheduled [0:31];
  reg [31:0] data      [0:31];

  integer cycle = 0;
  integer write_left = 0;    // remaining data beats after the WRITE command
  integer write_row_base = 0;
  integer write_col = 0;     // start column [7:0] of the current write burst
  integer slot, idx, beat_col;
  integer row_max;
  integer i;

  initial row_max = MEMORY_WORDS / 1024;

  // Physical layout: index = ((row*4)+bank)*256 + column
  // Supports all 4 banks x 2048 rows x 256 columns.
  function automatic integer location(input integer bank, input integer col);
    location = ((row[bank]*4 + bank) * 256) + (col & 8'hFF);
  endfunction

  // BL4 increment: keep column upper 6 bits fixed, wrap only the low 2 bits.
  function automatic integer burst_col(input integer start, input integer beat);
    burst_col = (start & 8'hFC) | ((start + beat) & 8'h03);
  endfunction

  task automatic check_index(input integer ind, input string op);
    begin
      if (ind < 0 || ind >= MEMORY_WORDS)
        $fatal(1, "retention model: %s physical index %0d out of range (memory size %0d)", op, ind, MEMORY_WORDS);
    end
  endtask

  // One 32-bit word write with independent per-byte DM mask (DM bit=1
  // preserves the old byte). Unknown DQ on any unmasked byte is fatal.
  task automatic store_word(input integer ind, input [31:0] w, input [3:0] mask);
    begin
      check_index(ind, "WRITE");
      if (((mask[0] === 1'b0) && (^w[ 7: 0] === 1'bx)) ||
          ((mask[1] === 1'b0) && (^w[15: 8] === 1'bx)) ||
          ((mask[2] === 1'b0) && (^w[23:16] === 1'bx)) ||
          ((mask[3] === 1'b0) && (^w[31:24] === 1'bx)))
        $fatal(1, "retention model: WRITE idx=%0d got unknown DQ=%h on unmasked byte (DM=%b)", ind, w, mask);
      if (mask[0] === 1'b0) memory[ind][ 7: 0] <= w[ 7: 0];
      if (mask[1] === 1'b0) memory[ind][15: 8] <= w[15: 8];
      if (mask[2] === 1'b0) memory[ind][23:16] <= w[23:16];
      if (mask[3] === 1'b0) memory[ind][31:24] <= w[31:24];
      writes = writes + 1;
    end
  endtask

  // READ returns retained storage. Words never written are legitimately X.
  function automatic [31:0] read_word(input integer ind);
    begin
      check_index(ind, "READ");
      read_word = memory[ind];
    end
  endfunction

  always @(posedge memory_clk or posedge rst) begin
    if (rst) begin
      // Clear scheduling, counters, row registers, burst state, output drive.
      // The memory[] array is intentionally preserved (retention).
      writes = 0; reads = 0; cycle = 0;
      write_left = 0; write_col = 0; write_row_base = 0;
      drive <= 0; value <= 0;
      for (i = 0; i < 4; i = i + 1)  row[i] = 0;
      for (i = 0; i < 32; i = i + 1) scheduled[i] = 0;
    end else begin
      // CL3 launch: a slot scheduled 3 cycles earlier drives now, after the
      // clock-to-pad flight template delay.
      drive <= #(READ_DELAY_NS) scheduled[cycle % 32];
      if (scheduled[cycle % 32]) value <= #(READ_DELAY_NS) data[cycle % 32];
      scheduled[cycle % 32] = 0;

      // Continuation beats of an in-progress WRITE burst on the memory
      // clock edges following the WRITE command.
      if (write_left > 0) begin
        beat_col = burst_col(write_col, 4 - write_left);
        store_word(write_row_base + beat_col, dq, dm);
        write_left = write_left - 1;
      end

      case ({ras, cas, we})
        3'b011: begin // ACT: latch row, must fit the modeled row space
          if (addr >= row_max)
            $fatal(1, "retention model: ACT row %0d out of range for memory size %0d", addr, MEMORY_WORDS);
          row[ba] = addr;
        end
        3'b000: begin // MRS: assert burst-4, CAS latency 3, sequential burst
          if (addr[2:0] !== 3'd2 || addr[6:4] !== 3'd3 || addr[3] !== 1'b0)
            $fatal(1, "retention model: expected BL4/CL3 sequential mode, got addr=%h", addr);
        end
        3'b100: begin // WRITE: first DQ beat captured on the command edge,
                      // next 3 beats on the following memory clock edges
          if (write_left > 0)
            $fatal(1, "retention model: new WRITE overlaps active write burst (%0d beats remaining)", write_left);
          write_row_base = ((row[ba]*4 + ba) * 256);
          write_col = addr[7:0];
          store_word(location(ba, burst_col(write_col, 0)), dq, dm);
          write_left = 3;
        end
        3'b101: begin // READ: schedule stored data at CL3, 4 contiguous beats
          for (i = 0; i < 4; i = i + 1) begin
            slot = (cycle + READ_LATENCY_CYCLES + i) % 32;
            if (scheduled[slot])
              $fatal(1, "retention model: READ slot %0d already scheduled (overlap)", slot);
            idx = location(ba, burst_col(addr[7:0], i));
            scheduled[slot] = 1;
            data[slot] = read_word(idx);
          end
          reads = reads + 4;
        end
      endcase
      cycle = cycle + 1;
    end
  end

endmodule
