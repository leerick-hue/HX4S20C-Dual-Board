`timescale 1ns/1ps
// RGB888 video pipeline: adjustment, fade, then alpha OSD and PCM waveform.
// Exactly 3 registered pixel stages. All input timing/coordinates must describe
// in_rgb. wave_sample is the synchronous RAM response to wave_addr (one cycle).
module video_effects #(
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
    input wire [2:0] album_current, input wire [2:0] album_total,
    input wire[31:0]ir_code,input wire ir_seen,
    input wire [2:0] control_mode,input wire music_play,input wire music_present,
    input wire osd_enable, input wire wave_enable,
    output wire [6:0] wave_addr, input wire signed [7:0] wave_sample,
    input wire wave_valid,
    output reg [23:0] out_rgb, output reg out_hs, output reg out_vs, output reg out_de
);
    reg [23:0] rgb1,rgb2;
    reg [9:0] x1,y1,x2,y2;
    reg hs1,vs1,de1,hs2,vs2,de2;
    reg [9:0] trace_y2;
    reg wave_valid2;
    reg [9:0] scroll;
    localparam integer FRAME_COUNT_BITS=(FRAMES_PER_SECOND<2)?1:$clog2(FRAMES_PER_SECOND);
    reg [FRAME_COUNT_BITS-1:0] frame_count;
    reg [3:0] sec0,sec1,min0,min1;
    reg [7:0] character;
    reg [9:0] text_x;
    reg [3:0] text_y;
    reg text_region,panel,wave_panel,wave_line;
    reg [23:0] composed;
    wire font_pixel;
    reg bar_panel,bar_border,bar_grid,bar_fill;
    wire [9:0] bar_x,bar_level_w,bar_top_w;
    wire [3:0] bar_off;
    wire [9:0] scroll_x=(x2+scroll>=640) ? x2+scroll-10'd640 : x2+scroll;
    // Keep the original horizontal span; the bar panel is thinner vertically.
    assign wave_addr=AUDIO_BARS ? ((in_x>=64 && in_x<576) ? (in_x-10'd64)>>4 : 7'd0)
                                : ((in_x>=64  && in_x<576) ? (in_x-10'd64)>>2  : 7'd0);
    assign bar_x=(x2>=64 && x2<576) ? x2-10'd64 : 10'd0;
    assign bar_off=bar_x[3:0];
    assign bar_level_w={3'd0,wave_sample[6:0]};
    assign bar_top_w=10'd420-(bar_level_w>>1);

    function [7:0] adjust;
        input [7:0] value;
        input [3:0] b,c;
        reg signed [11:0] centered,low_pair,high_pair,product,result;
        begin
            centered=$signed({1'b0,value})-12'sd128;
            // Four contrast bits need only two pairs of shifts/adds, rather
            // than a general multiplier. All intermediate values fit 12 bits.
            low_pair=(c[0]?centered:12'sd0)+(c[1]?(centered<<<1):12'sd0);
            high_pair=(c[2]?(centered<<<2):12'sd0)+(c[3]?(centered<<<3):12'sd0);
            product=low_pair+high_pair;
            result=(product>>>2)+12'sd128+(($signed({1'b0,b})-12'sd4)<<<5);
            if(result<0) adjust=0;
            else if(result>255) adjust=255;
            else adjust=result[7:0];
        end
    endfunction
    function [7:0] fade;
        input [7:0] value;
        input [5:0] gain;
        reg [13:0] sample_value,pair0,pair1,pair2,product;
        begin
            sample_value={6'd0,value};
            pair0=(gain[0]?sample_value:14'd0)+(gain[1]?(sample_value<<1):14'd0);
            pair1=(gain[2]?(sample_value<<2):14'd0)+(gain[3]?(sample_value<<3):14'd0);
            pair2=(gain[4]?(sample_value<<4):14'd0)+(gain[5]?(sample_value<<5):14'd0);
            product=(pair0+pair1)+pair2;
            fade=product[12:5];
        end
    endfunction
    function [7:0] digit;
        input [3:0] value;
        begin digit=8'd48+{4'd0,value}; end
    endfunction
    function [7:0] title_char;
        input [5:0] index;
        begin
        if(SHOW_VOLUME && index<7) begin
            case(index)
                0:title_char="V";1:title_char="O";2:title_char="L";3:title_char=":";
                4:title_char=digit(volume_level>8 ? 4'd8 : volume_level);
                5:title_char="/";6:title_char="8";
                default:title_char=" ";
            endcase
        end else case(index)
            0:title_char="H"; 1:title_char="X"; 2:title_char="4";
            3:title_char="S"; 4:title_char="2"; 5:title_char="0"; 6:title_char="C";
            9:title_char="T"; 10:title_char="I"; 11:title_char="M"; 12:title_char="E";
            14:title_char=digit(min1); 15:title_char=digit(min0); 16:title_char=":";
            17:title_char=digit(sec1); 18:title_char=digit(sec0);
            21:title_char="B"; 22:title_char=":";
            23:title_char=(brightness<4)?"-":"+";
            24:case(brightness) 0,8:title_char="1"; default:title_char="0"; endcase
            25:case(brightness) 0,8:title_char="2"; 1,7:title_char="9";
                2,6:title_char="6"; 3,5:title_char="3"; default:title_char="0"; endcase
            26:case(brightness) 0,8:title_char="8"; 1,7:title_char="6";
                2,6:title_char="4"; 3,5:title_char="2"; default:title_char="0"; endcase
            29:title_char="C"; 30:title_char=":";
            31:title_char=(contrast<4)?"0":((contrast<8)?"1":"2");
            32:title_char=".";
            33:case(contrast[1:0]) 0:title_char="0"; 1:title_char="2";
                2:title_char="5"; 3:title_char="7"; endcase
            34:title_char=contrast[0]?"5":"0";
            35:title_char="P";
            36:title_char=digit(album_current);
            37:title_char="/";
            38:title_char=digit(album_total);
            7:title_char=TF_AUDIO?"M":" ";
            8:title_char=TF_AUDIO?digit({1'b0,control_mode}):" ";
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
            32:slogan_char=TF_AUDIO?(music_present?(music_play?"P":"P"):"N"):" ";
            33:slogan_char=TF_AUDIO?(music_present?(music_play?"L":"A"):"O"):" ";
            34:slogan_char=TF_AUDIO?(music_present?(music_play?"A":"U"):" "):" ";
            35:slogan_char=TF_AUDIO?(music_present?(music_play?"Y":"S"):"A"):" ";
            36:slogan_char=TF_AUDIO?(music_present?(music_play?" ":"E"):"U"):" ";
            37:slogan_char=TF_AUDIO && !music_present?"D":" ";
            38:slogan_char=TF_AUDIO && !music_present?"I":" ";
            39:slogan_char=TF_AUDIO && !music_present?"O":" ";
            default:slogan_char=" ";
        endcase end
    endfunction
    function[7:0]hexchar;input[3:0]v;begin hexchar=v<10?8'd48+v:8'd65+v-10;end endfunction
    function[7:0]ir_char;input[5:0]n;begin
     case(n)
      0:ir_char="I";1:ir_char="R";2:ir_char=":";
      3:ir_char=ir_seen?hexchar(ir_code[31:28]):"-";
      4:ir_char=ir_seen?hexchar(ir_code[27:24]):"-";
      5:ir_char=ir_seen?hexchar(ir_code[23:20]):"-";
      6:ir_char=ir_seen?hexchar(ir_code[19:16]):"-";
      7:ir_char="/";
      8:ir_char=ir_seen?hexchar(ir_code[7:4]):"-";
      9:ir_char=ir_seen?hexchar(ir_code[3:0]):"-";
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
    font5x7 font(.character(character),.column(text_x[3:1]),.row(text_y[3:1]),.pixel(font_pixel));
    always @* begin
        character=" "; text_x=0; text_y=0; text_region=0;
        panel=osd_enable && (y2<32 || (y2>=440 && y2<472) || (SHOW_IR && y2>=30 && y2<54 && x2<176));
        wave_panel=osd_enable && wave_enable && !AUDIO_BARS && x2>=60 && x2<580 && y2>=300 && y2<410;
        wave_line=wave_panel && wave_valid2 && x2>=64 && x2<576 &&
                  (y2==trace_y2 || y2+10'd1==trace_y2);
        bar_panel=osd_enable && wave_enable && AUDIO_BARS && x2>=60 && x2<580 && y2>=334 && y2<428;
        bar_border=bar_panel && (x2==10'd60 || x2==10'd579 || y2==10'd334 || y2==10'd427);
        bar_grid=bar_panel && (y2==10'd372 || y2==10'd396 || y2==10'd420);
        bar_fill=bar_panel && wave_valid2 && x2>=64 && x2<576 && bar_off>=4'd2 && bar_off<4'd14 &&
                 y2>=trace_y2 && y2<10'd420;
        if(osd_enable && y2>=8 && y2<22 && x2>=8 && x2<632) begin
            text_x=x2-10'd8; text_y=y2-10'd8;
            character=title_char(text_x[9:4]); text_region=1;
        end else if(osd_enable && SHOW_IR && y2>=34 && y2<48 && x2>=8 && x2<168)begin
            text_x=x2-10'd8;text_y=y2-10'd34;character=ir_char(text_x[9:4]);text_region=1;
        end else if(osd_enable && y2>=448 && y2<462) begin
            text_x=scroll_x; text_y=y2-10'd448;
            character=slogan_char(scroll_x[9:4]); text_region=1;
        end else if(osd_enable && wave_enable && AUDIO_BARS && x2>=72 && x2<248 && y2>=338 && y2<352) begin
            text_x=x2-10'd72; text_y=y2-10'd338;
            character=bar_title_char(text_x[9:4]); text_region=1;
        end
        composed=rgb2;
        // 50% black panels retain the underlying photograph.
        if(panel || wave_panel) composed={1'b0,rgb2[23:17],1'b0,rgb2[15:9],1'b0,rgb2[7:1]};
        if(wave_panel && (y2==355 || x2==60 || x2==579 || y2==300 || y2==409))
            composed=24'h426078;
        if(wave_line) composed=24'h40ffb0;
        // Bar mode: 25% panel, 24'h304454 border/grid, level-scaled fill (AUDIO_BARS only).
        if(bar_panel) composed={2'b00,rgb2[23:18],2'b00,rgb2[15:10],2'b00,rgb2[7:2]};
        if(bar_border || bar_grid) composed=24'h304454;
        if(bar_fill) begin
            if(y2==trace_y2) composed=24'hfff3ce;
            else if(y2<10'd374) composed=24'hff5964;
            else if(y2<10'd397) composed=24'hffce58;
            else composed=24'h41e3b0;
        end
        // 75% white text over the existing layer, independently per channel.
        if(text_region && font_pixel)
            composed={8'd192+{2'b0,composed[23:18]},8'd192+{2'b0,composed[15:10]},
                      8'd192+{2'b0,composed[7:2]}};
    end
    always @(posedge pixel_clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb1<=0;rgb2<=0;x1<=0;y1<=0;x2<=0;y2<=0;
            hs1<=1;vs1<=1;de1<=0;hs2<=1;vs2<=1;de2<=0;
            out_rgb<=0;out_hs<=1;out_vs<=1;out_de<=0;
            trace_y2<=355;wave_valid2<=0;scroll<=0;frame_count<=0;
            sec0<=0;sec1<=0;min0<=0;min1<=0;
        end else begin
            rgb1<={adjust(in_rgb[23:16],brightness,contrast),adjust(in_rgb[15:8],brightness,contrast),
                   adjust(in_rgb[7:0],brightness,contrast)};
            x1<=in_x;y1<=in_y;hs1<=in_hs;vs1<=in_vs;de1<=in_de;
            rgb2<={fade(rgb1[23:16],fade_gain),fade(rgb1[15:8],fade_gain),fade(rgb1[7:0],fade_gain)};
            x2<=x1;y2<=y1;hs2<=hs1;vs2<=vs1;de2<=de1;
            // RAM data and x2/y2 describe the same pixel after this register.
            if(AUDIO_BARS) trace_y2<=bar_top_w;
            else trace_y2<=355-(($signed(wave_sample)*3) >>> 3);
            wave_valid2<=wave_valid;
            out_rgb<=de2?composed:24'd0;out_hs<=hs2;out_vs<=vs2;out_de<=de2;
            if(vblank_start) begin
                scroll<=(scroll==639)?10'd0:scroll+1'b1;
                if(frame_count==FRAMES_PER_SECOND-1) begin
                    frame_count<=0;
                    if(sec0==9) begin sec0<=0;
                        if(sec1==5) begin sec1<=0;
                            if(min0==9) begin min0<=0;min1<=(min1==9)?4'd0:min1+1'b1;end
                            else min0<=min0+1'b1;
                        end else sec1<=sec1+1'b1;
                    end else sec0<=sec0+1'b1;
                end else frame_count<=frame_count+1'b1;
            end
        end
    end
endmodule
