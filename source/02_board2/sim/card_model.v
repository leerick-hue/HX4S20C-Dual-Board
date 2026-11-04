`timescale 1ns/1ps
// Test-only sector service; explicitly substitutes the physical SPI/card front end.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=0,
 parameter CARD_BYTES=153088)(
 input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output reg sd_init_done=0,input sd_sec_read,input[31:0]sd_sec_read_addr,
 output reg[7:0]sd_sec_read_data=0,output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,
 input sd_sec_write,input[31:0]sd_sec_write_addr,input[7:0]sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
 assign SD_nCS=1,SD_DCLK=0,SD_MOSI=1,sd_sec_write_data_req=0,sd_sec_write_end=0;
 reg[7:0]image[0:CARD_BYTES-1];reg[31:0]saved;
 integer state=0,index=0,gap=0;
 initial $readmemh("../sim/fixtures/fps30.hex",image);
 always @(negedge clk)begin
  sd_sec_read_data_valid=0;sd_sec_read_end=0;
  if(rst)begin sd_init_done=0;state=0;index=0;gap=0;end
  else begin
   if(sd_sec_write)$fatal(1,"unexpected card write");
   sd_init_done=1;
   case(state)
    0:if(sd_sec_read)begin
     if(sd_sec_read_addr*512+511>=CARD_BYTES)$fatal(1,"invalid sector");
     saved=sd_sec_read_addr;index=0;gap=0;state=1;
    end
    1:begin
     if(!sd_sec_read||sd_sec_read_addr!==saved)$fatal(1,"unstable sector request");
     gap=gap+1;
     if(gap==36)begin
      gap=0;sd_sec_read_data=image[saved*512+index];sd_sec_read_data_valid=1;index=index+1;
      if(index==512)state=2;
     end
    end
    2:begin sd_sec_read_end=1;state=3;end
    3:if(!sd_sec_read)state=0;
   endcase
  end
 end
endmodule
