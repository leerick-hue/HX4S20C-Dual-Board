`timescale 1ns/1ps
module tb_jpeg_decode;
  reg clk=0; always #12.5 clk=~clk; // 40 MHz; all performance results also retain cycle counts.
  reg rst=1;
  reg in_valid=0, in_last=0, out_accept=1;
  reg [31:0] in_data=0;
  wire in_accept, out_valid, idle;
  wire [15:0] width,height,x,y;
  wire [7:0] r,g,b;
  jpeg_core #(.SUPPORT_WRITABLE_DHT(0)) dut (
    .clk_i(clk),.rst_i(rst),.inport_valid_i(in_valid),.inport_data_i(in_data),
    .inport_strb_i(4'hf),.inport_last_i(in_last),.inport_accept_o(in_accept),
    .outport_accept_i(out_accept),.outport_valid_o(out_valid),.outport_width_o(width),
    .outport_height_o(height),.outport_pixel_x_o(x),.outport_pixel_y_o(y),
    .outport_pixel_r_o(r),.outport_pixel_g_o(g),.outport_pixel_b_o(b),.idle_o(idle));
  reg [31:0] words[0:131071];
  reg [23:0] pixels[0:307199];
  reg seen[0:307199];
  integer cycles=0, count=0, first_pixel=0, last_pixel=0, frame_start=0;
  integer w,h,nwords,repeats,gap,stall,frame,i,j,fh,unused,accepted_words=0;
  integer output_stall_cycles=0;
  string hexfile, outfile;
  reg active=0, stalled_previous=0;
  reg [87:0] held_output;
  wire [87:0] packed_output={width,height,x,y,r,g,b};
  always @(negedge clk) begin
    if (stall != 0) out_accept = ((cycles % 97) < 61) && ((cycles % 509) > 7);
    else out_accept=1;
  end
  always @(posedge clk) begin
    cycles=cycles+1;
    if (!rst) begin
      if (stalled_previous && (!out_valid || packed_output !== held_output))
        $fatal(1,"output changed while stalled at cycle %0d",cycles);
      stalled_previous = out_valid && !out_accept;
      if (stalled_previous) held_output=packed_output;
      if (in_valid && in_accept) accepted_words=accepted_words+1;
      if (out_valid && !out_accept) output_stall_cycles=output_stall_cycles+1;
      if (out_valid && out_accept) begin
        if (!active) $fatal(1,"unexpected pixel outside a frame");
        if (width!=w || height!=h) $fatal(1,"wrong geometry %0dx%0d",width,height);
        if (x>=w || y>=h) $fatal(1,"out of range pixel %0d,%0d after %0d pixels width=%0d height=%0d",x,y,count,width,height);
        if (seen[y*w+x]) $fatal(1,"duplicate pixel %0d,%0d",x,y);
        seen[y*w+x]=1;
        pixels[y*w+x]={r,g,b};
        if (count==0) first_pixel=cycles;
        count=count+1;
        last_pixel=cycles;
      end
    end
    if (cycles>12000000) $fatal(1,"timeout: pixels=%0d expected=%0d idle=%b inputwords=%0d",count,w*h,idle,accepted_words);
  end
  initial begin
    unused=$value$plusargs("HEX=%s",hexfile);
    unused=$value$plusargs("W=%d",w);
    unused=$value$plusargs("H=%d",h);
    unused=$value$plusargs("WORDS=%d",nwords);
    unused=$value$plusargs("REPEATS=%d",repeats);
    unused=$value$plusargs("GAP=%d",gap);
    unused=$value$plusargs("STALL=%d",stall);
    if (w<=0 || h<=0 || nwords<=0 || repeats<=0) $fatal(1,"invalid plusargs");
    $readmemh(hexfile,words,0,nwords-1);
    repeat(10) @(negedge clk);
    rst=0;
    repeat(4) @(negedge clk);
    for(frame=0;frame<repeats;frame=frame+1) begin
      for(j=0;j<w*h;j=j+1) begin seen[j]=0; pixels[j]=24'hxxxxxx; end
      count=0; accepted_words=0; output_stall_cycles=0; active=1; frame_start=cycles;
      for(i=0;i<nwords;i=i+1) begin
        in_data=words[i]; in_last=(i==nwords-1); in_valid=1;
        @(posedge clk);
        while (!in_accept) @(posedge clk);
        @(negedge clk);
        in_valid=0; in_last=0;
        repeat(gap) @(negedge clk);
      end
      wait(count==w*h);
      @(negedge clk);
      wait(idle);
      repeat(64) @(negedge clk);
      if(count!=w*h || accepted_words!=nwords) $fatal(1,"count mismatch");
      for(j=0;j<w*h;j=j+1) if(!seen[j]) $fatal(1,"missing pixel %0d",j);
      outfile=$sformatf("decoded_%0d.hex",frame);
      fh=$fopen(outfile,"w");
      if(!fh) $fatal(1,"cannot create decoded file");
      for(j=0;j<w*h;j=j+1) $fdisplay(fh,"%06x",pixels[j]);
      $fclose(fh);
      $display("METRIC frame=%0d cycles=%0d first=%0d last=%0d accepted_words=%0d output_stall_cycles=%0d pixels=%0d",frame,last_pixel-frame_start,first_pixel-frame_start,last_pixel-frame_start,accepted_words,output_stall_cycles,count);
      active=0;
      repeat(30) @(negedge clk);
    end
    $display("PASS jpeg_decode coverage, geometry, unique coordinates, resetless frames and stalled-output stability");
    $finish;
  end
endmodule
