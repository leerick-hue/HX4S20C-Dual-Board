`timescale 1ns/1ps
// Observe the complete design from the board clock, even if media/video reset
// remains asserted. This monitor changes only the six-digit diagnostic display.
module bringup_status #(
 parameter ACTIVITY_BITS=8, WINDOW_BITS=20, HEARTBEAT_BITS=25
)(
 input clk,rst_n,pixel_clk,sd_clk,decode_clk,mem_clk,
 input system_locked,audio_locked,video_locked,
 input full_reset,media_reset,hdmi_reset,vblank_start,
 input sd_ready,catalog_ready,sdram_ready,hdmi_locked,
 input audio_muted,photo_present,media_ready,display_valid,
 output [23:0] display_code
);
 wire [3:0] activity;
 bringup_clock_div #(.BITS(ACTIVITY_BITS)) pixel_activity(.clk(pixel_clk),.rst_n(rst_n),.activity(activity[0]));
 bringup_clock_div #(.BITS(ACTIVITY_BITS)) sd_activity(.clk(sd_clk),.rst_n(rst_n),.activity(activity[1]));
 bringup_clock_div #(.BITS(ACTIVITY_BITS)) decode_activity(.clk(decode_clk),.rst_n(rst_n),.activity(activity[2]));
 bringup_clock_div #(.BITS(ACTIVITY_BITS)) mem_activity(.clk(mem_clk),.rst_n(rst_n),.activity(activity[3]));
 reg blank_seen;
 always @(posedge pixel_clk or negedge rst_n)
  if(!rst_n)blank_seen<=0;else if(vblank_start)blank_seen<=1;

 wire [14:0] raw_flags={system_locked,audio_locked,video_locked,
  full_reset,media_reset,hdmi_reset,blank_seen,
  sd_ready,catalog_ready,sdram_ready,hdmi_locked,
  audio_muted,photo_present,media_ready,display_valid};
 (* ASYNC_REG="TRUE" *)reg [14:0] flags_meta,flags_sync;
 (* ASYNC_REG="TRUE" *)reg [3:0] activity_meta,activity_sync;
 reg [3:0] activity_previous,seen,alive;
 reg [WINDOW_BITS-1:0] window_count;
 reg [HEARTBEAT_BITS-1:0] heartbeat;
 wire [3:0] changed=activity_sync^activity_previous;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   flags_meta<=0;flags_sync<=0;activity_meta<=0;activity_sync<=0;
   activity_previous<=0;seen<=0;alive<=0;window_count<=0;heartbeat<=0;
  end else begin
   flags_meta<=raw_flags;flags_sync<=flags_meta;
   activity_meta<=activity;activity_sync<=activity_meta;
   activity_previous<=activity_sync;
   window_count<=window_count+1'b1;heartbeat<=heartbeat+1'b1;
   if(&window_count)begin alive<=seen|changed;seen<=0;end
   else seen<=seen|changed;
  end
 end
 // d | heartbeat+3 PLL locks | mem/JPEG/SD/pixel clocks | reset/blank |
 // SD/catalog/SDRAM/HDMI ready | mute/photo/media/display.
 assign display_code={4'hd,heartbeat[HEARTBEAT_BITS-1],flags_sync[14:12],
  alive,flags_sync[11:8],flags_sync[7:4],flags_sync[3:0]};
endmodule

module bringup_clock_div #(parameter BITS=8)(input clk,rst_n,output activity);
 reg [BITS-1:0] count;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)count<=0;else count<=count+1'b1;
 assign activity=count[BITS-1];
endmodule
