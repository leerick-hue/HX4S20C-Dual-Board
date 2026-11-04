`timescale 1ns/1ps
module tb_video_path;
 parameter integer CARD_BYTES=1048576;
 parameter integer RATE_TEST=0;
 parameter integer SECTOR_FIXED_US=0,SECTOR_JITTER_US=50;
 localparam integer FRAME_WORDS=153600;
 localparam integer READ_WORDS=153600;
 localparam integer XOFF=320,YOFF=120,IMGW=640,IMGH=480;
 reg mem_clk=0,pixel_clk=0,decode_clk=0,sd_clk=0,rst=1,freeze=0;
 always #10 mem_clk=~mem_clk;
 always #6.734006734 pixel_clk=~pixel_clk;
 always #12.5 decode_clk=~decode_clk;
 always #5 sd_clk=~sd_clk;
 wire shifted;assign #8.5 shifted=mem_clk;
 wire hn,vn,dn,h,v,d,initialized,valid;
 wire[23:0]rgb;wire[15:0]id;wire[31:0]underflows,dropped,committed;
 wire[3:0]state,error;wire overflow,req;wire[31:0]addr;
 reg ready=0,byte_valid=0,byte_end=0;reg[7:0]byte_data=0;
 native_video_timing #(.WIDTH(1280),.HEIGHT(720),.HSA(40),.HBP(220),.HFP(110),
  .VSA(5),.VBP(20),.VFP(5),.HS_POLARITY(1),.VS_POLARITY(1)) raster(
  .clk(pixel_clk),.rst(rst),.hs(hn),.vs(vn),.de(dn));
 video_path dut(.mem_clk(mem_clk),.mem_clk_shift(shifted),.mem_rst(rst),
  .pixel_clk(pixel_clk),.pixel_rst(rst),.hs_native(hn),.vs_native(vn),.de_native(dn),
  .decode_clk(decode_clk),.decode_rst(rst),.sd_clk(sd_clk),.sd_rst(rst),
  .sd_ready(ready),.sd_req(req),.sd_addr(addr),.sd_data(byte_data),.sd_valid(byte_valid),.sd_end(byte_end),
  .player_state(state),.player_error(error),.bridge_overflow(overflow),.dropped_frames(dropped),.committed_frames(committed),
  .freeze(freeze),.hs(h),.vs(v),.de(d),.rgb(rgb),.init_done(initialized),
  .display_valid(valid),.display_id(id),.underruns(underflows));
 reg[7:0]image[0:CARD_BYTES-1];
 reg[31:0]gold0[0:153599],gold1[0:153599],gold2[0:153599];
 reg seen[0:153599];
 integer server=0,byte_no=0,gap=0,requests=0,start_gap=0;reg[15:0]jitter_lfsr=16'h4a31;reg[31:0]saved_addr;
 // Sector service at physical controller's best-case byte spacing. This model
 // does not implement card initialization/SPI wires or a measured card latency.
 always @(negedge sd_clk)begin
  byte_valid=0;byte_end=0;
  if(rst)begin server=0;byte_no=0;gap=0;ready=0;end
  else begin
   ready=1;
   case(server)
    0:if(req)begin
     if(addr*512+511>=CARD_BYTES)$fatal(1,"out-of-card request %0d",addr);
     saved_addr=addr;byte_no=0;gap=0;server=RATE_TEST?4:1;requests=requests+1;
     jitter_lfsr={jitter_lfsr[14:0],jitter_lfsr[15]^jitter_lfsr[13]^jitter_lfsr[12]^jitter_lfsr[10]};
     start_gap=SECTOR_FIXED_US*100+(SECTOR_JITTER_US?jitter_lfsr%(SECTOR_JITTER_US*100+1):0);
    end
    1:begin
     if(!req||addr!==saved_addr)$fatal(1,"request not held through sector");
     gap=gap+1;
     if(gap==36)begin
      gap=0;byte_data=image[saved_addr*512+byte_no];byte_valid=1;byte_no=byte_no+1;
      if(byte_no==512)server=2;
     end
    end
    2:begin byte_end=1;server=3;end
    3:if(!req)server=0;
    4:begin
     if(!req||addr!==saved_addr)$fatal(1,"request changed during token latency");
     if(start_gap==0)server=1;else start_gap=start_gap-1;
    end
   endcase
  end
 end
 function automatic[31:0]gold_word(input integer asset,index);
  case(asset)0:gold_word=gold0[index];1:gold_word=gold1[index];2:gold_word=gold2[index];default:gold_word=32'hx;endcase
 endfunction
 function automatic[23:0]gold_rgb(input integer asset,index);
  reg[31:0]w;reg[15:0]c;
  begin w=gold_word(asset,index/2);c=(index%2)?w[31:16]:w[15:0];
   gold_rgb={c[15:11],c[15:13],c[10:5],c[10:9],c[4:0],c[4:2]};end
 endfunction
 integer writes=0,write_total=0,index,asset=0,swaps=0,content_errors=0,wr_lo=0,wr_hi=0;
 // Native-coordinate reference model of storage and scanout. The decoder's own pixel stream is
 // recorded as source words, so every stored word and every displayed pixel is
 // predicted from what the decoder actually produced. Solid-colour fixtures on
 // their own cannot catch half swaps, row scrambling or a wrong scale grouping.
 reg [31:0]src_model[0:1][0:153599];
 reg [15:0]model_even;
 reg        bad_seen=0;
 reg [19:0] bad_index=0;
 reg [19:0] model_idx=0;
 reg [31:0] bad_got=0,bad_exp=0;
 function automatic[23:0]rgb565_to24(input[15:0]c);
  rgb565_to24={c[15:11],c[15:13],c[10:5],c[10:9],c[4:0],c[4:2]};
 endfunction
 always @(posedge decode_clk)if(!rst)begin
  if(dut.source.pixel_valid&&dut.source.pixel_ready)begin
   reg[15:0]enc;
   enc={dut.source.pixel_rgb[23:19],dut.source.pixel_rgb[15:10],dut.source.pixel_rgb[7:3]};
   if(!dut.source.player_pixel_addr[0])model_even=enc;
   else begin
    // The JPEG core emits in MCU-block order, so player_pixel_addr is a stream
    // counter, not a raster address.  The buffer position is derived from the
    // pixel's own column/row, so the model keys on the same coordinates.
    model_idx=dut.source.player.jpg_y*320+(dut.source.player.jpg_x>>1);
    src_model[dut.source.write_bank][model_idx]={enc,model_even};
    if({enc,model_even}!==gold_word(asset,model_idx))begin
     content_errors=content_errors+1;
     if(!bad_seen)begin
      bad_seen=1;
      bad_index=model_idx;
      bad_got={enc,model_even};
      bad_exp=gold_word(asset,model_idx);
     end
    end
   end
  end
 end
 reg old_req=0;reg [31:0]expected_word;
 always @(posedge decode_clk)if(!rst)begin
  old_req<=dut.write_req;
  if(dut.write_req&&!old_req)begin
   writes=0;asset=dut.source.player.frame_index;
   for(integer n=0;n<READ_WORDS;n=n+1)seen[n]=0;
  end
  if(error!=0||overflow)$fatal(1,"error=%0d state=%0d overflow=%b",error,state,overflow);
 end
 always @(posedge mem_clk)if(!rst)begin
  if(dut.app_wr)begin
   index=dut.wr_addr-(dut.write_bank?153600:0);
   if(index<0||index>=READ_WORDS||seen[index])$fatal(1,"duplicate/range address %0d",index);
   expected_word=gold_word(asset,index);
   if(dut.wr_data!==expected_word)$fatal(1,"JPEG WRITE asset=%0d word=%0d got=%h expected=%h dst_row=%0d dst_col=%0d",asset,index,dut.wr_data,expected_word,index/320,index%320);
   if(valid&&dut.display_bank==dut.write_bank)$fatal(1,"overwriting front buffer");
   if(writes==0)begin wr_lo=dut.wr_addr;wr_hi=dut.wr_addr;end
   else begin if(dut.wr_addr<wr_lo)wr_lo=dut.wr_addr;if(dut.wr_addr>wr_hi)wr_hi=dut.wr_addr;end
   seen[index]=1;writes=writes+1;write_total=write_total+1;
  end
  if(dut.rd_valid&&dut.dma.read_buf.full_flag)$fatal(1,"read overflow");
 end
 integer x=0,y=0,compared=0,frames=0,shown_asset=0,held_frames=0;
 integer asset_mask=0;reg in_line=0,was_v=0;reg[23:0]expected_rgb;
 reg freeze_previous=0;integer frozen_bank=0,frozen_asset=0,freeze_checks=0,resume_seen=0;
 realtime first_swap=0,last_swap=0;
 always @(posedge pixel_clk)if(!rst)begin
  if(dut.switched)begin
   if(writes!=FRAME_WORDS)$fatal(1,"swap before all writes %0d expected %0d",writes,FRAME_WORDS);
   if(d&& !v)$fatal(1,"swap during active pixels");
   if(RATE_TEST && asset!=(swaps%3))$fatal(1,"rate frame sequence skipped expected=%0d got=%0d",swaps%3,asset);
   shown_asset=asset;swaps=swaps+1;asset_mask=asset_mask|(1<<asset);
   if(swaps==1)first_swap=$realtime;last_swap=$realtime;
   $display("JPEG_SWAP n=%0d asset=%0d time_ns=%0t dropped=%0d wb=%b wr_addr_range=%0d..%0d",swaps,asset,$time,dropped,dut.write_bank,wr_lo,wr_hi);
  end
  if(v)begin x=0;y=0;in_line=0;end
  else if(d)begin
   expected_rgb=0;
   if(valid&&x>=XOFF&&x<XOFF+IMGW&&y>=YOFF&&y<YOFF+IMGH)begin
    integer sx,sy;reg[31:0]model_word;
    sx=x-XOFF; sy=y-YOFF;
    model_word=gold_word(shown_asset,sy*320+(sx>>1));
    // RGB565 words store the even source pixel in the low half.
    expected_rgb=rgb565_to24(sx[0]?model_word[31:16]:model_word[15:0]);
   end
   if(content_errors!=0)$fatal(1,"decoded colour model mismatches %0d first idx=%0d (x=%0d y=%0d) got=%h expected=%h",content_errors,bad_index,(bad_index%320)*2,bad_index/320,bad_got,bad_exp);
   if(rgb!==expected_rgb)$fatal(1,"JPEG RGB asset=%0d x=%0d y=%0d got=%h expected=%h",shown_asset,x,y,rgb,expected_rgb);
   if(valid&&id!==16'(shown_asset))$fatal(1,"metadata mismatch");
   if(valid)compared=compared+1;
   x=x+1;in_line=1;
  end else begin x=0;if(in_line)begin y=y+1;in_line=0;end end
  if(v&&!was_v&&compared!=0)begin
   if(compared!=921600||underflows!=0)$fatal(1,"scan count %0d underflows=%0d",compared,underflows);
   frames=frames+1;compared=0;
   // Freeze after the first complete picture, then resume the same buffered decode.
   if(held_frames==0 && !RATE_TEST)begin freeze=1;held_frames=1;end
   else if(freeze)begin held_frames=held_frames+1;if(held_frames==3)freeze=0;end
   $display("JPEG_FRAME n=%0d asset=%0d checked=921600 freeze=%b",frames,shown_asset,freeze);
   // A PASS line must not be printed when the content comparison counted errors:
   // run_video.py only greps for the PASS string, so an ungated display would
   // report passed=true with a non-zero error count.
   if(content_errors!=0)$fatal(1,"content errors %0d at frame %0d",content_errors,frames);
   if(RATE_TEST && swaps>=6)begin
    if(dropped!=0 || underflows!=0 || asset_mask!=7)$fatal(1,"rate drops=%0d underruns=%0d mask=%0d",dropped,underflows,asset_mask);
    if((swaps-1)*1.0e9/(last_swap-first_swap)<14.7)$fatal(1,"rate below target fps=%f",(swaps-1)*1.0e9/(last_swap-first_swap));
    $display("PASS video_path_rate swaps=%0d intervals=%0d fps=%f dropped=%0d underruns=%0d late=%0d jitter_us=%0d fixed_us=%0d",swaps,swaps-1,(swaps-1)*1.0e9/(last_swap-first_swap),dropped,underflows,dut.source.player.late_frames,SECTOR_JITTER_US,SECTOR_FIXED_US);$finish;
   end
   if(!RATE_TEST&&swaps>=4&&asset_mask==7&&shown_asset==0&&resume_seen&&freeze_checks>1000)begin
    $display("PASS video_path swaps=%0d displayed_frames=%0d pixels=%0d writes=%0d sectors=%0d drops=%0d content_errors=%0d freeze_resume=1 loop=1 actual_controller=1",swaps,frames,frames*921600,write_total,requests,dropped,content_errors);$finish;
   end
  end
  was_v=v;
 end
 initial begin
  $readmemh("../sim/fixtures/card480.hex",image);
  $readmemh("../sim/fixtures/video0_640x480.hex",gold0);
  $readmemh("../sim/fixtures/video1_640x480.hex",gold1);
  $readmemh("../sim/fixtures/video2_640x480.hex",gold2);
  repeat(12)@(negedge mem_clk);rst=0;
 end

 integer decode_cycles=0,decode_old_state=0;
 always @(posedge decode_clk)if(!rst)begin
  if(dut.source.player.state==8 && decode_old_state!=8)decode_cycles=0;
  if(dut.source.player.state==8 || dut.source.player.state==9)decode_cycles=decode_cycles+1;
  if(dut.source.player.state==9 && decode_old_state==8)$display("DECODE_DRAIN frame=%0d cycles=%0d ms=%f",asset,decode_cycles,decode_cycles/40000.0);
  if(dut.source.player.state==10 && decode_old_state==9)$display("DECODE_DUE frame=%0d cycles=%0d ms=%f late=%0d",asset,decode_cycles,decode_cycles/40000.0,dut.source.player.late_frames);
  decode_old_state=dut.source.player.state;
 end
 integer app_beat=0,source_beat=0;reg[20:0]app_base,source_base;
 always @(posedge decode_clk)if(!rst && dut.word_valid && dut.word_ready)begin
  if(source_beat==0)begin
   source_base=dut.word_addr;
   if(source_base[1:0]!=0)$fatal(1,"unaligned native source BL4");
  end else if(dut.word_addr!=source_base+source_beat)$fatal(1,"noncontiguous native source BL4");
  source_beat=(source_beat+1)%4;
 end
 always @(posedge mem_clk)if(!rst && dut.app_wr)begin
  if(app_beat==0)begin app_base=dut.wr_addr;if(app_base[1:0]!=0)$fatal(1,"unaligned App BL4");end
  else if(dut.wr_addr!=app_base+app_beat)$fatal(1,"noncontiguous App BL4");
  app_beat=(app_beat+1)%4;
 end
 always @(posedge pixel_clk)if(!rst)begin
  if(freeze && !freeze_previous)begin frozen_bank=dut.display_bank;frozen_asset=shown_asset;end
  if(freeze && freeze_previous)begin
   if(dut.display_bank!=frozen_bank || shown_asset!=frozen_asset)$fatal(1,"front bank changed while frozen");
   freeze_checks=freeze_checks+1;
  end
  if(!freeze && freeze_previous)resume_seen=1;
  freeze_previous=freeze;
 end

 integer rd_req=0,rd_ret=0,wr_app=0;
 always @(posedge mem_clk)if(!rst)begin
  if(dut.app_rd)rd_req=rd_req+1;
  if(dut.rd_valid)rd_ret=rd_ret+1;
  if(dut.app_wr)wr_app=wr_app+1;
 end
 // Which address did the SDRAM return unknown data for, and was it written?
 reg [20:0] addr_hist [0:7];
 integer aidx=0, xrd=0, xrd_dbg=0;
 always @(posedge mem_clk)begin
  addr_hist[aidx[2:0]]<=dut.rd_addr; aidx=aidx+1;
  if(!rst && dut.rd_valid && (^dut.rd_data===1'bx) && xrd<6)begin
    integer k,ai; k=(aidx-3)&7; ai=addr_hist[k]-153600;
    $display("XSDRAM t=%0t data=%h addr_of_response~=%0d logical=%0d seen=%b wr_total=%0d rdcnt=%0d",
      $time,dut.rd_data,addr_hist[k],ai,(ai>=0&&ai<153600)?seen[ai]:1'bx,
      write_total,dut.dma.frame_fifo_read_m0.read_cnt);
    xrd=xrd+1;
  end
 end
 initial begin for(integer t=1;t<=700;t++)begin #1000000;
  $display("HB t=%0dms swaps=%0d writes=%0d wr_total=%0d state=%0d err=%0d drops=%0d comp=%0d rreq=%0d rret=%0d wapp=%0d rdfifo=%0d rdusedw=%0d busy=%b idlem=%b ordb=%b owrb=%b empty=%b und=%0d",
   t,swaps,writes,write_total,state,error,dropped,compared,rd_req,rd_ret,wr_app,
   dut.dma.rdusedw,dut.dma.wrusedw,dut.busy,dut.dma.read_idle_mem,dut.dma.O_rd_busy,dut.dma.O_wr_busy,
   dut.fifo_empty,underflows,dut.dma.frame_fifo_read_m0.state,dut.dma.frame_fifo_read_m0.read_cnt,
   dut.dma.frame_fifo_read_m0.read_len_latch);
 end end
 initial begin #700000000;$fatal(1,"timeout state=%0d err=%0d writes=%0d swaps=%0d mask=%h",state,error,writes,swaps,asset_mask);end
endmodule
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input[10:0]addr,
 input[1:0]ba,inout[31:0]dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 sdram_retention_model #(.READ_LATENCY_CYCLES(2)) storage(.clk(clk),.rst(tb_video_path.rst),
  .ras(ras_n),.cas(cas_n),.we(we_n),.ba(ba),.addr(addr),.dm({dm3,dm2,dm1,dm0}),.dq(dq),.writes(),.reads());
endmodule
