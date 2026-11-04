`timescale 1ns/1ps
// Integer division appears only in this independent reference model.
module tb_scale;
    parameter integer W=1280,H=720,FIT=1;
    localparam integer N=W*H, MAX=1920*3*1080+512;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,abort=0,bv=0,bl=0,pr=0;
    reg [31:0] fs; reg [7:0] bd;
    wire br,pv,done,error,busy; localparam integer PADDR_BITS=(N>1)?$clog2(N):1; wire [PADDR_BITS-1:0] pa; wire [23:0] rgb; wire [3:0] ec;
    reg [7:0] bytes[0:MAX-1]; integer seen[0:N-1];
    integer sw,sh,payload_end,outputs=0,code_seen=0,test_count=0;
    integer sx,sy,k,fw,fh,ox,oy,px,py; reg [23:0] expected;
    reg done_seen=0,error_seen=0,stalled=0,random_stalls=1;
    reg [PADDR_BITS+23:0] held; reg [31:0] rng=32'h914a2c3d;
    bmp24_scale_stream #(.WIDTH(W),.HEIGHT(H),.KEEP_ASPECT(FIT)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.abort(abort),.file_size(fs),
        .byte_data(bd),.byte_valid(bv),.byte_ready(br),.byte_last(bl),
        .pixel_valid(pv),.pixel_ready(pr),.pixel_addr(pa),.pixel_rgb(rgb),
        .done(done),.error(error),.error_code(ec),.busy(busy));
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        pr=!random_stalls || rng[1:0]!=0;
    end
    function automatic [23:0] color(input integer x,input integer y);
        color=(y*1920+x)^24'h5ac317;
    endfunction
    always @(posedge clk) if(rst_n) begin
        if(abort) stalled=0;
        else begin
            if(stalled && (!pv || {pa,rgb}!==held)) $fatal(1,"Scale output changed while stalled");
            stalled=pv&&!pr; held={pa,rgb};
            if(pv&&pr) begin
                if(pa>=N) $fatal(1,"Scale output address out of range: %0d",pa);
                fw=W;fh=H;
                if(FIT && sw*H>sh*W) fh=(sh*W/sw<1)?1:sh*W/sw;
                else if(FIT && sw*H<sh*W) fw=(sw*H/sh<1)?1:sw*H/sh;
                ox=(W-fw)/2;oy=(H-fh)/2;px=pa%W;py=pa/W;
                sx=(px-ox)*sw/fw;sy=(py-oy)*sh/fh;
                expected=(px<ox || px>=ox+fw || py<oy || py>=oy+fh)?24'd0:color(sx,sy);
                if(rgb!==expected) $fatal(1,"Scale %0dx%0d -> %0dx%0d address %0d: got %h expected %h (source %0d,%0d)",
                    sw,sh,W,H,pa,rgb,expected,sx,sy);
                seen[pa]=seen[pa]+1; outputs=outputs+1;
            end
            if(done) begin
                done_seen=1;
                if(outputs!=N) $fatal(1,"Scale done before all output pixels: %0d/%0d",outputs,N);
            end
            if(error) begin error_seen=1; code_seen=ec; end
        end
    end
    task automatic le32(input integer at,input integer val);
        for(integer j=0;j<4;j=j+1) bytes[at+j]=8'(val>>(8*j));
    endtask
    task automatic build(input integer iw,input integer ih,input bit td,input integer off,input integer dib,input integer tail);
        integer stride,p,y,x,logical_y; reg [23:0] c;
        sw=iw;sh=ih;stride=((iw*3+3)/4)*4;
        payload_end=off+stride*ih;fs=payload_end+tail;
        for(integer j=0;j<fs;j=j+1) bytes[j]=8'hcd;
        for(integer j=0;j<54;j=j+1) bytes[j]=0;
        bytes[0]="B";bytes[1]="M";le32(2,fs);le32(10,off);le32(14,dib);
        le32(18,iw);le32(22,td?-ih:ih);bytes[26]=1;bytes[28]=24;
        for(y=0;y<ih;y=y+1) for(x=0;x<iw;x=x+1) begin
            logical_y=td?y:ih-1-y;c=color(x,logical_y);p=off+y*stride+x*3;
            bytes[p]=c[7:0];bytes[p+1]=c[15:8];bytes[p+2]=c[23:16];
        end
    endtask
    task automatic begin_file;
        @(negedge clk);outputs=0;done_seen=0;error_seen=0;code_seen=0;
        for(integer j=0;j<N;j=j+1) seen[j]=0;
        start=1;@(negedge clk);start=0;
    endtask
    task automatic send_bytes(input integer count,input bit mark_eof,input bit bubbles);
        for(integer j=0;j<count;j=j+1) begin
            if(bubbles && rng[4:2]==0) @(negedge clk);
            bd=bytes[j];bv=1;bl=mark_eof && j==count-1;
            @(posedge clk);
            while(!br && !error_seen && !done_seen) @(posedge clk);
            @(negedge clk);bv=0;bl=0;
            if(error_seen || done_seen) break;
        end
    endtask
    task automatic run_file(input integer count,input integer expected_error,input bit mark_eof,input bit bubbles);
        integer wait_cycles;
        begin_file();send_bytes(count,mark_eof,bubbles);
        wait_cycles=0;
        while(!done_seen && !error_seen && wait_cycles<8*N+10000) begin
            @(negedge clk);wait_cycles=wait_cycles+1;
        end
        if(expected_error==0) begin
            if(error_seen || !done_seen || outputs!=N) $fatal(1,"Valid scale failed code=%0d outputs=%0d",code_seen,outputs);
            for(integer j=0;j<N;j=j+1) if(seen[j]!=1) $fatal(1,"Scale pixel %0d written %0d times",j,seen[j]);
        end else if(!error_seen || code_seen!=expected_error || done_seen)
            $fatal(1,"Scale error got=%0d expected=%0d done=%0d",code_seen,expected_error,done_seen);
        test_count=test_count+1;
        repeat(3) @(negedge clk);
    endtask
    initial begin
        #32;rst_n=1;
        build(3,2,0,54,40,0);run_file(payload_end,0,1,1);
        build(3,2,1,70,40,0);run_file(payload_end,0,1,1);
        build(3,7,0,54,40,0);run_file(payload_end,0,1,1);
        build(7,2,1,54,40,0);run_file(payload_end,0,1,1);
        build(1280,720,0,54,40,0);run_file(payload_end,0,1,1);
        $display("PASS native1280x720 fit: five complete frames, exact unique address coverage, RGB and black borders, portrait/wide/top-down/bottom-up/native input, random stalls");
        $finish;
    end
    initial begin #1000000000;$fatal(1,"Scale test timeout");end
endmodule
