
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key3,           // B1: control mode
    input                       key2,           // 自动播放 开/关
    input                       ir_in,
    input                       link_rx,        // D14: Board2 UART TX (header depends on PCB revision)

    output                      link_ack_tx, // G11: delivery ACK to Board2
    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
// Native720p60 photo canvas; centered actual640x480 video window.
localparam HD_WIDTH=1280,HD_HEIGHT=720,HD_FPS=60;
localparam HD_HSA=40,HD_HFP=110,HD_HBP=220,HD_VSA=5,HD_VFP=5,HD_VBP=20;
localparam HD_HTOTAL=1650,HD_VTOTAL=750,HD_VIC=4;
localparam [20:0] FRAME_PIXELS=HD_WIDTH*HD_HEIGHT;
localparam [20:0] FRAME_WORDS=FRAME_PIXELS/2;
parameter [20:0] BUF0_ADDR     = 21'd0;
parameter [20:0] BUF1_ADDR     = FRAME_WORDS;

wire rst_all;
wire audio_pll_lock;
wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire decode_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire fx_hs,fx_vs,fx_de,fx_rst_n;
wire[9:0]pixel_x,pixel_y;wire video_pll_lock;
reg vs_previous,de_previous;
wire fx_blank=vs_previous && !vs; // positive-VS trailing edge, before back porch
wire [3:0] brightness,contrast,volume_level;
wire [2:0] edit_mode;
wire bars_enable,music_play,want_video,media_rst;
wire bist_mode;
(* ASYNC_REG="TRUE" *)reg[1:0] bist_decode_mode,bist_reference_mode;
(* ASYNC_REG="TRUE" *)reg [1:0] mode_pref_sync,active_mode_sync;
wire axis_s_valid,axis_s_ready;
wire media_decode_rst_n,media_video_rst_n,media_sd_rst_n,media_mem_rst_n;
wire media_decode_rst=!media_decode_rst_n,media_video_rst=!media_video_rst_n;
wire media_sd_rst=!media_sd_rst_n,media_mem_rst=!media_mem_rst_n;
// Assert all media domains together; release reset only on local clock edges.
// In particular the JPEG synchronous reset/CE must not be driven by a25MHz counter.
reset_sync decode_media_reset(.clk(decode_clk),.arst_n(!media_rst),.rst_n(media_decode_rst_n));
reset_sync video_media_reset(.clk(video_clk),.arst_n(!media_rst),.rst_n(media_video_rst_n));
reset_sync sd_media_reset(.clk(sd_card_clk),.arst_n(!media_rst),.rst_n(media_sd_rst_n));
reset_sync mem_media_reset(.clk(ext_mem_clk),.arst_n(!media_rst),.rst_n(media_mem_rst_n));
wire catalog_ready,active_video,video_present,photo_present;
wire merged_req;wire [31:0] merged_addr;
// Source changes assert media_rst on all producer/FIFO/swap domains, clearing
// display_valid. These lengths settle before the new source's first request;
// they cannot change while a valid old-mode framebuffer remains displayed.
wire [20:0] source_words=(active_video && !bist_decode_mode[1])?21'd153600:FRAME_WORDS;
wire [20:0] display_words=(active_mode_sync[1] && !bist_mode)?21'd153600:FRAME_WORDS;
always @(posedge decode_clk or posedge media_decode_rst)
 if(media_decode_rst)mode_pref_sync<=0;else mode_pref_sync<={mode_pref_sync[0],want_video};
always @(posedge video_clk or posedge media_video_rst)
 if(media_video_rst)active_mode_sync<=0;else active_mode_sync<={active_mode_sync[0],active_video};
media_mode_reset mode_restart(.clk(video_clk),.rst(rst_all),.want_video(want_video),.media_rst(media_rst));
wire sd_initialized,audio_playing;wire media_ready,audio_present;
wire [31:0] audio_start,audio_frames;wire [31:0] audio_underruns,playhead_samples;
wire [31:0] video_frame_number,video_total_frames,video_late_frames,video_dropped_frames;
wire [3:0] player_error;
wire playback_started;
wire player_byte_valid,player_end,bridge_overflow;
wire [7:0] player_byte;
(* ASYNC_REG="TRUE" *) reg [1:0] player_play;
always @(posedge decode_clk or posedge media_decode_rst)begin
 if(media_decode_rst)begin player_play<=0;end
 else player_play<={player_play[0],music_play};
end

