`timescale 1ns/1ps
// Digital SD card at the actual SPI pins, including slow initialization.
module tb_spi_read;
 reg clk=0,rst=1,read_req=0,miso=1;reg[31:0]lba=7;
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
       if(arg!==((mode==0||mode==3)?lba:lba*512))$fatal(1,"address units mode=%0d arg=%0d",mode,arg);
       cmd17s=cmd17s+1;push(0);
       if(!(mode==3&&cmd17s==1))begin
        push(8'hff);push(8'hfe);
        for(integer k=0;k<512;k=k+1)push((k^lba)&255);
        push(8'hff);push(8'hff);
       end
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
 always @(posedge clk)if(!rst&&valid)begin
  if(data!==8'((compared^lba)&255))$fatal(1,"SPI data index=%0d got=%h",compared,data);
  compared=compared+1;
 end
 initial begin
  for(integer m=0;m<4;m=m+1)begin
   mode=m;rst=1;read_req=0;compared=0;cmd17s=0;cmd16s=0;
   repeat(20)@(negedge clk);rst=0;wait(ready);@(negedge clk);read_req=1;
   wait(done);@(negedge clk);read_req=0;repeat(20)@(negedge clk);
   if(compared!=512||cmd17s!=(mode==3?2:1)||cmd16s!=((mode==0||mode==3)?0:1))$fatal(1,"incomplete SPI test mode=%0d samples=%0d",mode,compared);
   if(dut.sd_card_cmd_m0.read_timeout_count!=(mode==3?1:0))$fatal(1,"timeout count");
   $display("SPI_PASS mode=%0d bytes=%0d CMD17=%0d CMD16=%0d",mode,compared,cmd17s,cmd16s);
  end
  $display("PASS spi_read actual_SPI_pins SDHC_SDSCv2_SDSCv1 2048bytes production_clocks_dividers=1 token_timeout_retry=1 shortened_timeout2048");$finish;
 end
 initial begin #50000000;$fatal(1,"SPI timeout mode=%0d ready=%b state=%0d cmd=%0d count=%0d",mode,ready,dut.sd_card_cmd_m0.state,id,compared);end
endmodule
