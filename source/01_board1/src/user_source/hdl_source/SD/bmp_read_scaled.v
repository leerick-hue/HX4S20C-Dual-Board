`timescale 1ns/1ps
// Sector-aligned, contiguous raw BMP files; this is not a FAT reader.
// A complete sector is buffered before the decoder sees it, allowing
// arbitrary row-buffer and pixel-FIFO backpressure without losing SD bytes.
module bmp_read_scaled #(parameter integer WIDTH=640, HEIGHT=480, KEEP_ASPECT=0,
    parameter integer PIXEL_ADDR_BITS=(64'd1*WIDTH*HEIGHT>64'd524288) ?
        $clog2(64'd1*WIDTH*HEIGHT) : 19)(
    input wire clk, input wire rst, output wire ready,
    input wire scan_start, input wire [31:0] scan_start_sector,
    input wire [31:0] scan_max_sector, input wire [2:0] scan_target_count,
    output reg scan_done, output reg scan_found_valid,
    output reg [31:0] scan_found_sector, output reg [2:0] scan_found_total,
    input wire load_start, input wire [31:0] load_sector,
    input wire sd_init_done, output reg [3:0] state_code,
    input wire [15:0] bmp_width, input wire [15:0] bmp_height,
    output reg write_req, input wire write_req_ack,
    output reg sd_sec_read, output reg [31:0] sd_sec_read_addr,
    input wire [7:0] sd_sec_read_data, input wire sd_sec_read_data_valid,
    input wire sd_sec_read_end,
    output wire bmp_data_wr_en, output wire [23:0] bmp_data,
    output wire [PIXEL_ADDR_BITS-1:0] bmp_pixel_addr, input wire pixel_ready,
    output wire [10:0] source_width_debug,source_height_debug,
    output wire load_done, output wire load_error,
    output wire [3:0] load_error_code
);
    localparam [3:0] IDLE=0,SCAN=1,HEADER=2,WAIT_ACK=3,WAIT_RELEASE=4,
        START=5,READ=6,DRAIN=7,FETCH=8;
    reg [3:0] state;
    reg [8:0] header_pos, fill_pos, drain_pos;
    reg [15:0] magic, planes, bit_count;
    reg [31:0] file_len,pixel_offset,width,height,dib_size,compression;
    reg [31:0] scan_sector,load_sector_latched,stream_pos;
    reg [7:0] sector_mem[0:511];
    reg [7:0] sector_q;
    always @(posedge clk) sector_q<=sector_mem[drain_pos];
    reg parser_start;
    reg [1:0] ack_sync;
    wire byte_ready,parser_busy,parser_done,parser_error;
    wire [3:0] parser_error_code;
    wire [31:0] abs_height=height[31] ? (~height+32'd1) : height;
    reg [31:0] sector_count;
    reg [32:0] following_sector;
    reg following_outside;
    reg [31:0] last_byte_pos;
    reg byte_available,byte_is_last;
    reg [31:0] height_magnitude_q;
    reg dimensions_ok,format_ok,size_ok;
    wire header_match=dimensions_ok && format_ok && size_ok;
    // Header fields finish by byte 33. Register independent checks while the
    // rest of the 512-byte sector arrives, well before the scan decision.
    always @(posedge clk or posedge rst) begin
        if(rst) begin height_magnitude_q<=0;dimensions_ok<=0;format_ok<=0;size_ok<=0;
            sector_count<=0;following_sector<=0;following_outside<=0;last_byte_pos<=0;
            byte_available<=0;byte_is_last<=0;end
        else begin
            // File length finishes at byte 5; these stages settle long before sector end.
            sector_count<=(file_len+32'd511)>>9;
            last_byte_pos<=file_len-32'd1;
            // FETCH supplies a full cycle after stream_pos advances, before DRAIN consumes it.
            byte_available<=stream_pos<file_len;
            byte_is_last<=stream_pos==last_byte_pos;
            following_sector<={1'b0,scan_sector}+{1'b0,sector_count};
            following_outside<=following_sector>{1'b0,scan_max_sector};
            height_magnitude_q<=abs_height;
            dimensions_ok<=width>0 && width<=1920 && height_magnitude_q>0 && height_magnitude_q<=1080;
            format_ok<=magic==16'h4d42 && planes==1 && bit_count==24 && compression==0;
            size_ok<=dib_size>=40 && dib_size<=124 && pixel_offset>=dib_size+14 &&
                     file_len>=pixel_offset && file_len<32'hfffffe00;
        end
    end
    wire byte_valid=state==DRAIN && byte_available;
    wire byte_take=byte_valid && byte_ready;
    assign ready=state==IDLE;
    assign load_done=parser_done;
    assign load_error=parser_error;
    assign load_error_code=parser_error_code;
    bmp24_scale_stream #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.KEEP_ASPECT(KEEP_ASPECT),.PIXEL_ADDR_BITS(PIXEL_ADDR_BITS)) scaler(
        .source_width_debug(source_width_debug),.source_height_debug(source_height_debug),
        .clk(clk),.rst_n(!rst),.start(parser_start),.abort(!sd_init_done),
        .file_size(file_len),.byte_data(sector_q),
        .byte_valid(byte_valid),.byte_ready(byte_ready),
        .byte_last(byte_is_last),
        .pixel_valid(bmp_data_wr_en),.pixel_ready(pixel_ready),
        .pixel_addr(bmp_pixel_addr),.pixel_rgb(bmp_data),
        .done(parser_done),.error(parser_error),.error_code(parser_error_code),.busy(parser_busy));
    always @(posedge clk) begin
        if(state==READ && sd_sec_read_data_valid) sector_mem[fill_pos]<=sd_sec_read_data;
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            header_pos<=0; magic<=0; file_len<=0; pixel_offset<=0;
            width<=0; height<=0; dib_size<=0; planes<=0; bit_count<=0; compression<=0;
        end else if((state==SCAN || state==HEADER) && sd_sec_read_data_valid) begin
            header_pos<=header_pos+1'b1;
            case(header_pos)
            0,1: magic<={sd_sec_read_data,magic[15:8]};
            2,3,4,5: file_len<={sd_sec_read_data,file_len[31:8]};
            10,11,12,13: pixel_offset<={sd_sec_read_data,pixel_offset[31:8]};
            14,15,16,17: dib_size<={sd_sec_read_data,dib_size[31:8]};
            18,19,20,21: width<={sd_sec_read_data,width[31:8]};
            22,23,24,25: height<={sd_sec_read_data,height[31:8]};
            26,27: planes<={sd_sec_read_data,planes[15:8]};
            28,29: bit_count<={sd_sec_read_data,bit_count[15:8]};
            30,31,32,33: compression<={sd_sec_read_data,compression[31:8]};
            default: begin end
            endcase
        end else if(sd_sec_read_end || (state!=SCAN && state!=HEADER)) header_pos<=0;
    end
    always @(posedge clk or posedge rst) begin
        if(rst) ack_sync<=0;
        else ack_sync<={ack_sync[0],write_req_ack};
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE; state_code<=0; scan_done<=0; scan_found_valid<=0;
            scan_found_sector<=0; scan_found_total<=0; scan_sector<=0;
            load_sector_latched<=0; stream_pos<=0; fill_pos<=0; drain_pos<=0;
            write_req<=0; sd_sec_read<=0; sd_sec_read_addr<=0; parser_start<=0;
        end else if(!sd_init_done) begin
            state<=IDLE; state_code<=0; scan_done<=0; scan_found_valid<=0;
            scan_found_total<=0; write_req<=0; sd_sec_read<=0; parser_start<=0;
        end else begin
            scan_found_valid<=0; parser_start<=0;
            case(state)
            IDLE: begin
                state_code<=1; sd_sec_read<=0; write_req<=0;
                if(scan_start) begin
                    scan_done<=0; scan_found_total<=0; scan_sector<=scan_start_sector;
                    sd_sec_read_addr<=scan_start_sector; state<=SCAN;
                end else if(load_start) begin
                    load_sector_latched<=load_sector; sd_sec_read_addr<=load_sector;
                    state<=HEADER;
                end
            end
            SCAN: begin
                state_code<=2; sd_sec_read<=1;
                if(sd_sec_read_end) begin
                    sd_sec_read<=0;
                    if(header_match) begin
                        scan_found_valid<=1; scan_found_sector<=scan_sector;
                        scan_found_total<=scan_found_total+1'b1;
                        if(scan_found_total+1>=scan_target_count || following_outside) begin
                            scan_done<=1; state<=IDLE;
                        end else begin
                            scan_sector<=following_sector[31:0]; sd_sec_read_addr<=following_sector[31:0];
                        end
                    end else if(scan_sector>=scan_max_sector) begin scan_done<=1; state<=IDLE; end
                    else begin scan_sector<=scan_sector+1'b1; sd_sec_read_addr<=scan_sector+1'b1; end
                end
            end
            HEADER: begin
                state_code<=2; sd_sec_read<=1;
                if(sd_sec_read_end) begin sd_sec_read<=0; write_req<=1; state<=WAIT_ACK; end
            end
            WAIT_ACK: begin
                state_code<=3;
                if(ack_sync[1]) begin write_req<=0; state<=WAIT_RELEASE; end
            end
            WAIT_RELEASE: if(!ack_sync[1]) state<=START;
            START: begin
                parser_start<=1; stream_pos<=0; fill_pos<=0; drain_pos<=0;
                sd_sec_read_addr<=load_sector_latched; state<=READ;
            end
            READ: begin
                state_code<=4; sd_sec_read<=1;
                if(sd_sec_read_data_valid) fill_pos<=fill_pos+1'b1;
                if(sd_sec_read_end) begin sd_sec_read<=0; drain_pos<=0; state<=FETCH; end
            end
            FETCH: state<=DRAIN;
            DRAIN: if(byte_take) begin
                state<=FETCH;
                stream_pos<=stream_pos+1'b1; drain_pos<=drain_pos+1'b1;
                if(drain_pos==511 && !byte_is_last) begin
                    sd_sec_read_addr<=sd_sec_read_addr+1'b1; fill_pos<=0; state<=READ;
                end
            end
            default: state<=IDLE;
            endcase
            if(parser_done || parser_error) begin
                state<=IDLE; sd_sec_read<=0; state_code<=parser_error ? 4'he : 4'd1;
            end
        end
    end
endmodule
