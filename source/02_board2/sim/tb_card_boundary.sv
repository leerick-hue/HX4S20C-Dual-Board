`timescale 1ns/1ps
// Digital SD card at the actual SPI pins, including slow initialization.
module tb_card_boundary;
 reg clk=0,rst=1,miso=1,decode_clk=0,mem_clk=0;
 wire read_req;wire[31:0]lba;
 always #12.5 decode_clk=~decode_clk;
 always #10 mem_clk=~mem_clk;
 wire write_req,word_valid,swap_valid;wire[20:0]word_addr;wire[31:0]word_data;
 wire[3:0]source_error,source_state;reg write_ack=0,write_finish=0;
 integer words=0;reg[153599:0]seen=0;reg finished_once=0;
 always @(posedge decode_clk)begin
  if(rst)write_ack<=0;else write_ack<=write_req;
  if(!rst&&word_valid)begin
   if(word_addr>=153600||seen[word_addr])$fatal(1,"invalid/duplicate pixel word %0d",word_addr);
   if((^word_data)===1'bx)$fatal(1,"unknown pixel data");
   seen[word_addr]=1;words=words+1;
  end
 end
 always @(posedge mem_clk)begin
  write_finish<=0;
  if(!rst&&words==153600&&!finished_once)begin write_finish<=1;finished_once<=1;end
 end
 video_source source(.decode_clk(decode_clk),.decode_rst(rst),.sd_clk(clk),.sd_rst(rst),
  .mem_clk(mem_clk),.mem_rst(rst),.mem_init(1'b1),.sd_ready(ready),.freeze(1'b0),
  .sd_req(read_req),.sd_addr(lba),.sd_data(data),.sd_valid(valid),.sd_end(done),
  .write_req(write_req),.write_ack(write_ack),.write_finish(write_finish),.word_valid(word_valid),.word_ready(1'b1),
  .word_addr(word_addr),.word_data(word_data),.write_bank(),.frame_id(),.swap_valid(swap_valid),.swap_ready(1'b1),.swap_done(1'b0),
  .swap_bank(),.state_code(source_state),.error_code(source_error),.bridge_overflow(),
  .dropped_frames(),.committed_frames());
 reg[7:0]card_bytes[0:19967];integer offset=0,ends=0;
 initial $readmemh("card_boot.hex",card_bytes);
 always @(posedge clk)if(!rst&&done)ends=ends+1;
 always @(posedge decode_clk)if(!rst&&source_error!=0)
  $fatal(1,"HEADER_FAILURE error=%h state=%h CMD17=%0d bytes=%0d magic=%h count=%0d base=%0d",source_error,source_state,cmd17s,compared,source.player.header[0],source.player.byte_index,source.video_base);
 integer mode=0; // 0=SDHC, 1=SDSC v2, 2=SDSC v1, 3=SDHC missing first token
 always #5 clk=~clk;
 wire cs,sck,mosi,ready,valid,done;wire[7:0]data;
 sd_card_top dut(.clk(clk),.rst(rst),.SD_nCS(cs),.SD_DCLK(sck),.SD_MOSI(mosi),.SD_MISO(miso),
  .sd_init_done(ready),.sd_sec_read(read_req),.sd_sec_read_addr(lba),.sd_sec_read_data(data),
  .sd_sec_read_data_valid(valid),.sd_sec_read_end(done),.sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),
  .sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
 // Accelerate only the recovery timeout for fault injection, not SPI clocks.
 defparam dut.sd_card_cmd_m0.READ_TOKEN_TIMEOUT_CYCLES=2048;
 reg[7:0]queue[0:2047],cmd[0:5],rx=0,tx=8'hff;
 integer wp=0,rp=0,bits=0,command_bytes=0,cmd17s=0,cmd16s=0,compared=0;
 reg[31:0]arg;integer id;
 task push(input[7:0]b);begin queue[wp%2048]=b;wp=wp+1;end endtask
 task receive_byte(input[7:0]b);
  begin
   if(command_bytes==0)begin
    if(b[7:6]==2'b01)begin cmd[0]=b;command_bytes=1;end
   end else begin
    cmd[command_bytes]=b;command_bytes=command_bytes+1;
    if(command_bytes==6)begin
     command_bytes=0;id=cmd[0]&63;arg={cmd[1],cmd[2],cmd[3],cmd[4]};
     case(id)
      0:begin if(cmd[5]!=8'h95)$fatal(1,"CMD0 CRC");push(1);end
      8:begin
       if(arg!=32'h1aa||cmd[5]!=8'h87)$fatal(1,"CMD8");
       if(mode==2)push(5);else begin push(1);push(0);push(0);push(1);push(8'haa);end
      end
      55:push(1);
      41:begin
       if(arg!==(mode==2?32'd0:32'h40000000))$fatal(1,"ACMD41 argument");push(0);
      end
      58:begin push(0);push((mode==0||mode==3)?8'hc0:8'h80);push(0);push(0);push(0);end
      16:begin if(arg!=512)$fatal(1,"block size");cmd16s=cmd16s+1;push(0);end
      17:begin
       $display("CARD_CMD17 n=%0d address=%0d requested=%0d time=%t",cmd17s+1,arg,lba,$time);
       cmd17s=cmd17s+1;push(0);push(8'hff);push(8'hfe);
       if(arg==0)offset=0;
       else if(arg==18569)offset=512;
       else if(arg==18570)offset=1024;
       else if(arg>=18580&&arg<18616)offset=1536+(arg-18580)*512;
       else $fatal(1,"Unexpected address %0d",arg);
       for(integer k=0;k<512;k=k+1)push(card_bytes[offset+k]);
       push(8'hff);push(8'hff);
      end
      default:$fatal(1,"unexpected command %0d",id);
     endcase
    end
   end
  end
 endtask
 always @(posedge cs or posedge rst)begin
  bits=0;command_bytes=0;rx=0;tx=8'hff;wp=0;rp=0;miso=1;
 end
 always @(negedge sck)if(!cs&&!rst)begin
  if(bits==0)begin if(rp<wp)begin tx=queue[rp%2048];rp=rp+1;end else tx=8'hff;end
  miso=tx[7-bits];
 end
 always @(posedge sck)if(!cs&&!rst)begin
  rx={rx[6:0],mosi};bits=bits+1;
  if(bits==8)begin bits=0;receive_byte(rx);end
 end

 always @(posedge clk)if(!rst&&valid)compared=compared+1;
 initial begin
  repeat(20)@(negedge clk);rst=0;
  wait(swap_valid);repeat(200)@(negedge clk);
  if(cmd17s!=39||ends!=39||compared!=19968||source.player.media_ready!==1'b1||words!=153600||(&seen)!==1'b1)
   $fatal(1,"Request mismatch commands=%0d ends=%0d bytes=%0d",cmd17s,ends,compared);
  $display("PASS card_boundary actual_SPI_CDC_catalog_player JPEG_RGB565_first_frame words=%0d sectors=%0d bytes=%0d",words,ends,compared);$finish;
 end
 initial begin #50000000;$fatal(1,"boundary timeout");end
endmodule