wire photo_req,audio_req,card_req;
wire [31:0] photo_addr,audio_addr,card_addr;
wire [7:0] photo_byte,audio_byte,card_byte;
wire photo_byte_valid,photo_end,audio_byte_valid,audio_end,card_byte_valid,card_end;
(* ASYNC_REG="TRUE" *) reg [1:0] audio_present_sync;
(* ASYNC_REG="TRUE" *) reg [1:0] audio_present_sd_sync;
always @(posedge sd_card_clk or posedge media_sd_rst)
 if(media_sd_rst)audio_present_sd_sync<=0;
 else audio_present_sd_sync<={audio_present_sd_sync[0],audio_present};
always @(posedge video_clk or posedge rst_all)
 if(rst_all) audio_present_sync<=0;else audio_present_sync<={audio_present_sync[0],audio_present};
wire [5:0] fade_gain;
wire swap_valid,swap_ready,swap_done,swap_bank,display_bank,fx_valid,switched;
wire transition_busy,read_safe,write_ready;
wire[20:0]write_pixel_addr,packed_addr;wire packed_valid,packed_ready,video_word_read,video_fifo_empty;
wire[31:0]packed_data,video_underruns;wire[23:0]unpacked_rgb;
wire [6:0] wave_addr;wire signed [7:0] wave_sample;wire wave_valid;
wire board_read_req;

wire hdmi_rst,hdmi_video_locked,hdmi_audio_muted;
// PCM queue gives the core's FIFO-empty-gated ACR request a service window.
wire service_pcm_valid,service_acr_valid,service_wait,service_packet_seen;
wire[23:0]service_left,service_right;wire[19:0]service_n,service_cts;
wire[15:0]service_overflow;wire[7:0]service_queued;
reg service_seen;
(* ASYNC_REG="TRUE" *)reg[3:0]service_meta,service_sync;
always @(posedge video_clk or posedge hdmi_rst)
 if(hdmi_rst)service_seen<=0;else if(service_packet_seen)service_seen<=1;
always @(posedge clk or negedge rst_n)
 if(!rst_n)begin service_meta<=0;service_sync<=0;end
 else begin service_meta<={hdmi_video_locked,service_seen,service_wait,service_overflow!=0};service_sync<=service_meta;end

hdmi_audio_diagnostic diag_audio(.ref_clk(clk),.pixel_clk(video_clk),.rst_n(rst_n),.pixel_reset(hdmi_rst),.key4_n(key2),.muted(hdmi_audio_muted));
wire quiet_ref,quiet_pixel;
hdmi_background_quiet quiet_control(.ref_clk(clk),.pixel_clk(video_clk),.rst_n(rst_n),
 .pixel_reset(hdmi_rst),.pattern_key_n(key1),.quiet_key_n(key3),
 .quiet_ref(quiet_ref),.quiet_pixel(quiet_pixel));
wire [23:0] diagnostic_code;
wire pixel_probe_ref,pixel_probe_on,probe_hs,probe_vs,probe_de;
wire [23:0] probe_rgb;
wire system_pll_lock;
wire [23:0] bringup_code;
bringup_status status_probe(.clk(clk),.rst_n(rst_n),
 .pixel_clk(video_clk),.sd_clk(sd_card_clk),.decode_clk(decode_clk),.mem_clk(ext_mem_clk),
 .system_locked(system_pll_lock),.audio_locked(audio_pll_lock),.video_locked(video_pll_lock),
 .full_reset(rst_all),.media_reset(media_rst),.hdmi_reset(hdmi_rst),.vblank_start(fx_blank),
 .sd_ready(sd_initialized),.catalog_ready(catalog_ready),.sdram_ready(Sdr_init_done),.hdmi_locked(hdmi_video_locked),
 .audio_muted(hdmi_audio_muted),.photo_present(photo_present),.media_ready(media_ready),.display_valid(fx_valid),
 .display_code(bringup_code));
wire video_read_req_ack;
board_frame_request read_launch(.clk(video_clk),.rst(media_video_rst),.vblank_start((fx_blank && fx_valid) || switched),
    .read_req_ack(video_read_req_ack),.read_req(board_read_req));
wire        display_valid;

