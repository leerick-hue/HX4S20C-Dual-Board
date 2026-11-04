// Unit test for the new "short press = toggle / long press = step interval" logic
// inside sd_card_bmp. CLK_FREQ_HZ is set to 100 kHz so that debounce (20 ms =
// 2000 cycles) and hold (1.2 s = 120000 cycles) stay short in simulation.
// No SD/BMP traffic: scan results are forced ready so only the key decision
// logic is exercised.
`timescale 1ns/1ps
module tb_auto_interval;
    localparam integer F = 100_000;          // must equal the DUT CLK_FREQ_HZ
    localparam integer CYC_DEBOUNCE = 2000;  // (F/1000)*20
    localparam integer CYC_HOLD     = 120000;// (F/1000)*1200

    reg clk = 0, rst = 1;
    reg key_next = 1, key_auto = 1, key_inhibit = 0, pixel_ready = 1;
    reg remote_next = 0, remote_auto_valid = 0, remote_auto_enable = 0;
    wire remote_ready, swap_valid, swap_bank, write_req, write_en, sd_sec_read, auto_play_enabled;
    wire display_valid;
    wire [10:0] source_width_debug, source_height_debug;
    wire [19:0] write_pixel_addr;
    wire [3:0] state_code;
    wire [11:0] debug_status;
    wire [1:0] displayed_image_index, write_buf_idx, disp_buf_idx;
    wire [2:0] detected_image_count;
    wire [31:0] write_data, sd_sec_read_addr;

    always #5 clk = ~clk;

    sd_card_bmp #(.CLK_FREQ_HZ(F), .WIDTH(1280), .HEIGHT(720)) dut (
        .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
        .remote_next(remote_next), .remote_auto_valid(remote_auto_valid),
        .remote_auto_enable(remote_auto_enable), .remote_ready(remote_ready),
        .key_inhibit(key_inhibit), .pixel_ready(pixel_ready),
        .source_width_debug(source_width_debug), .source_height_debug(source_height_debug),
        .write_pixel_addr(write_pixel_addr), .swap_valid(swap_valid), .swap_ready(1'b1),
        .swap_done(1'b0), .swap_bank(swap_bank), .state_code(state_code),
        .debug_status(debug_status), .displayed_image_index(displayed_image_index),
        .detected_image_count(detected_image_count), .auto_play_enabled(auto_play_enabled),
        .bmp_width(16'd1280), .bmp_height(16'd720), .display_valid(display_valid),
        .write_finish_toggle(1'b0), .write_buf_idx(write_buf_idx), .disp_buf_idx(disp_buf_idx),
        .write_req(write_req), .write_req_ack(1'b1), .write_en(write_en), .write_data(write_data),
        .sd_init_done(1'b1), .media_ready(1'b1),
        .media_photo_start(32'd4), .media_photo_max(32'd4), .media_photo_count(3'd3),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(8'h00), .sd_sec_read_data_valid(1'b0), .sd_sec_read_end(1'b0)
    );

    integer errors = 0;
    task check(input [255:0] name, input integer got, input integer exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got %0d expected %0d", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("ok   %0s = %0d", name, got);
            end
        end
    endtask

    task hold_key(input integer cycles);
        begin key_auto = 1'b0; repeat (cycles) @(posedge clk); end
    endtask
    task release_key(input integer cycles);
        begin key_auto = 1'b1; repeat (cycles) @(posedge clk); end
    endtask

    integer i;
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_auto_interval.vcd"); $dumpvars(0, tb_auto_interval);
        end
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        force dut.scan_done = 1'b1;
        force dut.img_found_count = 3'd3;
        repeat (10) @(posedge clk);

        check("default tier", dut.auto_sel, 0);
        check("default auto off", auto_play_enabled, 0);

        // 1) short press: toggle happens on release only, tier unchanged
        hold_key(4 * CYC_DEBOUNCE);
        check("no toggle while held", auto_play_enabled, 0);
        release_key(4 * CYC_DEBOUNCE);
        check("short press turns auto on", auto_play_enabled, 1);
        check("short press keeps tier", dut.auto_sel, 0);

        // 2) long press: step at threshold, no toggle on release
        hold_key(CYC_HOLD + 4 * CYC_DEBOUNCE);
        check("long press steps to tier 1", dut.auto_sel, 1);
        check("auto stays on during hold", auto_play_enabled, 1);
        release_key(4 * CYC_DEBOUNCE);
        check("auto still on after long release", auto_play_enabled, 1);
        check("tier holds after long release", dut.auto_sel, 1);

        // 3) three more long presses -> 2, 3, 4
        for (i = 0; i < 3; i = i + 1) begin
            hold_key(CYC_HOLD + 4 * CYC_DEBOUNCE);
            release_key(4 * CYC_DEBOUNCE);
        end
        check("steps to top tier", dut.auto_sel, 4);

        // 4) one more long press wraps back to 0
        hold_key(CYC_HOLD + 4 * CYC_DEBOUNCE);
        release_key(4 * CYC_DEBOUNCE);
        check("top tier wraps to 0", dut.auto_sel, 0);
        check("wrap keeps auto on", auto_play_enabled, 1);

        // 5) long press must not step while another control mode is active
        key_inhibit = 1'b1;
        repeat (5) @(posedge clk);
        hold_key(CYC_HOLD + 4 * CYC_DEBOUNCE);
        release_key(4 * CYC_DEBOUNCE);
        check("inhibit blocks tier step", dut.auto_sel, 0);
        key_inhibit = 1'b0;
        repeat (5) @(posedge clk);

        // 6) short press turns auto off again
        hold_key(4 * CYC_DEBOUNCE);
        release_key(4 * CYC_DEBOUNCE);
        check("short press turns auto off", auto_play_enabled, 0);

        if (errors == 0) $display("PASS auto_interval: short=toggle on release, long=step 1/2/5/10/30 with wrap, inhibit blocks step");
        else $display("FAIL auto_interval: %0d errors", errors);
        $finish;
    end
endmodule
