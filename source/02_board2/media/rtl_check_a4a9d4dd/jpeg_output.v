//-----------------------------------------------------------------
//                      Baseline JPEG Decoder
//                             V0.1
//                       Ultra-Embedded.com
//                        Copyright 2020
//
//                   admin@ultra-embedded.com
//-----------------------------------------------------------------
//                      License: Apache 2.0
// This IP can be freely used in commercial projects, however you may
// want access to unreleased materials such as verification environments,
// or test vectors, as well as changes to the IP for integration purposes.
// If this is the case, contact the above address.
// I am interested to hear how and where this IP is used, so please get
// in touch!
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------

module jpeg_output
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           img_start_i
    ,input           img_end_i
    ,input  [ 15:0]  img_width_i
    ,input  [ 15:0]  img_height_i
    ,input  [  1:0]  img_mode_i
    ,input           inport_valid_i
    ,input  [ 31:0]  inport_data_i
    ,input  [  5:0]  inport_idx_i
    ,input  [ 31:0]  inport_id_i
    ,input           outport_accept_i

    // Outputs
    ,output          inport_accept_o
    ,output          outport_valid_o
    ,output [ 15:0]  outport_width_o
    ,output [ 15:0]  outport_height_o
    ,output [ 15:0]  outport_pixel_x_o
    ,output [ 15:0]  outport_pixel_y_o
    ,output [  7:0]  outport_pixel_r_o
    ,output [  7:0]  outport_pixel_g_o
    ,output [  7:0]  outport_pixel_b_o
    ,output          idle_o
);



localparam BLOCK_Y          = 2'd0;
localparam BLOCK_CB         = 2'd1;
localparam BLOCK_CR         = 2'd2;
localparam BLOCK_EOF        = 2'd3;

localparam JPEG_MONOCHROME  = 2'd0;
localparam JPEG_YCBCR_444   = 2'd1;
localparam JPEG_YCBCR_420   = 2'd2;
localparam JPEG_UNSUPPORTED = 2'd3;

reg valid_r;
wire output_space_w = (!outport_valid_o || outport_accept_i);

//-----------------------------------------------------------------
// FIFO: Y
//-----------------------------------------------------------------
wire               y_valid_w;
wire signed [31:0] y_value_w;
wire               y_pop_w;
wire [31:0]        y_level_w;

jpeg_output_y_ram
u_ram_y
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.flush_i(img_start_i)
    ,.level_o(y_level_w)

    ,.push_i(inport_valid_i && (inport_id_i[31:30] == BLOCK_Y || inport_id_i[31:30] == BLOCK_EOF))
    ,.wr_idx_i(inport_idx_i)
    ,.data_in_i(inport_data_i)

    ,.valid_o(y_valid_w)
    ,.data_out_o(y_value_w)
    ,.pop_i(y_pop_w)
);

//-----------------------------------------------------------------
// FIFO: Cb
//-----------------------------------------------------------------
wire               cb_valid_w;
wire signed [31:0] cb_value_w;
wire               cb_pop_w;
wire [31:0]        cb_level_w;

jpeg_output_cx_ram
u_ram_cb
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.flush_i(img_start_i)
    ,.level_o(cb_level_w)
    ,.mode420_i(img_mode_i == JPEG_YCBCR_420)

    ,.push_i(inport_valid_i && (inport_id_i[31:30] == BLOCK_CB || inport_id_i[31:30] == BLOCK_EOF))
    ,.wr_idx_i(inport_idx_i)
    ,.data_in_i(inport_data_i)

    ,.valid_o(cb_valid_w)
    ,.data_out_o(cb_value_w)
    ,.pop_i(cb_pop_w)
);

//-----------------------------------------------------------------
// FIFO: Cr
//-----------------------------------------------------------------
wire               cr_valid_w;
wire signed [31:0] cr_value_w;
wire               cr_pop_w;
wire [31:0]        cr_level_w;

jpeg_output_cx_ram
u_ram_cr
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.flush_i(img_start_i)
    ,.level_o(cr_level_w)
    ,.mode420_i(img_mode_i == JPEG_YCBCR_420)

    ,.push_i(inport_valid_i && (inport_id_i[31:30] == BLOCK_CR || inport_id_i[31:30] == BLOCK_EOF))
    ,.wr_idx_i(inport_idx_i)
    ,.data_in_i(inport_data_i)

    ,.valid_o(cr_valid_w)
    ,.data_out_o(cr_value_w)
    ,.pop_i(cr_pop_w)
);