wire [3:0]  state_code;
wire [1:0] album_index_sd;
wire [2:0] album_count_sd;
(* ASYNC_REG="TRUE" *) reg [5:0] album_meta,album_sync;
reg [2:0] album_current_video,album_total_video;
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin
        album_meta<=0;album_sync<=0;album_current_video<=0;album_total_video<=0;
    end else begin
        album_meta<={display_valid,album_count_sd,album_index_sd};
        album_sync<=album_meta;
        if(fx_blank) begin
            album_total_video<=album_sync[4:2];
            album_current_video<=album_sync[5] ? {1'b0,album_sync[1:0]}+3'd1 : 3'd0;
        end
    end
end
wire [11:0] sd_debug;
wire remote_next,remote_auto_valid,remote_auto_enable,remote_album_ready;
wire ir_ctl_valid,ir_ctl_ready,auto_state,ir_seen,remote_ready_gated;
wire photo_next_cmd,photo_auto_valid_cmd,photo_auto_enable_cmd;
wire[7:0]ir_ctl_id;wire[31:0]ir_last,ir_errors,ir_drops;
wire uart_ctl_valid,uart_ctl_ready,ctl_valid,ctl_ready;wire[3:0]uart_ctl_code;wire[7:0]ctl_id;
ir_media_bridge #(.VIDEO_CLK_HZ(74250000)) infrared(.video_clk(video_clk),.video_rst_n(fx_rst_n && media_video_rst_n),.sd_clk(decode_clk),.sd_rst_n(media_decode_rst_n),.ir_in(ir_in),.video_mode(active_mode_sync[1]),
 .album_ready(remote_album_ready),.auto_enabled(auto_state),.legacy_next(remote_next),.legacy_auto_valid(remote_auto_valid),.legacy_auto_enable(remote_auto_enable),.legacy_ready(remote_ready_gated),
 .photo_next(photo_next_cmd),.photo_auto_valid(photo_auto_valid_cmd),.photo_auto_enable(photo_auto_enable_cmd),
 .control_valid(ir_ctl_valid),.control_ready(ir_ctl_ready),.control_id(ir_ctl_id),.last_code(ir_last),.error_count(ir_errors),.dropped_count(ir_drops),.seen(ir_seen));
wire [31:0] remote_accepted,remote_duplicates,remote_unsupported,remote_errors;
wire [7:0] remote_bytes,remote_packets;
wire ack_valid,ack_ready,ack_byte_valid,ack_byte_ready;
wire [31:0] ack_data;wire [7:0] ack_sequence,ack_byte;
board_remote_control #(.CLK_HZ(40000000),.ACK_ENABLE(1)) remote(.clk(decode_clk),.rst_n(media_decode_rst_n),.link_rx(link_rx),
    .album_ready(remote_ready_gated),.control_valid(uart_ctl_valid),.control_ready(uart_ctl_ready),.control_code(uart_ctl_code),.next_pulse(remote_next),
    .auto_valid(remote_auto_valid),.auto_enable(remote_auto_enable),
    .accepted_count(remote_accepted),.duplicate_count(remote_duplicates),
    .unsupported_count(remote_unsupported),.packet_error_count(remote_errors),
    .received_byte_count(remote_bytes),.valid_packet_count(remote_packets),
    .ack_valid(ack_valid),.ack_ready(ack_ready),.ack_data(ack_data),.ack_sequence(ack_sequence));
event_packet_tx #(.USE_EVENT_SEQUENCE(1)) acknowledgements(.clk(decode_clk),.rst_n(media_decode_rst_n),
    .event_valid(ack_valid),.event_ready(ack_ready),.event_data(ack_data),.event_sequence(ack_sequence),
    .byte_valid(ack_byte_valid),.byte_ready(ack_byte_ready),.byte_data(ack_byte));
uart_tx #(.CLK_HZ(40000000),.BAUD(115200)) acknowledgement_wire(.clk(decode_clk),.rst_n(media_decode_rst_n),
    .byte_valid(ack_byte_valid),.byte_ready(ack_byte_ready),.byte_data(ack_byte),.tx(link_ack_tx),.busy());
media_control_arbiter commands(.sd_clk(decode_clk),.sd_rst_n(media_decode_rst_n),.video_mode(active_video),.uart_valid(uart_ctl_valid),.uart_ready(uart_ctl_ready),.uart_code(uart_ctl_code),
 .video_clk(video_clk),.video_rst_n(fx_rst_n && media_video_rst_n),.ir_valid(ir_ctl_valid),.ir_ready(ir_ctl_ready),.ir_id(ir_ctl_id),
 .control_valid(ctl_valid),.control_ready(ctl_ready),.control_id(ctl_id));
