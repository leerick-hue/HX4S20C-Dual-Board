`timescale 1ns/1ps
// Actual memory controller and FIFO path. 720p60 scanout, VGA window, 30Hz swap.
module motion_path(
 input mem_clk,mem_clk_shift,mem_rst,pixel_clk,pixel_rst,
 input hs_native,vs_native,de_native,input freeze,
 output hs,vs,de,output [23:0]rgb,
 output init_done,output display_valid,output [15:0]display_id,
 output [31:0]underruns,output [2:0]writer_state
);
 wire write_req,write_ack,write_finish,word_valid,word_ready,write_bank;
 wire [20:0]word_addr;wire [31:0]word_data;wire [15:0]frame_id;
 wire swap_valid,swap_ready,swap_done,display_bank,switched;
 wire read_safe,read_req,read_ack,word_read,fifo_empty;
 wire [31:0]fifo_data;wire [23:0]pixel_rgb;
 wire mask,read_pixel;
 reg vs_previous;
 wire blank=vs_previous && !vs;
 reg half_rate;
 (* ASYNC_REG="TRUE" *)reg[15:0]id_meta,id_sync;
 reg [15:0]shown_id;
 assign display_id=shown_id;
 always @(posedge pixel_clk or posedge pixel_rst)begin
  if(pixel_rst)begin vs_previous<=1;half_rate<=0;id_meta<=0;id_sync<=0;shown_id<=0;end
  else begin
   vs_previous<=vs;
   if(blank)half_rate<=!half_rate;
   id_meta<=frame_id;id_sync<=id_meta;
   if(switched)shown_id<=id_sync;
  end
 end
 motion_source source(.clk(mem_clk),.rst(mem_rst),.init_done(init_done),
  .write_req(write_req),.write_ack(write_ack),.write_finish(write_finish),
  .word_valid(word_valid),.word_ready(word_ready),.word_addr(word_addr),.word_data(word_data),
  .write_bank(write_bank),.frame_id(frame_id),.swap_valid(swap_valid),
  .swap_ready(swap_ready),.swap_done(swap_done),.state(writer_state));
 media_viewport viewport(.clk(pixel_clk),.rst(pixel_rst),.de(de_native),.vs(vs_native),
  .video_mode(1'b1),.pixel_mask(mask));
 video_delay pipeline(.video_clk(pixel_clk),.rst(pixel_rst),.read_en(read_pixel),
  .read_data(pixel_rgb),.pixel_mask(mask && display_valid),.hs(hs_native),.vs(vs_native),
  .de(de_native),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(rgb));
 rgb565_unpack unpack(.clk(pixel_clk),.rst(pixel_rst),.pixel_read(read_pixel),
  .word_read(word_read),.word_data(fifo_data),.word_empty(fifo_empty),
  .pixel_rgb(pixel_rgb),.underrun_count(underruns));
 frame_swap_fx_cdc swap(.sys_clk(mem_clk),.sys_rst_n(!mem_rst),
  .request_valid(swap_valid),.request_bank(write_bank),.request_ready(swap_ready),
  .request_done(swap_done),.pixel_clk(pixel_clk),.pixel_rst_n(!pixel_rst),
  .vblank_start(blank && half_rate && (!freeze || !display_valid)),
  .pixel_safe_to_swap(read_safe),.fade_enable(1'b0),
  .display_bank(display_bank),.display_valid(display_valid),.switched(switched),
  .fade_gain(),.transition_busy());
 board_frame_request read_launch(.clk(pixel_clk),.rst(pixel_rst),
  .vblank_start((blank && display_valid)||switched),.read_req_ack(read_ack),.read_req(read_req));
 wire init_ref,busy,rd_valid,app_rd,app_wr;
 wire [20:0]rd_addr,wr_addr;wire [31:0]rd_data,wr_data;wire [3:0]dm;
 frame_read_write #(.BURST_SIZE(64),.WRITE_V_FLIP(0),.WRITE_ADDR_BITS(21),
  .FRAME_WIDTH(320),.FRAME_HEIGHT(480)) dma(
  .rst(mem_rst),.mem_clk(mem_clk),.read_capture_delay(1'b1),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(init_ref),.Sdr_busy(busy),
  .App_rd_en(app_rd),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),
  .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
  .read_addr_0(21'd0),.read_addr_1(21'd153600),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index({1'b0,display_bank}),.read_len(21'd153600),
  .read_en(word_read),.read_data(fifo_data),.App_wr_en(app_wr),.App_wr_addr(wr_addr),
  .App_wr_din(wr_data),.App_wr_dm(dm),.write_clk(mem_clk),.write_req(write_req),
  .write_req_ack(write_ack),.write_finish(write_finish),
  .write_addr_0(21'd0),.write_addr_1(21'd153600),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index({1'b0,write_bank}),.write_len(21'd153600),
  .write_en(word_valid),.write_pixel_addr(word_addr),.write_data(word_data),
  .write_ready(word_ready),.read_safe(read_safe),.read_fifo_empty(fifo_empty));
 sdram memory(.Clk(mem_clk),.Clk_sft(mem_clk_shift),.Rst(mem_rst),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(init_ref),.Sdr_busy(busy),
  .App_wr_en(app_wr),.App_wr_addr(wr_addr),.App_wr_dm(dm),.App_wr_din(wr_data),
  .App_rd_en(app_rd),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data));
endmodule
