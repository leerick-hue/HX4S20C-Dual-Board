`timescale 1ns/1ps
// Hold physical KEY4 during physical KEY1 reset to suppress HDMI audio packets.
// Normal KEY4 presses after reset keep their original album/control behavior.
module hdmi_audio_diagnostic(
 input ref_clk,pixel_clk,rst_n,pixel_reset,key4_n,output muted
);
 reg boot_mute=1'b0;
 always @(posedge ref_clk)if(!rst_n)boot_mute<=!key4_n;
 (* ASYNC_REG="TRUE" *)reg[1:0]mute_pipe;
 always @(posedge pixel_clk or posedge pixel_reset)
  if(pixel_reset)mute_pipe<=0;else mute_pipe<={mute_pipe[0],boot_mute};
 assign muted=mute_pipe[1];
endmodule
