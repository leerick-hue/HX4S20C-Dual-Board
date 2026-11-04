`timescale 1ns/1ps
module tb_dtw_compat;
    localparam integer MAX_FRAMES = 128;
    localparam integer MAX_SCORE = 96;
    localparam integer MIN_MARGIN = 8;
    localparam integer INF = 32'h3fffffff;

    reg clk = 0;
    always #10 clk = ~clk;

    reg rst_n = 0;
    reg segment_start = 0;
    reg segment_end = 0;
    reg segment_abort = 0;
    reg [1:0] train_class = 0;
    reg feature_valid = 0;
    reg [63:0] feature_data = 0;
    wire segment_ready;
    wire feature_ready;
    wire [2:0] template_mask;
    wire train_done;
    wire result_valid;
    wire accepted;
    wire [15:0] best_score;
    wire [15:0] second_score;
    wire command_valid;
    reg command_ready = 0;
    wire [15:0] command_id;
    wire [31:0] reject_count;
    wire [31:0] abort_count;

    speech_dtw #(
        .MAX_FRAMES(MAX_FRAMES),
        .MIN_FRAMES(4),
        .MAX_SCORE(MAX_SCORE),
        .MIN_MARGIN(MIN_MARGIN)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .segment_start(segment_start), .segment_end(segment_end), .segment_abort(segment_abort),
        .train_class(train_class), .feature_valid(feature_valid), .feature_data(feature_data),
        .segment_ready(segment_ready), .feature_ready(feature_ready),
        .template_mask(template_mask), .train_done(train_done),
        .result_valid(result_valid), .accepted(accepted), .best_score(best_score),
        .second_score(second_score), .command_valid(command_valid), .command_ready(command_ready),
        .command_id(command_id), .reject_count(reject_count), .abort_count(abort_count)
    );

    reg [63:0] stimulus [0:MAX_FRAMES];
    reg [63:0] gold_template [1:3][0:MAX_FRAMES-1];
    integer gold_len [1:3];
    reg gold_valid [1:3];
    integer stimulus_len = 0;

    reg stalled_command = 0;
    reg [15:0] held_command_id = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            stalled_command = 0;
            held_command_id = 0;
        end else begin
            if (stalled_command && (!command_valid || command_id !== held_command_id))
                $fatal(1, "command output changed while ready was low");
            stalled_command = command_valid && !command_ready;
            if (command_valid && !command_ready) held_command_id = command_id;
        end
    end

    function automatic [63:0] make_feature;
        input integer class_id;
        input integer phase;
        input integer length;
        input integer delta;
        integer peak;
        integer d;
        integer mag;
        integer value;
        reg [63:0] packed_value;
        begin
            packed_value = 64'b0;
            if (class_id == 3) begin
                peak = (phase * 3 + 2) % 8;
                for (d = 0; d < 8; d = d + 1) begin
                    if (d == peak) value = 0;
                    else begin
                        mag = 8 + ((phase * 11 + d * 5 + phase * d * 3) % 31);
                        value = -mag;
                    end
                    value = value + delta;
                    if (value > 127) value = 127;
                    if (value < -128) value = -128;
                    packed_value[d*8 +: 8] = value[7:0];
                end
            end else begin
                peak = phase % 8;
                for (d = 0; d < 8; d = d + 1) begin
                    if (d == peak) value = 0;
                    else begin
                        mag = 6 + ((phase * 7 + d * 11 + phase * d) % 23);
                        value = -mag;
                    end
                    value = value + delta;
                    if (value > 127) value = 127;
                    if (value < -128) value = -128;
                    packed_value[d*8 +: 8] = value[7:0];
                end
            end
            make_feature = packed_value;
        end
    endfunction

    task make_sequence;
        input integer class_id;
        input integer length;
        input integer delta;
        integer i;
        integer phase;
        begin
            stimulus_len = length;
            for (i = 0; i < length && i <= MAX_FRAMES; i = i + 1) begin
                if (class_id == 2) phase = length - 1 - i;
                else phase = i;
                stimulus[i] = make_feature(class_id, phase, length, delta);
            end
        end
    endtask

    task make_stretched_sequence;
        input integer class_id;
        input integer base_length;
        integer i;
        integer phase;
        begin
            stimulus_len = base_length * 2;
            for (i = 0; i < stimulus_len; i = i + 1) begin
                phase = i / 2;
                if (class_id == 2) phase = base_length - 1 - phase;
                stimulus[i] = make_feature(class_id, phase, base_length, 0);
            end
        end
    endtask

    task make_unknown_sequence;
        input integer length;
        integer i;
        integer d;
        integer peak;
        reg [63:0] packed_value;
        begin
            stimulus_len = length;
            for (i = 0; i < length; i = i + 1) begin
                packed_value = 64'b0;
                peak = i % 8;
                for (d = 0; d < 8; d = d + 1)
                    packed_value[d*8 +: 8] = (d == peak) ? 8'h00 : 8'h80;
                stimulus[i] = packed_value;
            end
        end
    endtask

    task wait_segment_ready;
        integer cycles;
        begin
            cycles = 0;
            while (segment_ready !== 1'b1 && cycles < 10000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (segment_ready !== 1'b1) $fatal(1, "segment_ready timeout");
        end
    endtask

    task begin_with_first_feature;
        input [1:0] class_id;
        input [63:0] first_feature;
        input integer end_on_first;
        begin
            wait_segment_ready();
            @(negedge clk);
            segment_start = 1;
            train_class = class_id;
            feature_valid = 1;
            feature_data = first_feature;
            segment_end = end_on_first != 0;
            @(posedge clk);
            if (segment_ready !== 1'b1) $fatal(1, "segment_start was not accepted while ready");
            if (feature_ready !== 1'b1) $fatal(1, "first feature was not accepted with segment_start");
            @(negedge clk);
            segment_start = 0;
            feature_valid = 0;
            segment_end = 0;
        end
    endtask

    task send_feature;
        input [63:0] value;
        input integer is_last;
        integer cycles;
        reg did_handshake;
        begin
            @(negedge clk);
            feature_valid = 1;
            feature_data = value;
            segment_end = is_last != 0;
            cycles = 0;
            did_handshake = 0;
            while (!did_handshake && cycles < 10000) begin
                @(posedge clk);
                if (feature_ready === 1'b1) did_handshake = 1;
                cycles = cycles + 1;
            end
            if (!did_handshake) $fatal(1, "feature_ready timeout");
            @(negedge clk);
            feature_valid = 0;
            segment_end = 0;
        end
    endtask

    task submit_stimulus;
        input [1:0] class_id;
        input integer length;
        integer i;
        begin
            if (length < 1) $fatal(1, "submit_stimulus requires at least one feature");
            begin_with_first_feature(class_id, stimulus[0], length == 1);
            for (i = 1; i < length; i = i + 1)
                send_feature(stimulus[i], i == length - 1);
        end
    endtask

    task wait_train_done;
        integer cycles;
        begin
            cycles = 0;
            while (train_done !== 1'b1 && cycles < 500000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (train_done !== 1'b1) $fatal(1, "train_done timeout");
            @(negedge clk);
            if (train_done !== 1'b0) $fatal(1, "train_done was not a one-cycle pulse");
        end
    endtask

    task remember_template;
        input integer class_id;
        input integer length;
        integer i;
        begin
            gold_len[class_id] = length;
            gold_valid[class_id] = 1;
            for (i = 0; i < length; i = i + 1)
                gold_template[class_id][i] = stimulus[i];
        end
    endtask

    task train_sequence;
        input integer class_id;
        input integer length;
        input [2:0] expected_mask;
        begin
            make_sequence(class_id, length, 0);
            submit_stimulus(class_id[1:0], length);
            wait_train_done();
            remember_template(class_id, length);
            if (template_mask !== expected_mask)
                $fatal(1, "template mask after class %0d: got %b expected %b", class_id, template_mask, expected_mask);
        end
    endtask

    task calc_class_score;
        input integer class_id;
        output integer score;
        integer dp [0:MAX_FRAMES][0:MAX_FRAMES];
        integer i;
        integer j;
        integer d;
        integer local_cost;
        integer best_predecessor;
        integer difference;
        reg signed [7:0] query_lane;
        reg signed [7:0] template_lane;
        begin
            for (i = 0; i <= stimulus_len; i = i + 1) dp[i][0] = INF;
            for (j = 0; j <= gold_len[class_id]; j = j + 1) dp[0][j] = INF;
            dp[0][0] = 0;
            for (i = 1; i <= stimulus_len; i = i + 1) begin
                for (j = 1; j <= gold_len[class_id]; j = j + 1) begin
                    local_cost = 0;
                    for (d = 0; d < 8; d = d + 1) begin
                        query_lane = stimulus[i-1][d*8 +: 8];
                        template_lane = gold_template[class_id][j-1][d*8 +: 8];
                        difference = query_lane - template_lane;
                        if (difference < 0) difference = -difference;
                        local_cost = local_cost + difference;
                    end
                    best_predecessor = dp[i-1][j];
                    if (dp[i][j-1] < best_predecessor) best_predecessor = dp[i][j-1];
                    if (dp[i-1][j-1] < best_predecessor) best_predecessor = dp[i-1][j-1];
                    dp[i][j] = local_cost + best_predecessor;
                end
            end
            score = dp[stimulus_len][gold_len[class_id]] / (stimulus_len + gold_len[class_id]);
        end
    endtask

    task reference_scores;
        output integer best;
        output integer second;
        output integer best_class;
        integer score1;
        integer score2;
        integer score3;
        begin
            calc_class_score(1, score1);
            calc_class_score(2, score2);
            calc_class_score(3, score3);
            best = score1;
            second = INF;
            best_class = 1;
            if (score2 < best) begin
                second = best;
                best = score2;
                best_class = 2;
            end else second = score2;
            if (score3 < best) begin
                second = best;
                best = score3;
                best_class = 3;
            end else if (score3 < second) second = score3;
        end
    endtask

    task wait_result;
        integer cycles;
        begin
            cycles = 0;
            while (result_valid !== 1'b1 && cycles < 1000000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (result_valid !== 1'b1) $fatal(1, "result_valid timeout");
        end
    endtask

    task infer_and_check;
        input integer expected_accept;
        input integer extra_hold_cycles;
        integer expected_best;
        integer expected_second;
        integer expected_class;
        integer expected_decision;
        integer old_rejects;
        integer cycles;
        reg saw_command;
        begin
            if (template_mask !== 3'b111) $fatal(1, "inference called before all templates are trained");
            reference_scores(expected_best, expected_second, expected_class);
            expected_decision = (expected_best <= MAX_SCORE) && ((expected_second - expected_best) >= MIN_MARGIN);
            if (expected_decision != expected_accept)
                $fatal(1, "bad directed vector: expected acceptance %0d, golden decision %0d (scores %0d/%0d class %0d)",
                    expected_accept, expected_decision, expected_best, expected_second, expected_class);
            old_rejects = reject_count;
            command_ready = 0;
            submit_stimulus(2'b00, stimulus_len);
            wait_result();
            if (best_score !== 16'(expected_best) || second_score !== 16'(expected_second))
                $fatal(1, "DTW score mismatch: got %0d/%0d expected %0d/%0d", best_score, second_score, expected_best, expected_second);
            if (accepted !== expected_decision[0])
                $fatal(1, "DTW accept mismatch: got %b expected %0d", accepted, expected_decision);

            if (expected_decision) begin
                cycles = 0;
                saw_command = 0;
                while (!saw_command && cycles < 1000) begin
                    @(negedge clk);
                    if (command_valid === 1'b1) saw_command = 1;
                    cycles = cycles + 1;
                end
                if (!saw_command) $fatal(1, "accepted result did not produce command_valid");
                if (command_id !== 16'(expected_class))
                    $fatal(1, "command ID mismatch: got %0d expected %0d", command_id, expected_class);
                repeat (extra_hold_cycles + 2) begin
                    @(negedge clk);
                    if (!command_valid || command_id !== 16'(expected_class) || segment_ready)
                        $fatal(1, "command/segment_ready did not hold through backpressure");
                end
                if (reject_count !== old_rejects)
                    $fatal(1, "accepted inference changed reject_count");
                command_ready = 1;
                @(posedge clk);
                if (!command_valid || !command_ready || command_id !== 16'(expected_class))
                    $fatal(1, "command handshake missing");
                @(negedge clk);
                command_ready = 0;
                if (command_valid) $fatal(1, "command_valid did not clear after handshake");
                wait_segment_ready();
            end else begin
                repeat (4) begin
                    @(negedge clk);
                    if (command_valid) $fatal(1, "rejected inference produced a command");
                end
                if (reject_count !== old_rejects + 1)
                    $fatal(1, "reject_count did not increment exactly once: old %0d new %0d", old_rejects, reject_count);
                wait_segment_ready();
            end
        end
    endtask

    task check_no_command;
        input integer wait_cycles;
        integer i;
        begin
            for (i = 0; i < wait_cycles; i = i + 1) begin
                @(negedge clk);
                if (command_valid) $fatal(1, "command emitted when fewer than three templates were trained");
            end
        end
    endtask

    task abort_training_segment;
        input integer class_id;
        integer old_aborts;
        begin
            make_sequence(3, 8, 0);
            wait_segment_ready();
            begin_with_first_feature(class_id[1:0], stimulus[0], 0);
            send_feature(stimulus[1], 0);
            old_aborts = abort_count;
            @(negedge clk);
            feature_valid = 1;
            feature_data = stimulus[2];
            segment_end = 1;
            segment_abort = 1;
            @(posedge clk);
            @(negedge clk);
            feature_valid = 0;
            segment_end = 0;
            segment_abort = 0;
            wait_segment_ready();
            if (abort_count !== old_aborts + 1)
                $fatal(1, "explicit abort_count did not increment exactly once");
            if (train_done || template_mask !== 3'b111)
                $fatal(1, "aborted enrollment changed template state");
        end
    endtask

    task invalid_short_training;
        integer old_aborts;
        reg [2:0] old_mask;
        begin
            old_mask = template_mask;
            old_aborts = abort_count;
            make_sequence(3, 3, 0);
            submit_stimulus(2'd1, 3);
            wait_segment_ready();
            if (train_done || template_mask !== old_mask)
                $fatal(1, "short enrollment updated a template");
            if (abort_count !== old_aborts + 1)
                $fatal(1, "short segment did not increment abort_count exactly once");
        end
    endtask

    task overlength_training;
        integer i;
        integer cycles;
        integer old_aborts;
        reg [2:0] old_mask;
        reg extra_accepted;
        begin
            old_mask = template_mask;
            old_aborts = abort_count;
            make_sequence(3, MAX_FRAMES + 1, 0);
            begin_with_first_feature(2'd3, stimulus[0], 0);
            for (i = 1; i < MAX_FRAMES; i = i + 1)
                send_feature(stimulus[i], 0);

            @(negedge clk);
            feature_valid = 1;
            feature_data = stimulus[MAX_FRAMES];
            segment_end = 1;
            cycles = 0;
            extra_accepted = 0;
            while (!extra_accepted && segment_ready !== 1'b1 && cycles < 1000) begin
                @(posedge clk);
                if (feature_ready === 1'b1) extra_accepted = 1;
                cycles = cycles + 1;
            end
            @(negedge clk);
            feature_valid = 0;
            segment_end = 0;
            if (!extra_accepted && segment_ready !== 1'b1)
                $fatal(1, "overlength segment neither consumed overflow feature nor returned to idle");
            wait_segment_ready();
            if (train_done || template_mask !== old_mask)
                $fatal(1, "overlength enrollment changed template state");
            if (abort_count !== old_aborts + 1)
                $fatal(1, "overlength segment did not increment abort_count exactly once");
        end
    endtask

    initial begin
        for (integer c = 1; c <= 3; c = c + 1) begin
            gold_len[c] = 0;
            gold_valid[c] = 0;
        end
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        if (template_mask !== 3'b000 || reject_count !== 0 || abort_count !== 0)
            $fatal(1, "reset did not clear visible controls");

        // Before all three labels exist, inference must never emit a command.
        make_sequence(1, 6, 0);
        submit_stimulus(2'b00, stimulus_len);
        check_no_command(100);
        wait_segment_ready();

        train_sequence(1, 8, 3'b001);
        train_sequence(2, 8, 3'b011); // Same feature set as class 1, in reverse order.
        train_sequence(3, 10, 3'b111);

        // MIN_FRAMES itself is legal; the later 3-frame case must reject.
        train_sequence(3, 4, 3'b111);
        make_sequence(3, 4, 0);
        infer_and_check(1, 0);
        train_sequence(3, 10, 3'b111);

        make_sequence(1, 8, 0);
        infer_and_check(1, 8); // Exact match, command held under backpressure.
        make_sequence(2, 8, 0);
        infer_and_check(1, 0); // Reversed temporal pattern must map to class 2.

        make_stretched_sequence(1, 8);
        infer_and_check(1, 0); // Each template frame is repeated twice; full-end DTW must align.
        make_sequence(2, 8, 1);
        infer_and_check(1, 0); // Small feature perturbation remains within the score threshold.

        make_unknown_sequence(8);
        infer_and_check(0, 0); // Far from every class: reject by absolute score.

        // Make class 2 identical to class 1. A zero-score tie must fail the margin test.
        make_sequence(1, 8, 0);
        submit_stimulus(2'd2, stimulus_len);
        wait_train_done();
        remember_template(2, stimulus_len);
        if (template_mask !== 3'b111) $fatal(1, "retraining cleared a template bit");
        make_sequence(1, 8, 0);
        infer_and_check(0, 0);

        // Restore class 2, then prove abort and too-short enrollment preserve old templates.
        train_sequence(2, 8, 3'b111);
        abort_training_segment(1);
        invalid_short_training();
        make_sequence(1, 8, 0);
        infer_and_check(1, 0);

        // Exact upper boundary is legal and fully comparable against the 2-D oracle.
        train_sequence(3, MAX_FRAMES, 3'b111);
        make_sequence(3, MAX_FRAMES, 0);
        infer_and_check(1, 0);
        overlength_training();
        make_sequence(3, MAX_FRAMES, 0);
        infer_and_check(1, 0); // Overflow attempt must have left the prior template intact.

        // Reset clears templates, command state, and counters even after long-sequence use.
        @(negedge clk);
        rst_n = 0;
        command_ready = 0;
        feature_valid = 0;
        segment_start = 0;
        segment_end = 0;
        segment_abort = 0;
        repeat (4) @(negedge clk);
        if (template_mask !== 3'b000 || command_valid || result_valid || train_done ||
            reject_count !== 0 || abort_count !== 0)
            $fatal(1, "reset did not clear template/result/counter state");
        rst_n = 1;
        repeat (2) @(negedge clk);
        make_sequence(1, 8, 0);
        submit_stimulus(2'b00, stimulus_len);
        check_no_command(100);
        wait_segment_ready();

        $display("PASS tb_dtw_compat speech DTW: independent full-matrix scores, reversed order, time warp, perturbation, unknown rejection, tie margin, training/min/max/overflow/abort/reset, and command backpressure");
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "speech DTW test timeout");
    end
endmodule
