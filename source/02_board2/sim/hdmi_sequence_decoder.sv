`timescale 1ns/1ps
// Independent TERC4 decoder plus FIFO scoreboard for varying stereo PCM.
// This is a new test-only derivative of hdmi_packet_decoder.sv; production
// sources and the original constant-sample tests are intentionally unchanged.
module hdmi_sequence_decoder #(parameter CTS_MIN=74206,CTS_MAX=74209)(
 input clk,rst,input [9:0] c0,c1,c2,
 input audio_in_valid,input [23:0] audio_in_left,audio_in_right,
 output integer inputs=0,samples=0,audio_packets=0,acr_packets=0,
 output integer aif_packets=0,avi_packets=0,avmute_clears=0,
 output integer last_n=0,last_cts=0,queued=0,
 output integer gcp_packets=0,avmute_sets=0,
 output reg avmuted=1
);
 localparam QUEUE_DEPTH=8192;
 reg [47:0] expected[0:QUEUE_DEPTH-1];
 integer wr=0,rd=0;
 function automatic integer terc(input [9:0] w);
  case(w)
   10'h29c:terc=0;10'h263:terc=1;10'h2e4:terc=2;10'h2e2:terc=3;
   10'h171:terc=4;10'h11e:terc=5;10'h18e:terc=6;10'h13c:terc=7;
   10'h2cc:terc=8;10'h139:terc=9;10'h19c:terc=10;10'h2c6:terc=11;
   10'h28e:terc=12;10'h271:terc=13;10'h163:terc=14;10'h2c3:terc=15;
   default:terc=-1;
  endcase
 endfunction
 function automatic [7:0] ecc24(input [23:0] data);
  reg [7:0] e;integer i;
  begin e=0;for(i=0;i<24;i=i+1)e=(e>>1)^((e[0]^data[i])?8'h83:8'h00);ecc24=e;end
 endfunction
 function automatic [7:0] ecc56(input [55:0] data);
  reg [7:0] e;integer i;
  begin e=0;for(i=0;i<56;i=i+1)e=(e>>1)^((e[0]^data[i])?8'h83:8'h00);ecc56=e;end
 endfunction
 reg [31:0] header;
 reg [63:0] subpacket[0:3];
 reg [7:0] pb[0:27];
 integer state=0,preamble=0,guards=0,index=0,d0,d1,d2,j,b,typ,checksum,length;
 wire gb=(c1==10'h133 && c2==10'h133 && terc(c0)>=12);
 task automatic complete_packet;
  begin
   typ=header[7:0];
   if(header[31:24]!==ecc24(header[23:0]))
    $fatal(1,"sequence header BCH type=%h",typ);
   for(j=0;j<4;j=j+1)begin
    if(subpacket[j][63:56]!==ecc56(subpacket[j][55:0]))
     $fatal(1,"sequence body BCH type=%h sub=%0d",typ,j);
    for(b=0;b<7;b=b+1)pb[j*7+b]=subpacket[j][8*b+:8];
   end
   case(typ)
    8'h01:begin
     acr_packets=acr_packets+1;
     last_cts={subpacket[0][11:8],subpacket[0][23:16],subpacket[0][31:24]};
     last_n={subpacket[0][35:32],subpacket[0][47:40],subpacket[0][55:48]};
     if(last_n!=6144)$fatal(1,"sequence wrong N=%0d",last_n);
     if(last_cts<CTS_MIN || last_cts>CTS_MAX)
      $fatal(1,"sequence measured PLL CTS=%0d",last_cts);
     for(j=1;j<4;j=j+1)if(subpacket[j][55:0]!==subpacket[0][55:0])
      $fatal(1,"sequence ACR copies differ");
    end
    8'h02:begin
     audio_packets=audio_packets+1;
     for(j=0;j<4;j=j+1)if(header[8+j])begin
      if(rd==wr)$fatal(1,"decoded sample without corresponding core input sample=%0d got=%h",samples,subpacket[j][47:0]);
      if(subpacket[j][47:0]!==expected[rd%QUEUE_DEPTH])
       $fatal(1,"PCM order/content sample=%0d got=%h expected=%h queued=%0d",samples,subpacket[j][47:0],expected[rd%QUEUE_DEPTH],wr-rd);
      if(subpacket[j][48]!==1'b0 || subpacket[j][52]!==1'b0)
       $fatal(1,"PCM invalid sample=%0d flags=%h",samples,subpacket[j][55:48]);
      rd=rd+1;samples=samples+1;
     end
    end
    8'h03:begin
     gcp_packets=gcp_packets+1;
     if(subpacket[0][0] && subpacket[0][4])$fatal(1,"GCP Set/Clear AVMUTE both asserted");
     if(subpacket[0][0])begin avmute_sets=avmute_sets+1;avmuted=1;end
     if(subpacket[0][4])begin avmute_clears=avmute_clears+1;avmuted=0;end
    end
    8'h82,8'h84:begin
     checksum=header[7:0]+header[15:8]+header[23:16];length=header[23:16];
     if(length>27)$fatal(1,"sequence invalid InfoFrame length=%0d",length);
     for(j=0;j<=length;j=j+1)checksum=checksum+pb[j];
     if((checksum&255)!=0)$fatal(1,"sequence InfoFrame checksum type=%h",typ);
     if(typ==8'h82)begin
      avi_packets=avi_packets+1;
      if((pb[4]&127)!=4)$fatal(1,"sequence AVI wrong VIC");
     end else begin
      aif_packets=aif_packets+1;
      if(pb[1]!==8'h01 || pb[4]!==8'h00)
       $fatal(1,"sequence nonstereo AIF PB1=%h PB4=%h",pb[1],pb[4]);
     end
    end
   endcase
   queued=wr-rd;
  end
 endtask
 task automatic capture;
  begin
   d0=terc(c0);d1=terc(c1);d2=terc(c2);
   if(d0<0 || d1<0 || d2<0)$fatal(1,"sequence nonTERC4 index=%0d",index);
   header[index]=d0[2];
   for(integer k=0;k<4;k=k+1)begin subpacket[k][index*2]=d1[k];subpacket[k][index*2+1]=d2[k];end
   if(index==31)begin complete_packet();index=0;state=3;end
   else begin index=index+1;state=2;end
  end
 endtask
 // Capture the same pre-edge values consumed by the real HDMI core. Decode its
 // registered parallel TMDS after the edge; no protected internals are read.
 always @(posedge clk)begin
  if(rst)begin
   wr=0;rd=0;inputs=0;samples=0;queued=0;
   audio_packets=0;acr_packets=0;aif_packets=0;avi_packets=0;
   avmute_clears=0;avmute_sets=0;gcp_packets=0;avmuted=1;last_n=0;last_cts=0;
   state=0;preamble=0;guards=0;index=0;
  end else begin
   if(audio_in_valid)begin
    if(wr-rd>=QUEUE_DEPTH)$fatal(1,"sequence scoreboard overflow");
    expected[wr%QUEUE_DEPTH]={audio_in_right,audio_in_left};
    wr=wr+1;inputs=inputs+1;queued=wr-rd;
   end
   #1;
   case(state)
    0:begin
     if(c1==10'h0ab && c2==10'h0ab)preamble=preamble+1;
     else if(preamble>=8 && gb)begin guards=1;preamble=0;state=1;end
     else preamble=0;
    end
    1:begin
     if(gb)guards=guards+1;
     else begin
      if(guards!=2)$fatal(1,"sequence DI guard length=%0d",guards);
      index=0;capture();
     end
    end
    2:capture();
    3:begin
     if(gb)begin state=0;preamble=0;end
     else begin index=0;capture();end
    end
   endcase
  end
 end
endmodule