//-----------------------------------------------------------------
// FIFO: Info
//-----------------------------------------------------------------
wire        id_valid_w;
wire [31:0] id_value_w;
wire        id_pop_w;

jpeg_output_fifo
#(
     .WIDTH(32)
    ,.DEPTH(8)
    ,.ADDR_W(3)
)
u_info
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.flush_i(img_start_i)
 
    ,.push_i(inport_valid_i && (inport_id_i[31:30] == BLOCK_Y || inport_id_i[31:30] == BLOCK_EOF) && inport_idx_i == 6'd0)
    ,.data_in_i(inport_id_i)
    ,.accept_o()

    ,.valid_o(id_valid_w)
    ,.data_out_o(id_value_w)
    ,.pop_i(id_pop_w)
);

assign inport_accept_o   = (y_level_w <= 32'd384 && cr_level_w <= 32'd128) | idle_o;

//-----------------------------------------------------------------
// Block counter (0 - 63)
//-----------------------------------------------------------------
reg [5:0] idx_q;

always @ (posedge clk_i )
if (rst_i)
    idx_q <= 6'b0;
else if (img_start_i)
    idx_q <= 6'b0;
else if (valid_r && output_space_w)
    idx_q <= idx_q + 6'd1;

//-----------------------------------------------------------------
// Subsampling counter (420 chroma subsampling)
//-----------------------------------------------------------------
reg [1:0] subsmpl_q;

always @ (posedge clk_i )
if (rst_i)
    subsmpl_q <= 2'b0;
else if (img_start_i)
    subsmpl_q <= 2'b0;
