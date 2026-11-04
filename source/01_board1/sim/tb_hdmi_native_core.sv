`timescale 1ns / 1ps
// Diagnostic testbench: native 1280x720 video -> rgb_to_axis adapter -> HDMI 1.4b core.
// Observes natural lock only; no forcing of lock, no core internals touched, no EDID model,
// no PHY instance, no electrical/timing-closure claim. Source pixels are counted regardless
// of core ready, matching the production free-running source.

module tb_hdmi_native_core;

  localparam int HACTIVE       = 1280;
  localparam int VACTIVE       = 720;
  localparam int FRAME_PIXELS  = HACTIVE * VACTIVE; // 921600
  localparam int STOP_FRAMES   = 4;
  localparam int RESET_CLKS    = 100;
  localparam real CLK_HALF     = 6.734;             // 74.25 MHz pixel clock
  localparam real WATCHDOG_NS  = 100.0e6;           // 100 ms

  logic clk = 1'b0;
  logic rst = 1'b1;

  always #CLK_HALF clk = ~clk;

  wire hs;
  wire vs;
  wire de;

  wire        axis_user;
  wire        axis_valid;
  wire        axis_last;
  wire [23:0] axis_data;

  wire        core_ready;
  wire        core_locked;
  wire        edid_read_valid;
  wire [7:0]  edid_read_data;
  wire        ddc_scl;
  tri1        ddc_sda;
  wire [9:0]  ch0_tmds;
  wire [9:0]  ch1_tmds;
  wire [9:0]  ch2_tmds;
  wire [9:0]  clk_tmds;

  native_video_timing #(
      .WIDTH        (1280),
      .HEIGHT       (720),
      .HSA          (40),
      .HBP          (220),
      .HFP          (110),
      .VSA          (5),
      .VBP          (20),
      .VFP          (5),
      .HS_POLARITY  (1),
      .VS_POLARITY  (1)
  ) u_timing (
      .clk (clk),
      .rst (rst),
      .hs  (hs),
      .vs  (vs),
      .de  (de)
  );

  video_rgb_to_axis_640x480 #(
      .WIDTH (1280)
  ) u_adapter (
      .I_clk         (clk),
      .I_rst         (rst),
      .I_vs          (vs),
      .I_de          (de),
      .I_rgb         (24'h123456),
      .O_video_user  (axis_user),
      .O_video_valid (axis_valid),
      .O_video_last  (axis_last),
      .O_video_data  (axis_data)
  );

  hdmi_1_4b_transmitter_core_wrapper #(
      .DEVICE            ("EG"),
      .HTOTAL            (1650),
      .HSA               (40),
      .HFP               (110),
      .HBP               (220),
      .HACTIVE           (1280),
      .VTOTAL            (750),
      .VSA               (5),
      .VFP               (5),
      .VBP               (20),
      .VACTIVE           (720),
      .VIDEO_VIC         (4),
      .VIDEO_TPG         ("Disable"),
      .VIDEO_FORMAT      ("RGB"),
      .AUDIO_SAMPLE_RATE ("48K"),
      .IIC_SCL_DIV       (372)
  ) u_core (
      .I_pixel_clk        (clk),
      .I_rst              (rst),
      .I_edid_read_trig   (1'b0),
      .O_edid_read_valid  (edid_read_valid),
      .O_edid_read_data   (edid_read_data),
      .I_axis_s_user      (axis_user),
      .I_axis_s_valid     (axis_valid),
      .I_axis_s_last      (axis_last),
      .I_axis_s_data      (axis_data),
      .O_axis_s_ready     (core_ready),
      .I_audio_valid      (1'b0),
      .I_audio_left_data  (24'd0),
      .I_audio_right_data (24'd0),
      .I_acr_valid        (1'b0),
      .I_acr_cts          (20'd74250),
      .I_acr_n            (20'd6144),
      .O_video_locked     (core_locked),
      .O_ddc_scl          (ddc_scl),
      .IO_ddc_sda         (ddc_sda),
      .O_ch0_tmds_data    (ch0_tmds),
      .O_ch1_tmds_data    (ch1_tmds),
      .O_ch2_tmds_data    (ch2_tmds),
      .O_clk_tmds_data    (clk_tmds)
  );

  int unsigned rst_clks;
  always @(posedge clk) begin
    if (rst_clks < RESET_CLKS) begin
      rst_clks++;
      if (rst_clks == RESET_CLKS) begin
        rst <= 1'b0;
        $display("[%0t] TB: reset released after %0d pixel clocks", $time, rst_clks);
      end
    end
  end

  int unsigned frame_pixels;
  int unsigned frame_lines;
  int unsigned line_pixels;
  int unsigned frame_count;
  int unsigned pixel_viol;
  int unsigned line_viol;
  int unsigned last_viol;
  int unsigned locked_cycles;
  int unsigned lock_trans;
  int unsigned ready_cycles;
  int unsigned tmds_clk_trans;

  logic        locked_prev = 0;
  logic [9:0]  clk_tmds_prev;
  logic        tmds_sampled = 0;
  logic        frame_seen = 0;

  always @(posedge clk) begin
    if (rst == 1'b0) begin
      if (core_locked) begin
        locked_cycles++;
        if (!locked_prev) lock_trans++;
      end
      locked_prev = core_locked;
      if (core_ready === 1'b1) ready_cycles++;

      // A user pulse belongs to the first pixel of the NEW frame. Validate
      // the completed frame before counting that pixel; skip the first SOF.
      if (axis_user) begin
       if(frame_seen) begin
        frame_count++;
        if (frame_pixels != FRAME_PIXELS) pixel_viol++;
        if (frame_lines != VACTIVE) line_viol++;
        $display("CORE_FRAME frame=%0d pixels=%0d lines=%0d lock=%b ready=%b locked_cycles=%0d lock_trans=%0d",
                 frame_count,frame_pixels,frame_lines,core_locked,core_ready,locked_cycles,lock_trans);
        if(frame_count>=STOP_FRAMES) begin
         if(pixel_viol || line_viol || last_viol)$fatal(1,"native geometry mismatch");
         $display("PASS hdmi_native_geometry frames=%0d locked_cycles=%0d lock_transitions=%0d final_lock=%b ready_cycles=%0d tmds_clk_transitions=%0d",
          frame_count,locked_cycles,lock_trans,core_locked,ready_cycles,tmds_clk_trans);
         $finish;
        end
       end
       frame_seen=1;frame_pixels=0;frame_lines=0;line_pixels=0;
      end
      if (axis_valid && frame_seen) begin
        frame_pixels++;
        line_pixels++;
        if (axis_last) begin
          frame_lines++;
          if (line_pixels != HACTIVE) begin
            last_viol++;
            $display("[%0t] TB: last at line width %0d (expected %0d), line %0d of frame %0d",
                     $time, line_pixels, HACTIVE, frame_lines, frame_count + 1);
          end
          line_pixels = 0;
        end
      end

    end
  end

  always @(posedge clk) begin
    if (rst == 1'b0) begin
      if (tmds_sampled && (clk_tmds !== clk_tmds_prev)) tmds_clk_trans++;
      clk_tmds_prev <= clk_tmds;
      tmds_sampled  <= 1'b1;
    end
  end

  initial begin
    #WATCHDOG_NS;
    $display("[%0t] TB: WATCHDOG 100 ms expired frames=%0d pixels=%0d lines=%0d lock=%b",
             $time, frame_count, frame_pixels, frame_lines, core_locked);
    $fatal(1,"natural video diagnostic timeout");
  end

endmodule