wire [6:0] seg_debug0,seg_debug1,seg_debug2,seg_debug3;
reg [3:0] video_debug;
reg stream_stalled;
(* ASYNC_REG="TRUE" *) reg[1:0]video_diag_meta,video_diag_sync;
(* ASYNC_REG="TRUE" *) reg[22:0]seg_snapshot_meta,seg_snapshot_sync;
// These buses carry only the human-readable diagnostics, not control events.
always @(posedge clk or posedge rst_all) begin
 if(rst_all)begin seg_snapshot_meta<=0;seg_snapshot_sync<=0;end
 else begin seg_snapshot_meta<={sd_debug,video_debug,edit_mode,state_code};seg_snapshot_sync<=seg_snapshot_meta;end
end
always @(posedge video_clk or posedge rst_all) begin
 if(rst_all)begin video_debug<=0;video_diag_meta<=0;video_diag_sync<=0;stream_stalled<=0;end
 else begin
  video_diag_meta<={Sdr_init_done,swap_ready};video_diag_sync<=video_diag_meta;
  if(axis_s_valid && !axis_s_ready && fx_valid)stream_stalled<=1;
  if(fx_blank)video_debug<={2'b00,hdmi_audio_muted,hdmi_video_locked};
 end
end
seg_decoder dbg0(.bin_data(diagnostic_code[23:20]),.seg_data(seg_debug0));
seg_decoder dbg1(.bin_data(diagnostic_code[19:16]),.seg_data(seg_debug1));
seg_decoder dbg2(.bin_data(diagnostic_code[15:12]),.seg_data(seg_debug2));
seg_decoder dbg3(.bin_data(diagnostic_code[11:8]),.seg_data(seg_debug3));
wire [6:0]  seg_data_0;
wire [6:0] seg_mode;


wire        video_read_req;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关

wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        audio_raw_valid;
wire signed [23:0] audio_raw_left,audio_raw_right;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_last;
wire [23:0] axis_s_data;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

assign bist_mode=hdmi_audio_muted;
wire read_alignment_mem,read_alignment_ref;
boot_read_alignment read_alignment(.ref_clk(clk),.mem_clk(ext_mem_clk),.rst_n(rst_n),
 .mem_reset(media_mem_rst),.key3_n(key3),.enabled_mem(read_alignment_mem),.selected_ref(read_alignment_ref));
always @(posedge decode_clk or negedge media_decode_rst_n)
 if(!media_decode_rst_n)bist_decode_mode<=0;else bist_decode_mode<={bist_decode_mode[0],bist_mode};
always @(posedge clk or negedge rst_n)
 if(!rst_n)bist_reference_mode<=0;else bist_reference_mode<={bist_reference_mode[0],bist_mode};
wire [15:0] bist_status;
(* ASYNC_REG="TRUE" *)reg [15:0] bist_diag_meta,bist_diag_sync;
always @(posedge clk or negedge rst_n)
 if(!rst_n)begin bist_diag_meta<=0;bist_diag_sync<=0;end
 else begin bist_diag_meta<=bist_status;bist_diag_sync<=bist_diag_meta;end
wire[23:0]legacy_diagnostic_code;
wire[23:0]photo_probe_display;wire[4:0]photo_probe_page;wire photo_probe_next;
// KEY1 is restored to album navigation; hold the observer on its default page.
assign photo_probe_next=1'b0;


assign diagnostic_code=(quiet_ref || pixel_probe_ref || bist_reference_mode[1])?legacy_diagnostic_code:photo_probe_display;
assign legacy_diagnostic_code=quiet_ref?{4'hf,bringup_code[19:0]}:pixel_probe_ref?{4'he,bringup_code[19:0]}:
 (bist_reference_mode[1]?{(read_alignment_ref?4'ha:4'hb),bringup_code[19:16],bist_diag_sync}:bringup_code);
wire photo_write_req,photo_swap_valid,photo_swap_bank,photo_packed_valid,photo_pixel_ready;
wire [1:0]photo_write_buf_idx;
wire [20:0]photo_packed_addr,bist_word_addr;
wire [31:0]photo_packed_data,bist_word_data;
wire bist_write_req,bist_word_valid,bist_swap_valid;
assign sd_card_write_req=bist_decode_mode[1]?bist_write_req:photo_write_req;
assign write_buf_idx=bist_decode_mode[1]?2'd0:photo_write_buf_idx;
assign packed_valid=bist_decode_mode[1]?bist_word_valid:photo_packed_valid;
assign packed_addr=bist_decode_mode[1]?bist_word_addr:photo_packed_addr;
assign packed_data=bist_decode_mode[1]?bist_word_data:photo_packed_data;
assign swap_valid=bist_decode_mode[1]?bist_swap_valid:photo_swap_valid;
assign swap_bank=bist_decode_mode[1]?1'b0:photo_swap_bank;
assign write_ready=photo_pixel_ready && !bist_decode_mode[1];
framebuffer_bist memory_check(.decode_clk(decode_clk),.decode_rst_n(media_decode_rst_n),
 .pixel_clk(video_clk),.pixel_rst_n(media_video_rst_n),.enable(bist_mode),
 .write_req(bist_write_req),.write_ack(sd_card_write_req_ack),
 .word_valid(bist_word_valid),.word_ready(packed_ready && bist_decode_mode[1]),.word_addr(bist_word_addr),.word_data(bist_word_data),
 .write_finish_toggle(frame_write_toggle_mem),.swap_valid(bist_swap_valid),.swap_ready(swap_ready),.swap_done(swap_done),
 .read_req(board_read_req),.word_read(video_word_read),.word_empty(video_fifo_empty),.read_data(video_read_data),.status(bist_status));

// Pause media transactions in the F diagnostic mode, without stopping PLLs.
// HDMI timing/probe/adapter/core/PHY use hdmi_rst and continue independently.
assign rst_all = ~rst_n | ~audio_pll_lock | ~video_pll_lock | quiet_ref;
seg_decoder mode_decoder(.bin_data(diagnostic_code[7:4]),.seg_data(seg_mode));
reset_sync fx_reset(.clk(video_clk),.arst_n(!rst_all),.rst_n(fx_rst_n));
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin vs_previous<=1;de_previous<=0;end
    else begin
        vs_previous<=vs;de_previous<=de;
        

    end
end
video_canvas_coords #(.WIDTH(HD_WIDTH),.HEIGHT(HD_HEIGHT),.VS_POLARITY(1)) canvas(.clk(video_clk),.rst(rst_all),.de(de),.vs(vs),.x(pixel_x),.y(pixel_y));
board_video_controls #(.KEY_CYCLES(1485000)) controls(.clk(video_clk),.rst_n(fx_rst_n),.vblank_start(fx_blank),
    .key_n({key3,key2,key1}),.command_valid(ctl_valid),.command_id(ctl_id),.command_ready(ctl_ready),.brightness(brightness),.contrast(contrast),
    .edit_mode(edit_mode),.volume_level(volume_level),.bars_enable(bars_enable),.music_play(music_play));
