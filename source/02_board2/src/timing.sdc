create_clock -name ref_clk -period 20 [get_ports {clk}]
derive_clocks
# Exempt only first CDC sampling stages. Pixel and serial clocks stay related.
set_false_path -to [get_regs {control/pll_sync[0] control/edid_sync[0] lock_sync[0] audio_meta[*] diag_meta[*]}]
set_false_path -to [get_regs {motion/swap/ack_sync[0] motion/swap/request_sync[0] motion/swap/bank_sync[0] motion/id_meta[*]}]
set_false_path -to [get_regs {motion/dma/idle_sync[0] motion/read_launch/ack_sync[0] motion/dma/frame_fifo_read_m0/read_req_d0 motion/dma/frame_fifo_read_m0/read_addr_index_d0[*]}]
# Held frame number is valid before swap request and retained through ACK.
# FIFO Gray crossings keep explicit flight bounds, not broad clock exceptions.
set_max_delay -datapath_only -from [get_regs {motion/dma/write_buf/wgray[*]}] -to [get_regs {motion/dma/write_buf/wgray_meta[*]}] 7.7
set_max_delay -datapath_only -from [get_regs {motion/dma/write_buf/rgray[*]}] -to [get_regs {motion/dma/write_buf/rgray_meta[*]}] 7.7
set_false_path -from [get_regs {motion/dma/frame_fifo_read_m0/fifo_aclr}] -to [get_regs {motion/dma/read_buf/asy_r_rst0 motion/dma/read_buf/asy_r_rst1}]
set_false_path -from [get_regs {memory_reset/pipe[2]}] -to [get_regs {motion/dma/read_reset/pipe[*] motion/dma/read_buf/asy_r_rst0 motion/dma/read_buf/asy_r_rst1}]
# JPEG producer 40MHz, memory 50MHz, SPI 100MHz: handshake first stages only.
set_false_path -to [get_regs {err_meta[*] motion/source/ready_sync[0] motion/source/freeze_sync[0] motion/source/player/ack_sync[0] motion/source/player/finish_sync[0] motion/dma/frame_fifo_write_m0/write_req_d0}]
set_false_path -to [get_regs {motion/source/sectors/req_sync[0] motion/source/sectors/ack_sync[0] motion/source/sectors/byte_sync[0] motion/source/sectors/end_sync[0]}]
set_max_delay -datapath_only -from [get_regs {motion/source/sectors/held_data[*]}] -to [get_regs {motion/source/sectors/client_data[*]}] 9.5
set_max_delay -datapath_only -from [get_regs {motion/source/client_addr[*]}] -to [get_regs {motion/source/sectors/sd_addr[*]}] 9.5
set_false_path -from [get_regs {motion/dma/frame_fifo_write_m0/fifo_aclr memory_reset/pipe[2]}] -to [get_regs {motion/dma/write_buf/wrs/pipe[*]}]
set_false_path -from [get_regs {sd_reset/pipe[2] decode_reset/pipe[2]}] -to [get_regs {motion/source/sectors/client_reset/pipe[*] motion/source/sectors/sd_reset/pipe[*]}]

# External asynchronous inputs; all downstream voice and UART logic stays timed.
set_false_path -from [get_ports {mic_sd link_ack_rx keypad_col_n[*] key1 key2 key3}]
set_output_delay -clock ref_clk 0 [get_ports {link_tx debug_tx led_n[*] keypad_row_n[*] mic_sck mic_ws}]
# Pixel-domain assertion is asynchronous at the shared serial reset synchronizer.
# Its final stage and every DDR pad reset remain timed in the serial domain.
set_false_path -from [get_regs {control/rst_sync[*]}] -to [get_regs {phy/serial_reset_pipe[*]}]
