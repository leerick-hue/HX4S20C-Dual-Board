`timescale 1ns/1ps
// Isolate capture selection with tagged, preloaded memory. This does not test
// writes or establish silicon CAS latency; it uses the inherited early model.
module tb_read_capture_contract;
 reg clk=0,rst=1; always #10 clk=~clk;
 wire shifted; assign #8.5 shifted=clk;
 reg rd=0; reg [20:0] ra=0;
 wire init,refv,busy,rv; wire [31:0] rdata;
 reg [31:0] previous;
 integer selected=0,raw_bad=0,raw_unknown=0,burst_count=0,base=0;
 function automatic [31:0] tag(input integer address);
  tag=32'h9147a36d ^ (address*32'h10301);
 endfunction
 sdram dut(.Clk(clk),.Clk_sft(shifted),.Rst(rst),
  .Sdr_init_done(init),.Sdr_init_ref_vld(refv),.Sdr_busy(busy),
  .App_wr_en(1'b0),.App_wr_addr(21'd0),.App_wr_dm(4'd0),.App_wr_din(32'd0),
  .App_rd_en(rd),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rdata));
 always @(posedge clk) begin
  previous<=rdata;
  if(!rst && rv)begin
   if(burst_count>=64)$fatal(1,"extra response");
   if(previous!==tag(base+burst_count))
    $fatal(1,"selected capture n=%0d addr=%0d got=%h expected=%h raw=%h",
     selected,base+burst_count,previous,tag(base+burst_count),rdata);
   if(rdata!==tag(base+burst_count))raw_bad=raw_bad+1;
   if(^rdata===1'bx)raw_unknown=raw_unknown+1;
   burst_count=burst_count+1;selected=selected+1;
  end
 end
 task burst(input integer address);
  begin
   wait(!busy);repeat(10)@(negedge clk);
   base=address;burst_count=0;
   for(integer i=0;i<64;i=i+1)begin
    @(negedge clk);rd=1;ra=address+i;
   end
   @(negedge clk);rd=0;
   wait(burst_count==64);wait(!busy);repeat(10)@(negedge clk);
  end
 endtask
 initial begin
  repeat(12)@(negedge clk);rst=0;wait(init);wait(!busy);
  // The controller interleaves banks per BL4: row=App[20:10], bank=App[3:2],
  // column={App[9:4],App[1:0]}. The retained model stores row/bank/column.
  for(integer i=115200;i<116224;i=i+1)
   dut.sdram.storage.memory[((i>>10)*1024)+(((i>>2)&3)*256)+(((i>>4)&63)*4)+(i&3)]=tag(i);
  burst(115200);burst(115392);burst(115456);burst(115968);
  if(selected!=256 || raw_bad==0 || raw_unknown==0)$fatal(1,"missing coverage");
  $display("PASS read_capture selected=%0d raw_mismatch=%0d raw_unknown=%0d preloaded_read_only=1 early_return_model=1 no_silicon_timing_claim=1",selected,raw_bad,raw_unknown);
  $finish;
 end
 initial begin #5000000;$fatal(1,"read capture timeout");end
endmodule
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input[10:0]addr,
 input[1:0]ba,inout[31:0]dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 sdram_retention_model #(.READ_LATENCY_CYCLES(2)) storage(
  .clk(clk),.rst(tb_read_capture_contract.rst),.ras(ras_n),.cas(cas_n),.we(we_n),
  .ba(ba),.addr(addr),.dm({dm3,dm2,dm1,dm0}),.dq(dq),.writes(),.reads());
 always @(posedge storage.memory_clk)
  if(!tb_read_capture_contract.rst && {ras_n,cas_n,we_n}==3'b101)
   $display("READ_COORD bank=%0d row=%0d col=%0d value=%h",ba,storage.row[ba],addr[7:0],storage.memory[((storage.row[ba]*4+ba)*256)+addr[7:0]]);
endmodule
