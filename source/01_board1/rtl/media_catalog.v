`timescale 1ns/1ps
// HXAU v1 keeps its first36 bytes; optional HXUV extension points at an
// unchanged relative-LBA HXJV segment. Also accepts old HXAU/raw BMP and HXJV.
module media_catalog(
 input clk,rst,sd_ready,want_video,
 output reg sec_req,output wire [31:0] sec_addr,
 input [7:0] sec_data,input sec_valid,sec_end,
 output reg ready,active_video,video_present,photo_present,
 output reg [31:0] video_base,photo_start,photo_max,
 output reg [2:0] photo_count,
 output reg photo_audio_present,
 output reg [31:0] photo_audio_start,photo_audio_frames,
 output reg [3:0] error_code
);
 localparam BOOT=0,READ=1,CHECK=2,RELEASE=3,DONE=4;
 reg [2:0] state,gap;
 reg [9:0] byte_index;
 reg [31:0] header[0:12];
 wire [32:0] audio_end={1'b0,header[5]}+{8'd0,header[6][31:7]}+(|header[6][6:0]);
 wire [32:0] video_end={1'b0,header[10]}+{1'b0,header[11]};
 integer i;
 assign sec_addr=0;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=BOOT;gap<=0;byte_index<=0;sec_req<=0;ready<=0;active_video<=0;
   video_present<=0;photo_present<=0;video_base<=0;photo_start<=0;photo_max<=131071;
   photo_count<=4;photo_audio_present<=0;photo_audio_start<=0;photo_audio_frames<=0;error_code<=0;
   for(i=0;i<13;i=i+1)header[i]<=0;
  end else case(state)
   BOOT:if(sd_ready)begin sec_req<=1;state<=READ;end
   READ:begin
    if(sec_valid)begin
     // Fixed registers avoid a 13-word read mux feeding a write decoder.
     // This is the same four-byte little-endian shift for each header word.
     for(i=0;i<13;i=i+1)
      if(byte_index<52 && byte_index[5:2]==i)header[i]<={sec_data,header[i][31:8]};
     byte_index<=byte_index+1'b1;
    end
    if(sec_end)begin sec_req<=0;state<=CHECK;end
   end
   CHECK:begin
    state<=RELEASE;gap<=0;
    if(byte_index!=512)error_code<=1;
    else if(header[0]==32'h564a5848 && header[1]==1 && header[2]==512)begin
     video_present<=1;active_video<=1;
    end else if(header[0]==32'h55415848 && header[1]==1)begin
     if(header[7]<=1 || header[8]==0 || header[8]>4)error_code<=2;
     else begin
      photo_present<=1;photo_start<=1;photo_max<=header[7]-1'b1;photo_count<=header[8][2:0];
      if(header[2]==48000 && header[3]==2 && header[4]==16 && header[6]>=128 &&
         header[5]>=header[7] && audio_end<=33'd4194304)begin
       photo_audio_present<=1;photo_audio_start<=header[5];photo_audio_frames<=header[6];
      end
      if(header[9]==32'h56555848)begin // HXUV
       if(header[11]==0 || header[10]<header[7] || video_end!={1'b0,header[12]} ||
          header[12]>4194304 || (header[6]!=0 && audio_end>{1'b0,header[10]}))begin
        error_code<=3;photo_present<=0;photo_audio_present<=0;
       end else begin video_present<=1;video_base<=header[10];active_video<=want_video;end
      end
     end
    end else photo_present<=1; // legacy raw-sector BMP album, no audio header
   end
   // Ensure the old request propagates low through the40/100MHz bridge and
   // arbiter before a different parser is allowed to raise a new request.
   RELEASE:if(gap==7)begin ready<=1;state<=DONE;end else gap<=gap+1'b1;
   default:sec_req<=0;
  endcase
 end
endmodule
