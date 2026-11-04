`timescale 1ns/1ps
// Streaming Windows 24-bpp BI_RGB BMP decoder and nearest-neighbour scaler.
// KEEP_ASPECT=1 fits and centers the image with black bars; 0 stretches.
// Every output address is written exactly once, including black bars. Mapping:
// src_x=floor(dst_x*source_width/WIDTH), likewise for y (top-left origin).
// A single source scanline is buffered; no full-frame on-chip storage is used.
// Quotients/remainders are prepared by bounded repeated subtraction, then
// coordinates advance with addition/comparison. No runtime divider is used.
// The largest default RAM is 1920 x 24 bits, with a synchronous read port.
// byte_last denotes file EOF, not an SD-sector boundary. Bytes after the BMP
// pixel array need not be consumed; file_size is the independently known size.
module bmp24_scale_stream #(
    parameter integer WIDTH=640, parameter integer HEIGHT=480,
    parameter integer MAX_SOURCE_WIDTH=1920,
    parameter integer MAX_SOURCE_HEIGHT=1080,
    parameter integer KEEP_ASPECT=0,
    // Declared as a parameter because the ANSI pixel_addr port range uses it.
    parameter integer PIXEL_ADDR_BITS=(64'd1*WIDTH*HEIGHT>64'd524288) ?
        $clog2(64'd1*WIDTH*HEIGHT) : 19
)(
    input wire clk, input wire rst_n,
    input wire start, input wire abort,
    input wire [31:0] file_size,
    input wire [7:0] byte_data, input wire byte_valid, output wire byte_ready,
    input wire byte_last,
    output reg pixel_valid, input wire pixel_ready,
    output reg [PIXEL_ADDR_BITS-1:0] pixel_addr, output wire [23:0] pixel_rgb,
    output reg done, output reg error, output reg [3:0] error_code,
    output wire [10:0] source_width_debug,source_height_debug,
    output wire busy
);
    localparam [4:0] IDLE=0, HEADER=1, CHECK=2, SIZE_ADD=3, SIZE_CHECK=4,
        DIV_X=5, DIV_Y=6, PREPARE=7, SKIP=8, PIXELS=9, PAD=10,
        ROW_READY=11, READ_PIXEL=12, EMIT=13, ROW_ADVANCE=14,
        FLUSH=15, FAILED=16, SIZE_PREP=17, FIT_PREP=18, FIT_SELECT=19,
        FIT_DIV=20, FIT_FINISH=21;
    localparam [19:0] DEST_W=WIDTH, DEST_H=HEIGHT;
    localparam [PIXEL_ADDR_BITS-1:0] ROW_WORDS=WIDTH;
    localparam integer BOTTOM_BASE=(HEIGHT-1)*WIDTH;
    // Each output dimension may be at most 2^19 so its last coordinate fits
    // dest_x/dest_y and the dimensions fit the 20-bit fit_* registers. The
    // frame is capped at 2^21 pixels and must fit PIXEL_ADDR_BITS. Invalid
    // parameters fail with code 4.
    localparam integer OUTPUT_OK=(WIDTH>0 && HEIGHT>0 && WIDTH<=524288 &&
        HEIGHT<=524288 && (64'd1*WIDTH*HEIGHT)<=64'd2097152 &&
        (64'd1*WIDTH*HEIGHT)<=(64'd1<<PIXEL_ADDR_BITS));
    reg [4:0] state;
    reg [31:0] position, actual_size, declared_size, offset, dib_size;
    reg [31:0] width_in, height_in, compression;
    reg [15:0] magic, planes, bits;
    reg [10:0] source_width, source_height, file_row, logical_row;
    reg [10:0] write_x, source_x, target_y, size_rows;
    reg [12:0] stride;
    reg [31:0] payload_size;
    reg [1:0] padding, pad_left, component;
    reg [7:0] blue, green;
    reg top_down, output_remaining;
    reg [10:0] step_x, step_y;
    localparam integer PHASE_X_BITS=$clog2(WIDTH+MAX_SOURCE_WIDTH+1);
    localparam integer PHASE_Y_BITS=$clog2(HEIGHT+MAX_SOURCE_HEIGHT+1);
    reg [PHASE_X_BITS-1:0] rem_x,phase_x;
    reg [PHASE_Y_BITS-1:0] rem_y,phase_y;
    localparam integer DEST_X_BITS=(WIDTH>1)?$clog2(WIDTH):1;
    localparam integer DEST_Y_BITS=(HEIGHT>1)?$clog2(HEIGHT):1;
    reg [DEST_X_BITS-1:0] dest_x;
    reg [DEST_Y_BITS-1:0] dest_y;
    reg last_output_column;
    reg [PIXEL_ADDR_BITS-1:0] row_base;
    localparam integer FIT_X_BITS=(WIDTH>1)?$clog2(WIDTH+1):1;
    localparam integer FIT_Y_BITS=(HEIGHT>1)?$clog2(HEIGHT+1):1;
    reg [FIT_X_BITS-1:0] fit_width_q,fit_x_q,fit_right_q;
    reg [FIT_Y_BITS-1:0] fit_height_q,fit_y_q,fit_bottom_q;
    wire [FIT_X_BITS-1:0] fit_width=KEEP_ASPECT?fit_width_q:WIDTH;
    wire [FIT_Y_BITS-1:0] fit_height=KEEP_ASPECT?fit_height_q:HEIGHT;
    wire [FIT_X_BITS-1:0] fit_x=KEEP_ASPECT?fit_x_q:0;
    wire [FIT_Y_BITS-1:0] fit_y=KEEP_ASPECT?fit_y_q:0;
    wire [FIT_X_BITS-1:0] fit_right=KEEP_ASPECT?fit_right_q:WIDTH;
    wire [FIT_Y_BITS-1:0] fit_bottom=KEEP_ASPECT?fit_bottom_q:HEIGHT;
    reg [31:0] aspect_w,aspect_h,aspect_remaining;
    reg [10:0] aspect_divisor;
    reg [19:0] aspect_quotient;
    reg width_limited;
    reg [23:0] line_pixels [0:MAX_SOURCE_WIDTH-1];
    reg [23:0] line_pixel_q;
    reg read_black;
    // Keep the synchronous RAM read pure; a conditional value on its data
    // output prevents TD from inferring BRAM and costs thousands of LUTs.
    assign pixel_rgb=(KEEP_ASPECT && read_black)?24'd0:line_pixel_q;
    reg [31:0] height_magnitude;
    reg [31:0] last_skip_position;
    reg bad_magic,bad_dib,bad_dimensions,bad_format;
    reg [10:0] source_last_x,source_last_y;
    reg last_input_row,last_input_column;
    wire [32:0] header_end={1'b0,dib_size}+33'd14;
    reg [32:0] required_size;
    wire [PHASE_X_BITS-1:0] next_phase_x=phase_x+rem_x;
    wire [PHASE_Y_BITS-1:0] next_phase_y=phase_y+rem_y;
    wire take_byte=byte_valid && byte_ready;
    wire image_row=!KEEP_ASPECT || ({1'b0,dest_y}>=fit_y && {1'b0,dest_y}<fit_bottom);
    wire image_column=!KEEP_ASPECT || ({1'b0,dest_x}>=fit_x && {1'b0,dest_x}<fit_right);
    wire final_payload_byte=last_input_row &&
        ((state==PIXELS && last_input_column && component==2 && padding==0) ||
         (state==PAD && pad_left==1));
    assign byte_ready=(state==HEADER || state==SKIP || state==PIXELS || state==PAD);
    assign source_width_debug=source_width;
    assign source_height_debug=source_height;
    assign busy=(state!=IDLE && state!=FAILED);

    // The RAM is intentionally not reset. Every used location is overwritten
    // by the current source row before its synchronous read is enabled.
    always @(posedge clk) begin
        if (rst_n && !abort && state==PIXELS && take_byte && component==2)
            line_pixels[write_x]<={byte_data,green,blue};
        if (rst_n && !abort && state==READ_PIXEL)
            line_pixel_q<=line_pixels[source_x];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; height_magnitude<=0; required_size<=0; position<=0; actual_size<=0; declared_size<=0;
            offset<=0; dib_size<=0; width_in<=0; height_in<=0; compression<=0;
            magic<=0; planes<=0; bits<=0; source_width<=0; source_height<=0;
            file_row<=0; logical_row<=0; write_x<=0; source_x<=0; target_y<=0;
            size_rows<=0; stride<=0; payload_size<=0; padding<=0; pad_left<=0;
            component<=0; blue<=0; green<=0; top_down<=0; output_remaining<=0;
            step_x<=0; step_y<=0; rem_x<=0; rem_y<=0; phase_x<=0; phase_y<=0;
            dest_x<=0; dest_y<=0; row_base<=0;
            fit_width_q<=WIDTH;fit_height_q<=HEIGHT;fit_x_q<=0;fit_y_q<=0;
            fit_right_q<=WIDTH;fit_bottom_q<=HEIGHT;aspect_w<=0;aspect_h<=0;
            aspect_remaining<=0;aspect_divisor<=1;aspect_quotient<=0;width_limited<=0;
            pixel_valid<=0; pixel_addr<=0;
            read_black<=1;
            bad_magic<=0;bad_dib<=0;bad_dimensions<=0;bad_format<=0;last_skip_position<=0;
            source_last_x<=0;source_last_y<=0;last_input_row<=0;last_input_column<=0;last_output_column<=0;
            done<=0; error<=0; error_code<=0;
        end else begin
            // Height finishes at header byte 25; this pipeline settles before CHECK after byte 53.
            height_magnitude<=height_in[31] ? (~height_in+32'd1) : height_in;
            last_skip_position<=offset-32'd1;
            // Header fields settle many bytes before byte53. Register the
            // validation predicates before their priority/error selection.
            bad_magic<=magic!=16'h4d42;
            bad_dib<=dib_size<40 || dib_size>124 || header_end>{1'b0,offset};
            bad_dimensions<=!OUTPUT_OK || width_in==0 || height_magnitude==0 ||
                width_in>1920 || height_magnitude>1080 ||
                width_in>MAX_SOURCE_WIDTH || height_magnitude>MAX_SOURCE_HEIGHT;
            bad_format<=planes!=1 || bits!=24 || compression!=0;
            source_last_x<=source_width-11'd1;source_last_y<=source_height-11'd1;
            // Row/column advance precedes the third RGB byte by at least two
            // clocks. These flags remove subtract/compare from the EOF path.
            last_input_row<=file_row==source_last_y;
            last_input_column<=write_x==source_last_x;
            done<=0; error<=0;
            if (pixel_valid && pixel_ready) pixel_valid<=0;
            if (abort) begin state<=IDLE; pixel_valid<=0; end
            else if (start && (state==IDLE || state==FAILED)) begin
                state<=HEADER; position<=0; actual_size<=file_size;
                declared_size<=0; offset<=0; dib_size<=0; width_in<=0; height_in<=0;
                compression<=0; magic<=0; planes<=0; bits<=0;
                file_row<=0; write_x<=0; component<=0; pixel_valid<=0;
                payload_size<=0; step_x<=0; step_y<=0; error_code<=0;
                if (file_size<54) begin state<=FAILED; error<=1; error_code<=1; end
            end else begin
                if (take_byte) position<=position+32'd1;
                case (state)
                HEADER: if (take_byte) begin
                    case (position)
                    0,1: magic<={byte_data,magic[15:8]};
                    2,3,4,5: declared_size<={byte_data,declared_size[31:8]};
                    10,11,12,13: offset<={byte_data,offset[31:8]};
                    14,15,16,17: dib_size<={byte_data,dib_size[31:8]};
                    18,19,20,21: width_in<={byte_data,width_in[31:8]};
                    22,23,24,25: height_in<={byte_data,height_in[31:8]};
                    26,27: planes<={byte_data,planes[15:8]};
                    28,29: bits<={byte_data,bits[15:8]};
                    30,31,32,33: compression<={byte_data,compression[31:8]};
                    default: begin end
                    endcase
                    if (position==53) state<=CHECK;
                end
                CHECK: begin
                    if (bad_magic) begin state<=FAILED; error<=1; error_code<=2; end
                    else if (bad_dib) begin
                        state<=FAILED; error<=1; error_code<=3;
                    end else if (bad_dimensions) begin
                        state<=FAILED; error<=1; error_code<=4;
                    end else if (bad_format) begin
                        state<=FAILED; error<=1; error_code<=5;
                    end else begin
                        source_width<=width_in[10:0]; source_height<=height_magnitude[10:0];
                        size_rows<=height_magnitude[10:0]; top_down<=height_in[31];
                        stride<=((width_in[12:0]<<1)+width_in[12:0]+13'd3)&13'h1ffc;
                        // (-3*width) modulo 4 equals width modulo 4.
                        padding<=width_in[1:0];
                        rem_x<={9'd0,width_in[10:0]}; rem_y<={9'd0,height_magnitude[10:0]};
                        state<=SIZE_ADD;
                    end
                end
                SIZE_ADD: begin
                    payload_size<=payload_size+{19'd0,stride};
                    size_rows<=size_rows-11'd1;
                    if (size_rows==1) state<=SIZE_PREP;
                end
                SIZE_PREP: begin required_size<={1'b0,offset}+{1'b0,payload_size};state<=SIZE_CHECK;end
                SIZE_CHECK: begin
                    if (required_size>{1'b0,actual_size} || required_size>{1'b0,declared_size} ||
                        declared_size>actual_size) begin
                        state<=FAILED; error<=1; error_code<=6;
                    end else state<=FIT_PREP;
                end
                FIT_PREP: begin
                    // Constant multipliers are outside the pixel loop. Division
                    // is bounded repeated subtraction once per image, never '/'.
                    aspect_w<=source_width*HEIGHT;aspect_h<=source_height*WIDTH;
                    fit_width_q<=WIDTH;fit_height_q<=HEIGHT;state<=FIT_SELECT;
                end
                FIT_SELECT: begin
                    if(KEEP_ASPECT && aspect_w!=aspect_h) begin
                        width_limited<=aspect_w>aspect_h;
                        aspect_remaining<=(aspect_w>aspect_h) ? aspect_h : aspect_w;
                        aspect_divisor<=(aspect_w>aspect_h) ? source_width : source_height;
                        aspect_quotient<=0;state<=FIT_DIV;
                    end else state<=FIT_FINISH;
                end
                FIT_DIV: begin
                    if(aspect_remaining>={21'd0,aspect_divisor}) begin
                        aspect_remaining<=aspect_remaining-{21'd0,aspect_divisor};
                        aspect_quotient<=aspect_quotient+20'd1;
                    end else begin
                        if(width_limited) fit_height_q<=(aspect_quotient==0)?20'd1:aspect_quotient;
                        else fit_width_q<=(aspect_quotient==0)?20'd1:aspect_quotient;
                        state<=FIT_FINISH;
                    end
                end
                FIT_FINISH: begin
                    fit_x_q<=(DEST_W-fit_width)>>1;fit_y_q<=(DEST_H-fit_height)>>1;
                    fit_right_q<=((DEST_W-fit_width)>>1)+fit_width;
                    fit_bottom_q<=((DEST_H-fit_height)>>1)+fit_height;
                    state<=DIV_X;
                end
                DIV_X: begin
                    if (rem_x>=fit_width) begin rem_x<=rem_x-fit_width; step_x<=step_x+11'd1; end
                    else state<=DIV_Y;
                end
                DIV_Y: begin
                    if (rem_y>=fit_height) begin rem_y<=rem_y-fit_height; step_y<=step_y+11'd1; end
                    else state<=PREPARE;
                end
                PREPARE: begin
                    logical_row<=top_down ? 11'd0 : source_height-11'd1;
                    dest_y<=top_down ? 19'd0 : HEIGHT-1;
                    row_base<=top_down ? {PIXEL_ADDR_BITS{1'b0}} : BOTTOM_BASE[PIXEL_ADDR_BITS-1:0];
                    target_y<=top_down ? 11'd0 : source_height-step_y-((rem_y!=0)?11'd1:11'd0);
                    phase_y<=top_down || rem_y==0 ? 20'd0 : fit_height-rem_y;
                    output_remaining<=1;
                    state<=(position==offset) ? PIXELS : SKIP;
                end
                SKIP: if (take_byte && position==last_skip_position) state<=PIXELS;
                PIXELS: if (take_byte) begin
                    case (component)
                    0: begin blue<=byte_data; component<=1; end
                    1: begin green<=byte_data; component<=2; end
                    2: begin
                        component<=0;
                        if (write_x==source_last_x) begin
                            if (padding==0) state<=ROW_READY;
                            else begin state<=PAD; pad_left<=padding; end
                        end else write_x<=write_x+11'd1;
                    end
                    default: component<=0;
                    endcase
                end
                PAD: if (take_byte) begin
                    if (pad_left==1) state<=ROW_READY;
                    else pad_left<=pad_left-2'd1;
                end
                ROW_READY: begin
                    if (output_remaining && (!image_row || logical_row==target_y)) begin
                        dest_x<=0; source_x<=0; phase_x<=0; state<=READ_PIXEL;
                    end else state<=ROW_ADVANCE;
                end
                READ_PIXEL: begin
                    read_black<=!(image_row && image_column);
                    last_output_column<=({1'b0,dest_x}==DEST_W-20'd1);
                    pixel_addr<=row_base+dest_x; pixel_valid<=1; state<=EMIT;
                end
                EMIT: if (pixel_ready) begin
                    if (last_output_column) begin
                        if ((top_down && {1'b0,dest_y}==DEST_H-20'd1) || (!top_down && dest_y==0))
                            output_remaining<=0;
                        else if (top_down) begin
                            dest_y<=dest_y+19'd1; row_base<=row_base+ROW_WORDS;
                            if(image_row) begin
                                if (next_phase_y>=fit_height) begin
                                    phase_y<=next_phase_y-fit_height; target_y<=target_y+step_y+11'd1;
                                end else begin phase_y<=next_phase_y; target_y<=target_y+step_y; end
                            end
                        end else begin
                            dest_y<=dest_y-19'd1; row_base<=row_base-ROW_WORDS;
                            if(image_row) begin
                                if (phase_y<rem_y) begin
                                    phase_y<=phase_y+fit_height-rem_y; target_y<=target_y-step_y-11'd1;
                                end else begin phase_y<=phase_y-rem_y; target_y<=target_y-step_y; end
                            end
                        end
                        state<=ROW_READY;
                    end else begin
                        dest_x<=dest_x+19'd1;
                        if(image_column && image_row) begin
                            if (next_phase_x>=fit_width) begin
                                phase_x<=next_phase_x-fit_width; source_x<=source_x+step_x+11'd1;
                            end else begin phase_x<=next_phase_x; source_x<=source_x+step_x; end
                        end
                        state<=READ_PIXEL;
                    end
                end
                ROW_ADVANCE: begin
                    if (file_row==source_last_y) state<=FLUSH;
                    else begin
                        file_row<=file_row+11'd1; logical_row<=top_down ? logical_row+11'd1 : logical_row-11'd1;
                        write_x<=0; component<=0; state<=PIXELS;
                    end
                end
                FLUSH: if (!pixel_valid || pixel_ready) begin done<=1; state<=IDLE; end
                default: begin end
                endcase
                // EOF before the complete pixel array is always an error,
                // including a truncated row that would not be sampled.
                if (take_byte && byte_last && !final_payload_byte) begin
                    state<=FAILED; error<=1; error_code<=7; pixel_valid<=0;
                end
            end
        end
    end
endmodule
