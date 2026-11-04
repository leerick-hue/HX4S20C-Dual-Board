# HX4S20C: 50 MHz board clock; PLL outputs retain their generated-clock relationships.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
# Only the asynchronous UART input path is exempt, not its internal logic.
set_false_path -from [get_ports {link_rx}]
derive_clocks

rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {jpeg_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[3]}]
rename_clock -name {audio_mclk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

# Pixel and HDMI 5x clocks run together from one PLL; do not mark them exclusive.
# The independent audio PLL crosses into video through the existing synchronizers.
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk jpeg_clk clk]

# Keep the existing conservative 7.7ns Gray-bus flight bound. The write FIFO
# now crosses JPEG 40MHz and memory 50MHz; no SDRAM PHY paths are exempted.
set_max_delay -datapath_only -from [get_regs {frame_read_write_m0/write_buf/wgray[*]}] -to [get_regs {frame_read_write_m0/write_buf/wgray_meta[*]}] 7.7
set_max_delay -datapath_only -from [get_regs {frame_read_write_m0/write_buf/rgray[*]}] -to [get_regs {frame_read_write_m0/write_buf/rgray_meta[*]}] 7.7
# FIFO reset releases through WRS; only its asynchronous source is exempt.
set_false_path -from [get_regs {frame_read_write_m0/frame_fifo_write_m0/fifo_aclr}] -to [get_regs {frame_read_write_m0/write_buf/wrs/pipe[*]}]

# Audio FIFO Gray buses: less than one 100 MHz source clock period.
set_max_delay -datapath_only -from [get_regs {tf_music/fifo/wgray[*]}] -to [get_regs {tf_music/fifo/wg_meta[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {tf_music/fifo/rgray[*]}] -to [get_regs {tf_music/fifo/rg_meta[*]}] 9.5

set_false_path -from [get_ports {ir_in}]

# Handshake payloads remain held until the destination accepts them. A distinct
# destination register captures the byte only after the two-flop request chain.
# Bound the physical bus flight time; retain normal STA for destination decode.

# Only the first asynchronous sampling stage is exempt. Later stages, the
# pending-command decoders, framebuffer data and HDMI paths remain checked.
set_false_path -to [get_regs {swap/ack_sync[0] swap/request_sync[0] swap/bank_sync[0]}]
set_false_path -to [get_regs {frame_read_write_m0/idle_sync[0] read_launch/ack_sync[0]}]
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_req_d0 frame_read_write_m0/frame_fifo_read_m0/read_addr_index_d0[*]}]
# The writer holds its request until ACK through the d0/d1/d2 synchronizer.
# Exempt only its first sampling FF; d1/d2 and the write datapath stay timed.
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_write_m0/write_req_d0}]
set_false_path -to [get_regs {album_meta[*] audio_present_sync[0] tf_music/present_sync[0]}]
# The generated read FIFO asynchronously asserts reset and releases it through
# these two reset synchronizers. Do not exempt its downstream reset tree.
set_false_path -from [get_regs {frame_read_write_m0/frame_fifo_read_m0/fifo_aclr}] -to [get_regs {frame_read_write_m0/read_buf/asy_r_rst0 frame_read_write_m0/read_buf/asy_r_rst1}]

# MJPEG client40 MHz <-> SPI100 MHz mailboxes; payloads stay held until ACK.
set_false_path -to [get_regs {player_play[0] mode_pref_sync[0] active_mode_sync[0] sources/ready_sync[0] sources/video_player/ack_sync[0] sources/video_player/finish_sync[0] sources/album/wrfin_tgl_sync[0] sources/album/bmp_read_m0/ack_sync[0] sources/album/inhibit_sync[0]}]
set_false_path -to [get_regs {video_sectors/req_sync[0] video_sectors/ack_sync[0] video_sectors/byte_sync[0] video_sectors/end_sync[0]}]
set_max_delay -datapath_only -from [get_regs {video_sectors/held_data[*]}] -to [get_regs {video_sectors/client_data[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {sources/merged_addr[*]}] -to [get_regs {video_sectors/sd_addr[*]}] 9.5
# Audio configuration is held after media_ready; only its first readiness FF is exempt.
set_false_path -to [get_regs {tf_music/metadata_sync[0] tf_music/start_sync[0] tf_music/ready_sync[0]}]
set_max_delay -datapath_only -from [get_regs {sources/audio_start[*] sources/audio_frames[*]}] -to [get_regs {tf_music/base_lba[*] tf_music/total_samples[*] tf_music/sec_addr[*]}] 9.5

# The media restart is an asynchronous reset request. Its only destinations
# below are the reset synchronizers themselves; every downstream reset release
# and all data/enable paths remain timed in their local domain.
set_false_path -from [get_regs {mode_restart/hold_count[*] mode_restart/selected controls/want_video}] -to [get_regs {decode_media_reset/pipe[*] video_media_reset/pipe[*] sd_media_reset/pipe[*] mem_media_reset/pipe[*] video_sectors/client_reset/pipe[*] video_sectors/sd_reset/pipe[*] tf_music/sd_reset/pipe[*] tf_music/video_reset/pipe[*] tf_music/head_reset/pipe[*] tf_music/audio_reset/pipe[*] tf_music/fifo/wr_reset/pipe[*] tf_music/fifo/rd_reset/pipe[*]}]
# The write FIFO already uses its own two-domain reset synchronizers.
set_false_path -from [get_regs {mem_media_reset/pipe[2]}] -to [get_regs {frame_read_write_m0/write_buf/wrs/pipe[*] frame_read_write_m0/write_buf/rrs/pipe[*]}]
# The mode holds each frame length before its request and through ACK. These
# are only the first samples; d1 and the request-qualified latched values stay timed.
set_false_path -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_len_d0[*] frame_read_write_m0/frame_fifo_write_m0/write_len_d0[*] audio_present_sd_sync[0]}]
# Both sides of the generated read FIFO already release reset locally.
set_false_path -from [get_regs {mem_media_reset/pipe[2]}] -to [get_regs {frame_read_write_m0/read_buf/asy_r_rst0 frame_read_write_m0/read_buf/asy_r_rst1 frame_read_write_m0/read_buf/asy_w_rst0 frame_read_write_m0/read_buf/asy_w_rst1}]
set_false_path -from [get_regs {mem_media_reset/pipe[2]}] -to [get_regs {frame_read_write_m0/read_reset/pipe[*]}]

