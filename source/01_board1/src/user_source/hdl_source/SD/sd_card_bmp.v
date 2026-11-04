
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer WIDTH             = 640,
    parameter integer HEIGHT            = 480,
    parameter integer PIXEL_ADDR_BITS   = (64'd1*WIDTH*HEIGHT>64'd524288) ?
        $clog2(64'd1*WIDTH*HEIGHT) : 19
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input remote_next,remote_auto_valid,remote_auto_enable,output remote_ready,
    input key_inhibit, input pixel_ready,
    output [10:0] source_width_debug,source_height_debug,
    output [PIXEL_ADDR_BITS-1:0] write_pixel_addr,
    output swap_valid, input swap_ready, input swap_done,
    output swap_bank,
    output [3:0]                state_code,
    output [11:0] debug_status,
    output [1:0] displayed_image_index,
    output [2:0] detected_image_count,output auto_play_enabled,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    input sd_init_done,input media_ready,
    input [31:0] media_photo_start,input [31:0] media_photo_max,input [2:0] media_photo_count,
    output sd_sec_read,output [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,input sd_sec_read_data_valid,input sd_sec_read_end
);

reg swap_pending,swap_accepted,write_done_seen,load_failed;
reg [1:0] inhibit_sync;
wire parser_done,parser_error;
wire [3:0] parser_error_code;
reg [3:0] last_error;
always @(posedge clk or posedge rst) begin
    if(rst) last_error<=0;
    else if(parser_error) last_error<=parser_error_code;
end
assign swap_valid=swap_pending && !swap_accepted;

always @(posedge clk or posedge rst) begin
    if(rst) inhibit_sync<=0;else inhibit_sync<={inhibit_sync[0],key_inhibit};
end
wire key_next_press;
wire key_auto_press;
wire key_auto_release;

wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
// 轮播间隔档位 0..4 对应 1/2/5/10/30 秒。位宽按最大档 30s 选取，
// 旧实现的 $clog2(CLK_FREQ_HZ) 只能表示到 1.68s（40MHz），加档必须先加宽。
localparam integer AUTO_MAX_S = 30;
localparam [63:0] AUTO_MAX_CYCLES=64'd1*CLK_FREQ_HZ*AUTO_MAX_S;
localparam AUTO_BITS=(AUTO_MAX_CYCLES>1)?$clog2(AUTO_MAX_CYCLES):1;
reg [AUTO_BITS-1:0] auto_cnt;
reg [2:0]        auto_sel;             // 0=1s 1=2s 2=5s 3=10s 4=30s
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              next_req_pending;
reg              load_busy;
// These values describe the committed picture and completed scan, not a
// pending key press or a picture still being written to SDRAM.
assign auto_play_enabled=auto_play_en;
assign displayed_image_index = img_idx;
assign detected_image_count = scan_done ? img_found_count : 3'd0;
assign remote_ready=scan_done && display_valid && !load_busy && !load_failed && !next_req_pending;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

wire [3:0] progress_code = !sd_init_done ? 4'd0 : load_failed ? 4'he :
    !scan_done ? 4'd1 : img_found_count==0 ? 4'd2 :
    first_image_committed && !load_busy ? 4'd6 :
    !source_done_seen ? 4'd3 : !write_done_seen ? 4'd4 : 4'd5;
assign debug_status={1'b0,img_found_count,progress_code,last_error};


// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [1:0] next_from_current;

assign write_en   = bmp_data_wr_en && pixel_ready;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign swap_bank=pending_buf_idx[0];
localparam [AUTO_BITS-1:0] AUTO_LIM_1S =64'd1*CLK_FREQ_HZ-1;
localparam [AUTO_BITS-1:0] AUTO_LIM_2S =64'd2*CLK_FREQ_HZ-1;
localparam [AUTO_BITS-1:0] AUTO_LIM_5S =64'd5*CLK_FREQ_HZ-1;
localparam [AUTO_BITS-1:0] AUTO_LIM_10S=64'd10*CLK_FREQ_HZ-1;
localparam [AUTO_BITS-1:0] AUTO_LIM_30S=64'd30*CLK_FREQ_HZ-1;
reg [AUTO_BITS-1:0] auto_limit;
always @* begin
    case(auto_sel)
        3'd0:    auto_limit = AUTO_LIM_1S;
        3'd1:    auto_limit = AUTO_LIM_2S;
        3'd2:    auto_limit = AUTO_LIM_5S;
        3'd3:    auto_limit = AUTO_LIM_10S;
        default: auto_limit = AUTO_LIM_30S;
    endcase
end
wire [AUTO_BITS-1:0] auto_limit_v = auto_limit[AUTO_BITS-1:0];
assign auto_tick  = (auto_cnt == auto_limit_v);
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk          (clk),
    .rst          (rst),
    .button_in    (key_auto),
    .press_pulse  (key_auto_press),
    .release_pulse(key_auto_release)
);

// KEY2（轮播键）短按=开关轮播，长按 >=1.2s=切换轮播间隔档位。
// 开关动作因此从“按下”改为“松开且未触发长按”，长按只切档不再翻转开关。
localparam integer HOLD_MS = 1200;
localparam [31:0] HOLD_CYCLES = (64'd1*CLK_FREQ_HZ/1000)*HOLD_MS;
reg [31:0] hold_cnt;
reg        hold_busy,hold_long;
// Combinational decisions are consumed on the same edge by the scheduler:
// a period change or pause must suppress an already-due automatic load.
wire hold_due=hold_cnt>=HOLD_CYCLES-32'd1;
wire auto_step_pulse=hold_busy && !hold_long && !inhibit_sync[1] && hold_due;
wire auto_toggle_pulse=key_auto_release && hold_busy && !hold_long &&
                       !inhibit_sync[1] && !hold_due;
wire remote_auto_set=(remote_auto_valid===1'b1) && scan_done;
wire local_auto_toggle=auto_toggle_pulse && scan_done && (img_found_count>3'd1);
wire auto_control_change=remote_auto_set || local_auto_toggle || auto_step_pulse;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        hold_cnt<=32'd0;hold_busy<=1'b0;hold_long<=1'b0;
        auto_sel<=3'd0;
    end else begin
        // Cancel the entire gesture if another control mode becomes active.
        // Returning to album mode while still held cannot re-arm it.
        if(inhibit_sync[1]) begin
            hold_busy<=1'b0;hold_long<=1'b0;hold_cnt<=32'd0;
        end else if(key_auto_press) begin
            hold_busy<=1'b1;hold_long<=1'b0;hold_cnt<=32'd0;
        end else if(hold_busy) begin
            if(auto_step_pulse) begin
                hold_long<=1'b1;
                auto_sel<=(auto_sel>=3'd4)?3'd0:(auto_sel+3'd1);
            end else if(!hold_long && !key_auto_release) begin
                hold_cnt<=hold_cnt+32'd1;
            end
            // hold_due wins over release, so the threshold edge only steps.
            if(key_auto_release) hold_busy<=1'b0;
        end
    end
end

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        swap_pending<=0;swap_accepted<=0;write_done_seen<=0;load_failed<=0;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            swap_pending<=0;swap_accepted<=0;write_done_seen<=0;load_failed<=0;
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            if(load_busy && parser_done) source_done_seen<=1;
            if(load_busy && write_finish_pulse) write_done_seen<=1;
            if(load_busy && parser_error) begin load_failed<=1; load_busy<=0; end
            if(load_busy && source_done_seen && write_done_seen) swap_pending<=1;
            if(swap_valid && swap_ready) swap_accepted<=1;
            if(swap_pending && swap_done) begin
                swap_pending<=0; swap_accepted<=0;write_done_seen<=0;
                load_busy<=0; source_done_seen<=0; disp_buf_idx<=pending_buf_idx;
                img_idx<=load_idx; display_valid<=1; first_image_committed<=1;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready && media_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin
                // 忙的时候也只记 1 次“下一张”请求，不会累积成连跳两张
                if (((key_next_press && !inhibit_sync[1]) || remote_next===1'b1) && scan_done && (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;

                // 自动播放开/关（短按 KEY2 松开时触发；长按只切档，不翻转）
                if (local_auto_toggle) begin
                    auto_play_en <= ~auto_play_en;
                end
                // Explicit SET commands are idempotent; they are not toggles.
                if(remote_auto_set) begin
                    auto_play_en<=remote_auto_enable;
                end

                // 自动播放计数：只有当前没有写图任务时才计时。切档时归零，新周期立即生效。
                if(auto_control_change) begin
                    auto_cnt<=0;
                end else if (scan_done && auto_play_en && display_valid && !load_busy && !load_failed && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_done && !first_image_committed && bmp_ready && !load_busy && !load_failed && (img_found_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 手动下一张优先：写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && !load_failed && next_req_pending && (img_found_count != 3'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_done && bmp_ready && display_valid && !load_busy && !load_failed && auto_play_en && auto_tick && !auto_control_change && (img_found_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

bmp_read_scaled #(
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT),
    .KEEP_ASPECT(1),
    .PIXEL_ADDR_BITS(PIXEL_ADDR_BITS)
) bmp_read_m0(
    .source_width_debug(source_width_debug),.source_height_debug(source_height_debug),
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (media_photo_start),
    .scan_max_sector        (media_photo_max),
    .scan_target_count      (media_photo_count),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),
    .bmp_pixel_addr         (write_pixel_addr), .pixel_ready(pixel_ready),
    .load_done(parser_done), .load_error(parser_error), .load_error_code(parser_error_code)
);


endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    output reg  release_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
localparam COUNT_BITS=(DEBOUNCE_CYCLES>1)?$clog2(DEBOUNCE_CYCLES):1;
reg [COUNT_BITS-1:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
        release_pulse <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;
        release_pulse<= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                if (!button_stable && button_sync1)
                    release_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
