`timescale 1ns/1ps
module ir_media_bridge #(parameter VIDEO_CLK_HZ=25000000)(input video_clk,video_rst_n,sd_clk,sd_rst_n,input ir_in,
 input video_mode,input album_ready,auto_enabled,input legacy_next,legacy_auto_valid,legacy_auto_enable,output legacy_ready,
 output photo_next,photo_auto_valid,photo_auto_enable,
 output control_valid,input control_ready,output[7:0]control_id,
 output[31:0]last_code,error_count,dropped_count,output reg seen);
 wire frame_valid,repeat_frame,cmd_valid,cmd_ready,mail_ready,dst_valid,dst_ready;
 wire[15:0]address;wire[7:0]keycode,cmd,dst_cmd;
 wire photo=cmd==1 || (!video_mode && (cmd==2 || cmd==3 || cmd==20));
 wire fire=dst_valid && dst_ready;
 ir_nec_rx #(.CLK_HZ(VIDEO_CLK_HZ)) receiver(.clk(video_clk),.rst_n(video_rst_n),.ir_in(ir_in),.address(address),.command(keycode),
  .frame_valid(frame_valid),.repeat_frame(repeat_frame),.error_count(error_count));
 ir_keymap #(.CLK_HZ(VIDEO_CLK_HZ)) map(.clk(video_clk),.rst_n(video_rst_n),.frame_valid(frame_valid),.repeat_frame(repeat_frame),
  .address(address),.command(keycode),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_id(cmd),.last_raw_code(last_code),.dropped_count(dropped_count));
 assign cmd_ready=photo?mail_ready:control_ready;
 assign control_valid=cmd_valid && !photo;assign control_id=video_mode?((cmd==2)?8'd17:(cmd==3)?8'd18:(cmd==20)?8'd19:cmd):cmd;
 media_command_cdc mailbox(.src_clk(video_clk),.src_rst_n(video_rst_n),.src_valid(cmd_valid && photo),.src_ready(mail_ready),.src_code(cmd),
  .dst_clk(sd_clk),.dst_rst_n(sd_rst_n),.dst_valid(dst_valid),.dst_ready(dst_ready),.dst_code(dst_cmd));
 assign legacy_ready=album_ready && !dst_valid;
 assign dst_ready=album_ready && !legacy_next && !legacy_auto_valid;
 assign photo_next=legacy_next || (fire && dst_cmd==1);
 assign photo_auto_valid=legacy_auto_valid || (fire && dst_cmd!=1);
 assign photo_auto_enable=legacy_auto_valid?legacy_auto_enable:(dst_cmd==3 || (dst_cmd==20 && !auto_enabled));
 always @(posedge video_clk or negedge video_rst_n)if(!video_rst_n)seen<=0;else if(frame_valid || repeat_frame)seen<=1;
endmodule