# Boot diagnostic flag is held from physical KEY1 release; first sample only.
set_false_path -to [get_regs {diag_audio/mute_pipe[0]}]

# Bringup observer: only first asynchronous sampler stages are exempt.
set_false_path -to [get_regs {status_probe/flags_meta[*] status_probe/activity_meta[*]}]

# BIST boot selection, finish toggle and human-readable status: first stages only.
set_false_path -to [get_regs {memory_check/enable_sync[0] memory_check/finish_sync[0] memory_check/done_sync[0] bist_diag_meta[*]}]

# Boot mode is held; sample into each data/diagnostic clock before use.
set_false_path -to [get_regs {bist_decode_mode[0] bist_reference_mode[0]}]

# Held boot selection: exempt only the first memory-clock sampling stage.
set_false_path -to [get_regs {read_alignment/mode_sync[0]}]

# Fixed pixel probe selection is held after reset; only the first CDC sampler.
set_false_path -to [get_regs {pixel_probe/sync_ff[0]}]

# Quiet boot flag is held after board reset; exempt only its first pixel sampler.
set_false_path -to [get_regs {quiet_control/quiet_sync[0]}]
# This one boot register can change only while physical rst_n is low, which
# already asserts every affected reset. It is held throughout normal operation.
# Do not time a runtime clk->video/audio recovery event that cannot occur.
# HDMI data/enable, synchronizer later stages and all media paths stay timed.
set_false_path -from [get_regs {quiet_control/boot_quiet}]

# Four independent single-bit diagnostic flags; only first synchronizer flops.
set_false_path -to [get_regs {service_meta[*]}]

# Pixel-domain reset asserts the serial reset synchronizer asynchronously.
# Only video-clock launches into this dedicated reset pipe are exempt.
# Serial pipe D paths and its serial-domain FF/ODDR recovery checks remain timed.
set_false_path -from [get_clocks video_clk] -to [get_regs {u_hdmi2phy_wrapper/serial_reset_pipe[*]}]

# Diagnostic reports are held for an entire frame/second. Only event first
# samplers are asynchronous; payload capture occurs after two event flops.
set_false_path -to [get_regs {photo_probe/write_bridge/event_sync[0] photo_probe/read_bridge/event_sync[0] photo_probe/audio_bridge/event_sync[0]}]
set_max_delay -datapath_only -from [get_regs {photo_probe/wheld[*]}] -to [get_regs {photo_probe/write_bridge/report[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {photo_probe/rheld[*]}] -to [get_regs {photo_probe/read_bridge/report[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {photo_probe/aheld[*]}] -to [get_regs {photo_probe/audio_bridge/report[*]}] 9.5
set_false_path -to [get_regs {photo_probe/finish_sync[0]}]

# Restored IR/UART control mailboxes: first toggle samplers only. Payloads
# remain held through the handshake and retain a bounded flight time.
set_false_path -to [get_regs {infrared/mailbox/ack_meta infrared/mailbox/req_meta commands/keyboard_mailbox/ack_meta commands/keyboard_mailbox/req_meta}]
set_max_delay -datapath_only -from [get_regs {infrared/mailbox/payload[*]}] -to [get_regs {infrared/mailbox/dst_payload[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {commands/keyboard_mailbox/payload[*]}] -to [get_regs {commands/keyboard_mailbox/dst_payload[*]}] 9.5
# UART serializer launches in the actual 40 MHz decode clock domain.
set_output_delay -clock [get_clocks {jpeg_clk}] 0 [get_ports {link_ack_tx}]