// This release prioritizes native HD photos and keeps the proven photo controls.
assign want_video=1'b0;
frame_swap_fx_cdc swap(.sys_clk(decode_clk),.sys_rst_n(media_decode_rst_n),
    .request_valid(swap_valid),.request_bank(swap_bank),.request_ready(swap_ready),.request_done(swap_done),
    .pixel_clk(video_clk),.pixel_rst_n(media_video_rst_n),.vblank_start(fx_blank),
    .pixel_safe_to_swap(read_safe),.fade_enable(!active_mode_sync[1] && !bist_mode),.display_bank(display_bank),
    .display_valid(fx_valid),.switched(switched),.fade_gain(fade_gain),.transition_busy(transition_busy));
  audio_bar_capture waveform(.audio_clk(video_clk),.audio_rst_n(fx_rst_n),
    .pcm_left(audio_left_data),.pcm_right(audio_right_data),.pcm_valid(audio_valid),.pixel_clk(video_clk),.pixel_rst_n(fx_rst_n),
    .vblank_start(fx_blank),.wave_addr(wave_addr),.wave_sample(wave_sample),.wave_valid(wave_valid));
  video_effects_hd #(.FRAMES_PER_SECOND(HD_FPS),.SHOW_VOLUME(1),.AUDIO_BARS(1),.TF_AUDIO(1),.SHOW_IR(1)) effects(.pixel_clk(video_clk),.rst_n(fx_rst_n),.vblank_start(fx_blank),
    .in_x(pixel_x),.in_y(pixel_y),.in_rgb(fx_valid?vout_data_raw:24'd0),.in_hs(hs),.in_vs(vs),.in_de(de),
    .fade_gain(fade_gain),.brightness(brightness),.contrast(contrast),
    .volume_level(volume_level),
    .video_mode(active_mode_sync[1] && !bist_mode),.album_current(album_current_video),.album_total(album_total_video),
    .ir_code(ir_last),.ir_seen(ir_seen),.control_mode(edit_mode),.music_play(music_play),.music_present(audio_present_sync[1]),
    .osd_enable(1'b1),.wave_enable(bars_enable),
    .wave_addr(wave_addr),.wave_sample(wave_sample),.wave_valid(wave_valid),
    .out_rgb(vout_data),.out_hs(fx_hs),.out_vs(fx_vs),.out_de(fx_de));


// TF、SDRAM 与 video 时钟分域管理。
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .clk3_out   (decode_clk),
    .locked     (system_pll_lock),
    .reset      (1'b0)
);

video_hd_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .locked     (video_pll_lock),
    .reset      (!rst_n)
);


// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (!rst_n),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge media_mem_rst) begin
    if (media_mem_rst)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// Header/decoder and framebuffer writer run at the40 MHz board clock.
// The sector mailbox leaves the proven100 MHz SPI controller untouched.
sd_sector_cdc video_sectors(.client_clk(decode_clk),.sd_clk(sd_card_clk),.rst(media_rst),
 .client_req(merged_req),.client_addr(merged_addr),.client_data(player_byte),
 .client_valid(player_byte_valid),.client_end(player_end),
 .sd_req(photo_req),.sd_addr(photo_addr),.sd_data(photo_byte),
 .sd_valid(photo_byte_valid),.sd_end(photo_end),.overflow(bridge_overflow));
wire [10:0] photo_source_width_debug,photo_source_height_debug;
unified_media_source #(.ENABLE_VIDEO(0)) sources(
 .source_width_debug(photo_source_width_debug),.source_height_debug(photo_source_height_debug),.clk(decode_clk),.rst(media_decode_rst),.sd_ready(sd_initialized),.playhead_samples(playhead_samples),
 .want_video(mode_pref_sync[1]),.play_enable(player_play[1]),.key1(key1),.key2(key2),.edit_mode(edit_mode),
 .photo_next_cmd(photo_next_cmd),.photo_auto_valid_cmd(photo_auto_valid_cmd),.photo_auto_enable_cmd(photo_auto_enable_cmd),
 .remote_album_ready(remote_album_ready),.auto_state(auto_state),
 .merged_req(merged_req),.merged_addr(merged_addr),.player_byte(player_byte),.player_byte_valid(player_byte_valid),.player_end(player_end),.bridge_overflow(bridge_overflow),
 .catalog_ready(catalog_ready),.active_video(active_video),.video_present(video_present),.photo_present(photo_present),
 .media_ready(media_ready),.audio_present(audio_present),.audio_start(audio_start),.audio_frames(audio_frames),
 .playback_started(playback_started),.video_frame_number(video_frame_number),.video_total_frames(video_total_frames),.video_late_frames(video_late_frames),.video_dropped_frames(video_dropped_frames),
 .state_code(state_code),.player_error(player_error),.sd_debug(sd_debug),.album_index_sd(album_index_sd),.album_count_sd(album_count_sd),
 .sd_card_write_req(photo_write_req),.sd_card_write_req_ack(sd_card_write_req_ack && !bist_decode_mode[1]),.frame_write_toggle_mem(frame_write_toggle_mem),
 .write_buf_idx(photo_write_buf_idx),.sd_card_write_en(sd_card_write_en),.write_ready(write_ready),.write_pixel_addr(write_pixel_addr),.sd_card_write_data(sd_card_write_data),
 .swap_valid(photo_swap_valid),.swap_ready(swap_ready && !bist_decode_mode[1]),.swap_done(swap_done && !bist_decode_mode[1]),.swap_bank(photo_swap_bank));
assign display_valid=fx_valid;