else if (valid_r && output_space_w && img_mode_i == JPEG_YCBCR_420 && idx_q == 6'd63)
    subsmpl_q <= subsmpl_q + 2'd1;

//-----------------------------------------------------------------
// YUV -> RGB
//-----------------------------------------------------------------
reg active_q;

always @ (posedge clk_i )
if (rst_i)
    active_q <= 1'b0;
else if (img_start_i)
    active_q <= 1'b0;
else if (!active_q)
begin
    if (img_mode_i == JPEG_MONOCHROME)
        active_q <= (y_level_w >= 32'd64);
    else if (img_mode_i == JPEG_YCBCR_444)
        active_q <= (y_level_w >= 32'd64) && (cb_level_w >= 32'd64) && (cr_level_w >= 32'd64);
    else if (subsmpl_q != 2'b0) // 420
        active_q <= 1'b1;
    else // 420
        active_q <= (y_level_w >= 32'd256) && (cb_level_w >= 32'd256) && (cr_level_w >= 32'd256);
end
else if (valid_r && output_space_w && idx_q == 6'd63)
    active_q <= 1'b0;

always @ * valid_r = active_q;

assign y_pop_w  = output_space_w && active_q;
assign cb_pop_w = output_space_w && active_q;
assign cr_pop_w = output_space_w && active_q;
assign id_pop_w = output_space_w && (idx_q == 6'd63);

//-----------------------------------------------------------------
// Outputs
//-----------------------------------------------------------------
// Four common-CE stages; backpressure freezes coordinates, samples and valid together.
// Products intentionally wrap at 32 bits before the arithmetic right shift, like upstream.
reg v1_q, v2_q, v3_q, valid_q;
reg mono1_q, mono2_q;
reg signed [31:0] y1_q, y2_q;
reg [15:0] x1_q, x2_q, x3_q, pixel_x_q;
reg [15:0] yy1_q, yy2_q, yy3_q, pixel_y_q;
reg signed [31:0] r3_q, g3_q, b3_q;
reg [7:0] pixel_r_q, pixel_g_q, pixel_b_q;
reg signed [31:0] cr1402_p0_q;
reg signed [31:0] cr1402_p1_q;
reg signed [31:0] cr1402_p2_q;
reg signed [31:0] cr1402_q;
reg signed [31:0] cr0714_p0_q;
reg signed [31:0] cr0714_p1_q;
reg signed [31:0] cr0714_p2_q;
reg signed [31:0] cr0714_q;
reg signed [31:0] cb0344_p0_q;
reg signed [31:0] cb0344_p1_q;
reg signed [31:0] cb0344_p2_q;
reg signed [31:0] cb0344_q;
reg signed [31:0] cb1772_p0_q;
reg signed [31:0] cb1772_p1_q;
reg signed [31:0] cb1772_p2_q;
reg signed [31:0] cb1772_q;
wire [15:0] x_start_w = {id_value_w[12:0],3'b0};
wire [15:0] y_start_w = {id_value_w[28:16],3'b0};
always @(posedge clk_i) begin
 if (rst_i || img_start_i) begin
  v1_q<=1'b0; v2_q<=1'b0; v3_q<=1'b0; valid_q<=1'b0;
 end else if (output_space_w) begin
  v1_q<=valid_r && (id_value_w[31:30] != BLOCK_EOF);
  v2_q<=v1_q; v3_q<=v2_q; valid_q<=v3_q;
 end
 if (output_space_w) begin
  x1_q<=x_start_w+{13'b0,idx_q[2:0]}; yy1_q<=y_start_w+{13'b0,idx_q[5:3]};
  x2_q<=x1_q; yy2_q<=yy1_q; x3_q<=x2_q; yy3_q<=yy2_q;
  pixel_x_q<=x3_q; pixel_y_q<=yy3_q;
  mono1_q<=(img_mode_i==JPEG_MONOCHROME); mono2_q<=mono1_q;
  y1_q<=y_value_w; y2_q<=y1_q;
  cr1402_p0_q <= ($signed(cr_value_w) <<< 13) - ($signed(cr_value_w) <<< 11);
  cr1402_p1_q <= - ($signed(cr_value_w) <<< 9) + ($signed(cr_value_w) <<< 7);
  cr1402_p2_q <= - ($signed(cr_value_w) <<< 4) - ($signed(cr_value_w) <<< 0);
  cr1402_q <= cr1402_p0_q + cr1402_p1_q + cr1402_p2_q;
  cr0714_p0_q <= ($signed(cr_value_w) <<< 12) - ($signed(cr_value_w) <<< 10);
  cr0714_p1_q <= - ($signed(cr_value_w) <<< 7) - ($signed(cr_value_w) <<< 4);
  cr0714_p2_q <= - ($signed(cr_value_w) <<< 2) + ($signed(cr_value_w) <<< 0);
  cr0714_q <= cr0714_p0_q + cr0714_p1_q + cr0714_p2_q;
  cb0344_p0_q <= ($signed(cb_value_w) <<< 10) + ($signed(cb_value_w) <<< 9);
  cb0344_p1_q <= - ($signed(cb_value_w) <<< 7) + ($signed(cb_value_w) <<< 1);
  cb0344_p2_q <= 32'sd0;
  cb0344_q <= cb0344_p0_q + cb0344_p1_q + cb0344_p2_q;
  cb1772_p0_q <= ($signed(cb_value_w) <<< 13) - ($signed(cb_value_w) <<< 10);
  cb1772_p1_q <= ($signed(cb_value_w) <<< 7) - ($signed(cb_value_w) <<< 5);
  cb1772_p2_q <= - ($signed(cb_value_w) <<< 3) + ($signed(cb_value_w) <<< 1);
  cb1772_q <= cb1772_p0_q + cb1772_p1_q + cb1772_p2_q;
  r3_q<=32'sd128+y2_q+(mono2_q ? 32'sd0 : (cr1402_q >>> 12));
  g3_q<=32'sd128+y2_q-(mono2_q ? 32'sd0 : (cb0344_q >>> 12))-(mono2_q ? 32'sd0 : (cr0714_q >>> 12));
  b3_q<=32'sd128+y2_q+(mono2_q ? 32'sd0 : (cb1772_q >>> 12));
  pixel_r_q <= (|r3_q[31:8]) ? (r3_q[31:24] ^ 8'hff) : r3_q[7:0];
  pixel_g_q <= (|g3_q[31:8]) ? (g3_q[31:24] ^ 8'hff) : g3_q[7:0];
  pixel_b_q <= (|b3_q[31:8]) ? (b3_q[31:24] ^ 8'hff) : b3_q[7:0];
 end
end
assign outport_valid_o=valid_q;
assign outport_pixel_x_o=pixel_x_q;
assign outport_pixel_y_o=pixel_y_q;
assign outport_width_o=img_width_i;
assign outport_height_o=img_height_i;
assign outport_pixel_r_o=pixel_r_q;
assign outport_pixel_g_o=pixel_g_q;
assign outport_pixel_b_o=pixel_b_q;

//-----------------------------------------------------------------
// Idle
//-----------------------------------------------------------------
reg idle_q;

always @ (posedge clk_i )
if (rst_i)
    idle_q <= 1'b1;
else if (img_start_i)
    idle_q <= 1'b0;
else if (id_valid_w && id_value_w[31:30] == BLOCK_EOF)
    idle_q <= 1'b1;

assign idle_o = idle_q && !(v1_q || v2_q || v3_q || valid_q);


endmodule
