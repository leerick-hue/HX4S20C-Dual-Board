`timescale 1ns/1ps
// Native-pixel RGB pipeline with a logical 640x480 UI canvas.
// Nine registered stages process one new pixel per clock.
// UI control/scroll values are sampled at input+2, fade gain at input+1,
// providing frame-stable UI control and aligned pixel arithmetic.
// wave_sample is a synchronous one-cycle response to the current wave_addr.
module video_effects_hd #(
    parameter integer FRAMES_PER_SECOND=60,
    parameter integer SHOW_VOLUME=0,
    parameter integer AUDIO_BARS=0,parameter integer TF_AUDIO=0,parameter integer SHOW_IR=0
)(
    input wire pixel_clk, input wire rst_n, input wire vblank_start,
    input wire [9:0] in_x, input wire [9:0] in_y,
    input wire [23:0] in_rgb, input wire in_hs, input wire in_vs, input wire in_de,
    input wire [5:0] fade_gain,
    input wire [3:0] brightness, input wire [3:0] contrast,
    input wire [3:0] volume_level,
    input wire video_mode,input wire [2:0] album_current, input wire [2:0] album_total,
    input wire[31:0]ir_code,input wire ir_seen,
    input wire [2:0] control_mode,input wire music_play,input wire music_present,
    input wire osd_enable, input wire wave_enable,
    output wire [6:0] wave_addr, input wire signed [7:0] wave_sample,
    input wire wave_valid,
    output reg [23:0] out_rgb, output reg out_hs, output reg out_vs, output reg out_de
);
    localparam integer LATENCY=9;
    localparam integer FRAME_COUNT_BITS=(FRAMES_PER_SECOND<2)?1:$clog2(FRAMES_PER_SECOND);
    reg [7:0] hs_pipe,vs_pipe,de_pipe;
    reg [9:0] x0,y0,x1,y1,trace0;
    reg valid_wave0;
    reg signed [11:0] centered[0:2],low_pair[0:2],high_pair[0:2],contrast_product[0:2],adjust_sum[0:2];
    reg signed [11:0] boff0,boff1,boff2;
    reg [3:0] c0;
    reg [7:0] clamped[0:2];
    reg [5:0] gain_pipe[0:3];
    (* dsp_style="yes" *) wire [13:0] multiply_r=clamped[0]*gain_pipe[3];
    (* dsp_style="yes" *) wire [13:0] multiply_g=clamped[1]*gain_pipe[3];
    (* dsp_style="yes" *) wire [13:0] multiply_b=clamped[2]*gain_pipe[3];
    reg [13:0] fade_product_r,fade_product_g,fade_product_b;
    reg [23:0] faded6,layer7;
    reg [9:0] flags[2:7];
    reg [9:0] geometry;
    reg [2:0] region_tmp,region2;
    reg [9:0] text_x_tmp;
    reg [3:0] text_y_tmp;
    reg [5:0] index2;
    reg [2:0] column2,row2,column3,row3;
    reg [7:0] title3,ir3,slogan3,bar3,character4;
    reg [2:0] region3,column4,row4;
    wire font_pixel;
    reg font4,font5,font6,font7;
    reg [23:0] base_layer;
    reg [9:0] scroll;
    reg [FRAME_COUNT_BITS-1:0] frame_count;
    reg [3:0] sec0,sec1,min0,min1;
    reg [3:0] u_volume,u_bright,u_contrast,u_sec0,u_sec1,u_min0,u_min1;
    reg [2:0] u_mode,u_current,u_total;
    reg [31:0] u_ir_code;
    reg u_video_mode;reg u_ir_seen,u_music_play,u_music_present;
    wire [9:0] scroll_x=(x1+scroll>=640)?x1+scroll-10'd640:x1+scroll;
    wire wave_panel=osd_enable && wave_enable && !AUDIO_BARS && x1>=60 && x1<580 && y1>=300 && y1<410;
    wire bar_panel=osd_enable && wave_enable && AUDIO_BARS && x1>=60 && x1<580 && y1>=334 && y1<428;
    integer k;
    assign wave_addr=AUDIO_BARS?((in_x>=64 && in_x<576)?(in_x-10'd64)>>4:7'd0)
                              :((in_x>=64 && in_x<576)?(in_x-10'd64)>>2:7'd0);
    font5x7 font(.character(character4),.column(column4),.row(row4),.pixel(font_pixel));
    function [7:0] clamp8;
        input signed [11:0] v;
        begin if(v<0)clamp8=0;else if(v>255)clamp8=255;else clamp8=v[7:0];end
    endfunction
    function [7:0] digit;
        input [3:0] value;
        begin digit=8'd48+{4'd0,value}; end
    endfunction
    function [7:0] source_hint;
        input [5:0] n;begin case(n)
        0:source_hint="K";1:source_hint="2";2:source_hint=":";3:source_hint="V";4:source_hint="I";5:source_hint="D";6:source_hint="E";7:source_hint="O";
        9:source_hint="K";10:source_hint="4";11:source_hint=":";12:source_hint="A";13:source_hint="L";14:source_hint="B";15:source_hint="U";16:source_hint="M";default:source_hint=" ";endcase end
    endfunction
    function [7:0] title_char;
        input [5:0] index;
        begin
        if(u_mode==6 && index>=21) title_char=source_hint(index-21);
        else if(SHOW_VOLUME && index<7) begin
            case(index)
                0:title_char="V";1:title_char="O";2:title_char="L";3:title_char=":";
                4:title_char=digit(u_volume>8 ? 4'd8 : u_volume);
                5:title_char="/";6:title_char="8";
                default:title_char=" ";
            endcase
        end else case(index)
            0:title_char="H"; 1:title_char="X"; 2:title_char="4";
            3:title_char="S"; 4:title_char="2"; 5:title_char="0"; 6:title_char="C";
            9:title_char="T"; 10:title_char="I"; 11:title_char="M"; 12:title_char="E";
            14:title_char=digit(u_min1); 15:title_char=digit(u_min0); 16:title_char=":";
            17:title_char=digit(u_sec1); 18:title_char=digit(u_sec0);
            21:title_char="B"; 22:title_char=":";
            23:title_char=(u_bright<4)?"-":"+";
            24:case(u_bright) 0,8:title_char="1"; default:title_char="0"; endcase
            25:case(u_bright) 0,8:title_char="2"; 1,7:title_char="9";
                2,6:title_char="6"; 3,5:title_char="3"; default:title_char="0"; endcase
            26:case(u_bright) 0,8:title_char="8"; 1,7:title_char="6";
                2,6:title_char="4"; 3,5:title_char="2"; default:title_char="0"; endcase
            29:title_char="C"; 30:title_char=":";
            31:title_char=(u_contrast<4)?"0":((u_contrast<8)?"1":"2");
            32:title_char=".";
            33:case(u_contrast[1:0]) 0:title_char="0"; 1:title_char="2";
                2:title_char="5"; 3:title_char="7"; endcase
            34:title_char=u_contrast[0]?"5":"0";
            35:title_char=u_video_mode?"M":"P";
            36:title_char=u_video_mode?"J":digit({1'b0,u_current});
            37:title_char=u_video_mode?"P":"/";
            38:title_char=u_video_mode?"G":digit({1'b0,u_total});
            7:title_char=TF_AUDIO?"M":" ";
            8:title_char=TF_AUDIO?digit({1'b0,u_mode}):" ";
            default:title_char=" ";
        endcase end
    endfunction
    function [7:0] slogan_char;
        input [5:0] index;
        begin case(index)
            0:slogan_char="F";1:slogan_char="P";2:slogan_char="G";3:slogan_char="A";
            5:slogan_char="M";6:slogan_char="E";7:slogan_char="D";8:slogan_char="I";9:slogan_char="A";
            11:slogan_char="D";12:slogan_char="I";13:slogan_char="S";14:slogan_char="P";
            15:slogan_char="L";16:slogan_char="A";17:slogan_char="Y";
            20:slogan_char="4";21:slogan_char="8";22:slogan_char="K";
            23:slogan_char="H";24:slogan_char="Z";
            26:slogan_char="A";27:slogan_char="U";28:slogan_char="D";
            29:slogan_char="I";30:slogan_char="O";
            32:slogan_char=TF_AUDIO?(u_music_present?(u_music_play?"P":"P"):"N"):" ";
            33:slogan_char=TF_AUDIO?(u_music_present?(u_music_play?"L":"A"):"O"):" ";
            34:slogan_char=TF_AUDIO?(u_music_present?(u_music_play?"A":"U"):" "):" ";
            35:slogan_char=TF_AUDIO?(u_music_present?(u_music_play?"Y":"S"):"A"):" ";
            36:slogan_char=TF_AUDIO?(u_music_present?(u_music_play?" ":"E"):"U"):" ";
            37:slogan_char=TF_AUDIO && !u_music_present?"D":" ";
            38:slogan_char=TF_AUDIO && !u_music_present?"I":" ";
            39:slogan_char=TF_AUDIO && !u_music_present?"O":" ";
            default:slogan_char=" ";
        endcase end
    endfunction
    function[7:0]hexchar;input[3:0]v;begin hexchar=v<10?8'd48+v:8'd65+v-10;end endfunction
    function[7:0]ir_char;input[5:0]n;begin
     case(n)
      0:ir_char="I";1:ir_char="R";2:ir_char=":";
      3:ir_char=u_ir_seen?hexchar(u_ir_code[31:28]):"-";
      4:ir_char=u_ir_seen?hexchar(u_ir_code[27:24]):"-";
      5:ir_char=u_ir_seen?hexchar(u_ir_code[23:20]):"-";
      6:ir_char=u_ir_seen?hexchar(u_ir_code[19:16]):"-";
      7:ir_char="/";
      8:ir_char=u_ir_seen?hexchar(u_ir_code[7:4]):"-";
      9:ir_char=u_ir_seen?hexchar(u_ir_code[3:0]):"-";
      default:ir_char=" ";
     endcase
    end endfunction
    function [7:0] bar_title_char;
        input [5:0] index;
        begin case(index)
            0:bar_title_char="A";1:bar_title_char="U";2:bar_title_char="D";
            3:bar_title_char="I";4:bar_title_char="O";6:bar_title_char="L";
            7:bar_title_char="E";8:bar_title_char="V";9:bar_title_char="E";
            10:bar_title_char="L";
            default:bar_title_char=" ";
        endcase end
    endfunction
    // Region decode and coordinate arithmetic precede the character ROM.
    // These booleans describe the same pixel as x1/y1 and trace0.
    always @* begin
        geometry=0;region_tmp=0;text_x_tmp=0;text_y_tmp=0;
        geometry[0]=osd_enable && (y1<32 || (y1>=440 && y1<472) || (SHOW_IR && y1>=30 && y1<54 && x1<176)) || wave_panel;
        geometry[1]=wave_panel && (y1==355 || x1==60 || x1==579 || y1==300 || y1==409);
        geometry[2]=wave_panel && valid_wave0 && x1>=64 && x1<576 && (y1==trace0 || y1+10'd1==trace0);
        geometry[3]=bar_panel;
        geometry[4]=bar_panel && (x1==60 || x1==579 || y1==334 || y1==427 || y1==372 || y1==396 || y1==420);
        geometry[5]=bar_panel && valid_wave0 && x1>=64 && x1<576 && x1[3:0]>=2 && x1[3:0]<14 && y1>=trace0 && y1<420;
        geometry[6]=y1==trace0;geometry[7]=y1<374;geometry[8]=y1<397;
        if(osd_enable && y1>=8 && y1<22 && x1>=8 && x1<632) begin
            text_x_tmp=x1-10'd8;text_y_tmp=y1-10'd8;region_tmp=1;
        end else if(osd_enable && SHOW_IR && y1>=34 && y1<48 && x1>=8 && x1<168)begin
            text_x_tmp=x1-10'd8;text_y_tmp=y1-10'd34;region_tmp=2;
        end else if(osd_enable && y1>=448 && y1<462)begin
            text_x_tmp=scroll_x;text_y_tmp=y1-10'd448;region_tmp=3;
        end else if(osd_enable && wave_enable && AUDIO_BARS && x1>=72 && x1<248 && y1>=338 && y1<352)begin
            text_x_tmp=x1-10'd72;text_y_tmp=y1-10'd338;region_tmp=4;
        end
        geometry[9]=region_tmp!=0;
    end
    // Background blending and colored bars are registered separately from
    // the white-font alpha step, so no glyph path spans both operations.
    always @*begin
        base_layer=faded6;
        if(flags[6][0])base_layer={1'b0,faded6[23:17],1'b0,faded6[15:9],1'b0,faded6[7:1]};
        if(flags[6][1])base_layer=24'h426078;
        if(flags[6][2])base_layer=24'h40ffb0;
        if(flags[6][3])base_layer={2'b00,faded6[23:18],2'b00,faded6[15:10],2'b00,faded6[7:2]};
        if(flags[6][4])base_layer=24'h304454;
        if(flags[6][5])begin
            if(flags[6][6])base_layer=24'hfff3ce;
            else if(flags[6][7])base_layer=24'hff5964;
            else if(flags[6][8])base_layer=24'hffce58;
            else base_layer=24'h41e3b0;
        end
    end
    always @(posedge pixel_clk or negedge rst_n)begin
        if(!rst_n)begin
            hs_pipe<=8'hff;vs_pipe<=8'hff;de_pipe<=0;
            x0<=0;y0<=0;x1<=0;y1<=0;trace0<=355;valid_wave0<=0;c0<=0;boff0<=0;boff1<=0;boff2<=0;
            for(k=0;k<3;k=k+1)begin centered[k]<=0;low_pair[k]<=0;high_pair[k]<=0;contrast_product[k]<=0;adjust_sum[k]<=0;clamped[k]<=0;end
            for(k=0;k<4;k=k+1)gain_pipe[k]<=0;
            for(k=2;k<8;k=k+1)flags[k]<=0;
            fade_product_r<=0;fade_product_g<=0;fade_product_b<=0;faded6<=0;layer7<=0;
            region2<=0;index2<=0;column2<=0;row2<=0;column3<=0;row3<=0;
            title3<=32;ir3<=32;slogan3<=32;bar3<=32;character4<=32;region3<=0;column4<=0;row4<=0;
            font4<=0;font5<=0;font6<=0;font7<=0;
            u_volume<=0;u_bright<=0;u_contrast<=0;u_sec0<=0;u_sec1<=0;u_min0<=0;u_min1<=0;
            u_mode<=0;u_video_mode<=0;u_current<=0;u_total<=0;u_ir_code<=0;u_ir_seen<=0;u_music_play<=0;u_music_present<=0;
            out_rgb<=0;out_hs<=1;out_vs<=1;out_de<=0;
        end else begin
            // Stages0..4: signed contrast and brightness, then saturation.
            centered[0]<=$signed({1'b0,in_rgb[23:16]})-12'sd128;
            centered[1]<=$signed({1'b0,in_rgb[15:8]})-12'sd128;
            centered[2]<=$signed({1'b0,in_rgb[7:0]})-12'sd128;
            c0<=contrast;boff0<=($signed({1'b0,brightness})-12'sd4)<<<5;
            boff1<=boff0;boff2<=boff1;
            for(k=0;k<3;k=k+1)begin
                low_pair[k]<=(c0[0]?centered[k]:12'sd0)+(c0[1]?(centered[k]<<<1):12'sd0);
                high_pair[k]<=(c0[2]?(centered[k]<<<2):12'sd0)+(c0[3]?(centered[k]<<<3):12'sd0);
                contrast_product[k]<=low_pair[k]+high_pair[k];
                adjust_sum[k]<=(contrast_product[k]>>>2)+12'sd128+boff2;
                clamped[k]<=clamp8(adjust_sum[k]);
            end
            // Fade uses gain one clock after the pixel input.
            gain_pipe[0]<=fade_gain;for(k=1;k<4;k=k+1)gain_pipe[k]<=gain_pipe[k-1];
            fade_product_r<=multiply_r;fade_product_g<=multiply_g;fade_product_b<=multiply_b;
            faded6<={fade_product_r[12:5],fade_product_g[12:5],fade_product_b[12:5]};
            x0<=in_x;y0<=in_y;x1<=x0;y1<=y0;
            // One-cycle wave RAM response is associated with the input pixel
            // one cycle earlier; trace0 is then used alongside x1/y1.
            if(AUDIO_BARS)trace0<=10'd420-({3'd0,wave_sample[6:0]}>>1);
            else trace0<=355-(($signed(wave_sample)*3)>>>3);
            valid_wave0<=wave_valid;
            // Stage2 geometry and contemporaneous UI controls.
            flags[2]<=geometry;for(k=3;k<8;k=k+1)flags[k]<=flags[k-1];
            region2<=region_tmp;index2<=text_x_tmp[9:4];column2<=text_x_tmp[3:1];row2<=text_y_tmp[3:1];
            u_volume<=volume_level;u_bright<=brightness;u_contrast<=contrast;u_mode<=control_mode;
            u_video_mode<=video_mode;u_current<=album_current;u_total<=album_total;u_ir_code<=ir_code;u_ir_seen<=ir_seen;
            u_music_play<=music_play;u_music_present<=music_present;
            u_sec0<=sec0;u_sec1<=sec1;u_min0<=min0;u_min1<=min1;
            // Parallel character lookup before the region mux supports the
            // 74.25MHz pixel pipeline.
            title3<=title_char(index2);ir3<=ir_char(index2);
            slogan3<=slogan_char(index2);bar3<=bar_title_char(index2);region3<=region2;
            case(region3)
                1:character4<=title3;2:character4<=ir3;
                3:character4<=slogan3;4:character4<=bar3;
                default:character4<=32;
            endcase
            column3<=column2;row3<=row2;column4<=column3;row4<=row3;
            font5<=font_pixel;font6<=font5;font7<=font6;
            // Stage7 colored background, stage8 font alpha and timing.
            layer7<=base_layer;
            out_rgb<=!de_pipe[7]?24'd0:(flags[7][9] && font7)?
                {8'd192+{2'b0,layer7[23:18]},8'd192+{2'b0,layer7[15:10]},8'd192+{2'b0,layer7[7:2]}}:layer7;
            out_hs<=hs_pipe[7];out_vs<=vs_pipe[7];out_de<=de_pipe[7];
            hs_pipe<={hs_pipe[6:0],in_hs};vs_pipe<={vs_pipe[6:0],in_vs};de_pipe<={de_pipe[6:0],in_de};
        end
    end
    // The timer/scroll control clock domain and update semantics are unchanged.
    always @(posedge pixel_clk or negedge rst_n)begin
        if(!rst_n)begin scroll<=0;frame_count<=0;sec0<=0;sec1<=0;min0<=0;min1<=0;end
        else if(vblank_start)begin
            scroll<=(scroll==639)?10'd0:scroll+1'b1;
            if(frame_count==FRAMES_PER_SECOND-1)begin
                frame_count<=0;
                if(sec0==9)begin
                    sec0<=0;
                    if(sec1==5)begin
                        sec1<=0;
                        if(min0==9)begin min0<=0;min1<=(min1==9)?4'd0:min1+1'b1;end
                        else min0<=min0+1'b1;
                    end else sec1<=sec1+1'b1;
                end else sec0<=sec0+1'b1;
            end else frame_count<=frame_count+1'b1;
        end
    end
endmodule