seg_decoder seg_decoder_m0(
    .bin_data          (diagnostic_code[3:0]),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,seg_debug0}),
    .seg_data_1        ({1'b1,seg_debug1}),
    .seg_data_2        ({1'b1,seg_debug2}),
    .seg_data_3        ({1'b1,seg_debug3}),
    .seg_data_4        ({1'b1,seg_mode}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
native_video_timing #(.WIDTH(HD_WIDTH),.HEIGHT(HD_HEIGHT),.HSA(HD_HSA),.HFP(HD_HFP),.HBP(HD_HBP),.VSA(HD_VSA),.VFP(HD_VFP),.VBP(HD_VBP),.HS_POLARITY(1),.VS_POLARITY(1)) video_timing_data_m0(
    .clk               (video_clk),
    .rst               (hdmi_rst),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

wire viewport_mask;
media_viewport viewport(.clk(video_clk),.rst(rst_all),.de(de_0),.vs(vs_0),
 .video_mode(active_mode_sync[1] && !bist_mode),.pixel_mask(viewport_mask));
video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (unpacked_rgb),
    .pixel_mask        (viewport_mask),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

rgb565_pack pack(.clk(decode_clk),.rst(media_decode_rst || sd_card_write_req),.pixel_valid(sd_card_write_en),.pixel_ready(photo_pixel_ready),
 .pixel_addr(write_pixel_addr),.pixel_rgb(sd_card_write_data[31:8]),.word_valid(photo_packed_valid),.word_ready(packed_ready && !bist_decode_mode[1]),.word_addr(photo_packed_addr),.word_data(photo_packed_data));
rgb565_unpack unpack(.clk(video_clk),.rst(media_video_rst),.pixel_read(video_read_en && fx_valid),.word_read(video_word_read),
 .word_data(video_read_data),.word_empty(video_fifo_empty),.pixel_rgb(unpacked_rgb),.underrun_count(video_underruns));
// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
// RGB output is produced by the extension pipeline above.

frame_read_write #(
    .BURST_SIZE        (64),
    .WRITE_V_FLIP     (0),
    .WRITE_ADDR_BITS  (21),
    .FRAME_WIDTH      (HD_WIDTH/2),
    .FRAME_HEIGHT     (HD_HEIGHT)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .read_capture_delay(read_alignment_mem),
    .rst               (media_mem_rst),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (board_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (21'd0),
    .read_addr_3       (21'd0),
    .read_addr_index   ({1'b0,display_bank}),
    .read_len          (display_words),
    .read_en           (video_word_read),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (decode_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (21'd0),
    .write_addr_3      (21'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (source_words),
    .write_en          (packed_valid && packed_ready),
    .write_data        (packed_data),
    .write_pixel_addr(packed_addr),.write_ready(packed_ready),.read_safe(read_safe),.read_fifo_empty(video_fifo_empty)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (media_mem_rst),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== Indexed JPEG video + streaming TF PCM =====================
// One100 MHz SPI controller arbitrates40 MHz JPEG mailboxes and streaming PCM.
sd_card_top card(.clk(sd_card_clk),.rst(media_sd_rst),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .sd_init_done(sd_initialized),.sd_sec_read(card_req),.sd_sec_read_addr(card_addr),
 .sd_sec_read_data(card_byte),.sd_sec_read_data_valid(card_byte_valid),.sd_sec_read_end(card_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
 .sd_sec_write_data_req(),.sd_sec_write_end());
sd_sector_arbiter sectors(.clk(sd_card_clk),.rst(media_sd_rst),.ready(sd_initialized),
 .photo_req(photo_req),.photo_addr(photo_addr),.photo_data(photo_byte),.photo_valid(photo_byte_valid),.photo_end(photo_end),
 .audio_req(audio_req),.audio_addr(audio_addr),.audio_data(audio_byte),.audio_valid(audio_byte_valid),.audio_end(audio_end),
 .sd_req(card_req),.sd_addr(card_addr),.sd_data(card_byte),.sd_valid(card_byte_valid),.sd_end(card_end));
hxjv_pcm_player tf_music(.sd_clk(sd_card_clk),.video_clk(video_clk),.playhead_clk(decode_clk),.audio_mclk(audio_mclk),.rst(media_rst),
 .sd_ready(sd_initialized),.media_ready(media_ready),.audio_present(audio_present_sd_sync[1]),.audio_start(audio_start),.audio_frames(audio_frames),
 .playback_started(active_video?playback_started:catalog_ready),.play_enable(music_play),.playhead_samples(playhead_samples),
 .sec_req(audio_req),.sec_addr(audio_addr),.sec_data(audio_byte),.sec_valid(audio_byte_valid),.sec_end(audio_end),
 .pcm_valid(audio_raw_valid),.pcm_left(audio_raw_left),.pcm_right(audio_raw_right),
 .underrun_count(audio_underruns),.playing(audio_playing));

// Scale decoded PCM once for HDMI and waveform. ACR keeps the raw sample clock.
audio_volume volume(.clk(video_clk),.rst_n(fx_rst_n),
    .pcm_valid(audio_raw_valid),.pcm_left(audio_raw_left),.pcm_right(audio_raw_right),
    .volume_level(volume_level),.out_valid(audio_valid),
    .out_left(audio_left_data),.out_right(audio_right_data));

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_raw_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
// Physical KEY2 is logical key1/B2; distinct from KEY4's key2/C1 BIST strap.
hdmi_pixel_probe #(.WIDTH(HD_WIDTH)) pixel_probe(
 .ref_clk(clk),.pixel_clk(video_clk),.rst_n(rst_n),.pixel_reset(hdmi_rst),.pattern_key_n(key1),
 .native_hs(hs_0),.native_vs(vs_0),.native_de(de_0),
 .media_hs(fx_hs),.media_vs(fx_vs),.media_de(fx_de),.media_rgb(vout_data),
 .enabled_ref(pixel_probe_ref),.enabled_pixel(pixel_probe_on),
 .out_hs(probe_hs),.out_vs(probe_vs),.out_de(probe_de),.out_rgb(probe_rgb));
video_rgb_to_axis_640x480 #(.WIDTH(HD_WIDTH)) u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (hdmi_rst),
    .I_vs          (probe_vs),
    .I_de          (probe_de),
    .I_rgb         (probe_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// Match the tested HDMI diagnostic startup: sync reset release and100ms EDID.
diag_control #(.EDID_DELAY_CYCLES(7425000)) hdmi_startup(
 .ref_clk(clk),.pixel_clk(video_clk),.rst_n(rst_n),.pll_locked(video_pll_lock),
 .edid_valid(edid_valid),.pixel_rst(hdmi_rst),.edid_trigger(edid_trig),.display_code());

hdmi_acr_pcm_gate audio_service(.clk(video_clk),.rst(hdmi_rst),
 .pcm_valid(audio_valid && hdmi_video_locked && !hdmi_audio_muted && !quiet_pixel),
 .pcm_left(audio_left_data),.pcm_right(audio_right_data),
 .acr_valid(acr_valid && hdmi_video_locked && !hdmi_audio_muted && !quiet_pixel),.acr_n(acr_n),.acr_cts(acr_cts),
 .acr_packet_seen(service_packet_seen),.out_pcm_valid(service_pcm_valid),.out_pcm_left(service_left),.out_pcm_right(service_right),
 .out_acr_valid(service_acr_valid),.out_acr_n(service_n),.out_acr_cts(service_cts),.waiting_acr(service_wait),
 .overflow_count(service_overflow),.queued_samples(service_queued));
hdmi_acr_packet_ack service_ack(.clk(video_clk),.rst(hdmi_rst),
 .c0(tmds_ch0_data),.c1(tmds_ch1_data),.c2(tmds_ch2_data),
 .acr_packet_seen(service_packet_seen));

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( HD_HTOTAL        ),
    .HSA                    ( HD_HSA         ),
    .HFP                    ( HD_HFP         ),
    .HBP                    ( HD_HBP         ),
    .HACTIVE                ( HD_WIDTH        ),
    .VTOTAL                 ( HD_VTOTAL        ),
    .VSA                    ( HD_VSA          ),
    .VFP                    ( HD_VFP         ),
    .VBP                    ( HD_VBP         ),
    .VACTIVE                ( HD_HEIGHT        ),
    .VIDEO_VIC              ( HD_VIC          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 372        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (hdmi_rst),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (service_pcm_valid),
    .I_audio_left_data  (service_left),
    .I_audio_right_data (service_right),
    .I_acr_valid        (service_acr_valid),
    .I_acr_cts          (service_cts),
    .I_acr_n            (service_n),

    .O_video_locked     (hdmi_video_locked),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (hdmi_rst),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

photo_path_observer photo_probe(
 .ref_clk(clk),.ref_rst(!rst_n),.next_page(photo_probe_next),.base_code({4'h9,service_sync,bringup_code[15:0]}),
 .write_clk(decode_clk),.write_rst(media_decode_rst),.write_req(sd_card_write_req),.write_finish_toggle(frame_write_toggle_mem),
 .pixel_accept(sd_card_write_en && photo_pixel_ready),.source_width(photo_source_width_debug),.source_height(photo_source_height_debug),
 .word_accept(photo_packed_valid && packed_ready && !bist_decode_mode[1]),.word_addr(photo_packed_addr),.word_data(photo_packed_data),
 .read_clk(video_clk),.read_rst(media_video_rst),.read_req(board_read_req),.word_read(video_word_read),.word_empty(video_fifo_empty),.read_data(video_read_data),
 .acr_in(acr_valid && hdmi_video_locked && !hdmi_audio_muted),.acr_ack(service_packet_seen),
 .pcm_in(audio_valid && hdmi_video_locked && !hdmi_audio_muted),.pcm_out(service_pcm_valid),.acr_wait(service_wait),.overflow_count(service_overflow),
 .acr_n(acr_n),.acr_cts(acr_cts),.display_code(photo_probe_display),.page(photo_probe_page));

endmodule
