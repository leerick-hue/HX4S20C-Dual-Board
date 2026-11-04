`timescale 1ns/100fs
module tb_capture_phy;
  localparam TOTAL=24576;
  reg[39:0]vectors[0:TOTAL-1];
  initial begin $readmemh("tmds_0.hex",vectors,0,8191);$readmemh("tmds_1.hex",vectors,8192,16383);$readmemh("tmds_2.hex",vectors,16384,24575);end
  wire[9:0]clock_word=vectors[0][39:30];
  reg refclk=0,pll_rst=1,phy_rst=1;
  always #10 refclk=~refclk;
  wire pclk,sclk,locked,h0,h1,h2,hclk;
  reg [9:0] d0=0,d1=0,d2=0;
  video_hd_pll pll(.refclk(refclk),.reset(pll_rst),.clk0_out(pclk),.clk1_out(sclk),.locked(locked));
  hdmi_phy_wrapper dut(.I_pixel_clk(pclk),.I_serial_clk(sclk),.I_rst(phy_rst),
    .I_tmds_channel_0(d0),.I_tmds_channel_1(d1),.I_tmds_channel_2(d2),
    .I_tmds_channel_clk(clock_word),.O_tmds_ch0_p(h0),.O_tmds_ch1_p(h1),
    .O_tmds_ch2_p(h2),.O_tmds_clk_p(hclk));
  function automatic [9:0] value(input integer lane,input integer n);
    if(n<64)case(lane)0:value=n*13+10'h123;1:value=n*41+10'h2a5;2:value=n*67+10'h3c1;endcase
    else if(n<64+TOTAL)value=vectors[n-64][lane*10+:10];else value=0;
  endfunction
  integer generated=0,boot=0,total=0,payload_checked=0,last_index=-1,payload_total=0;
  always @(posedge pclk or posedge phy_rst)
    if(phy_rst)begin generated=0;d0<=0;d1<=0;d2<=0;end
    else begin generated=generated+1;d0<=value(0,generated);d1<=value(1,generated);d2<=value(2,generated);end

  realtime last_s=0,last_p=0,serial_period=0,pixel_period=0;
  always @(posedge sclk)begin serial_period=$realtime-last_s;last_s=$realtime;end
  always @(posedge pclk)begin : measure
    realtime t,phase;
    t=$realtime;pixel_period=t-last_p;last_p=t;
    #0.0001;
    if(!phy_rst && generated>16)begin
      phase=serial_period-(t-last_s);
      if(pixel_period<13.467 || pixel_period>13.469 || serial_period<2.6926 || serial_period>2.6946)
        $fatal(1,"clock rates Tp=%f Ts=%f",pixel_period,serial_period);
      if(generated==17)$display("CANDIDATE_PLL_PHASE=%f",phase);
    end
  end

  integer release_edges=0;
  always @(posedge sclk)begin
    if(phy_rst)release_edges=0;
    else begin
      release_edges=release_edges+1;
      #0.0001;
      if((release_edges<3 && dut.serial_reset!==1) || (release_edges>=3 && dut.serial_reset!==0))
        $fatal(1,"serial reset released on wrong edge count=%0d reset=%b",release_edges,dut.serial_reset);
    end
  end
  always @(posedge phy_rst)begin
    #0.0001;if(dut.serial_reset!==1)$fatal(1,"serial reset failed asynchronous assertion");
  end
  integer bitpos=10,words=0,checked=0,latency=-1,found;
  reg previous_clock=0,done=0;
  reg [9:0] w0,w1,w2;
  always @(posedge sclk or negedge sclk)begin
    #0.0001;
    if(phy_rst)begin bitpos=10;previous_clock=0;words=0;checked=0;latency=-1;done=0;last_index=-1;payload_checked=0;end
    else if(!done)begin
      if(!locked)$fatal(1,"PLL lost lock during test");
      if(hclk===clock_word[0] && previous_clock===!clock_word[0])begin
        if(words>16 && bitpos!=10)$fatal(1,"forwarded clock boundary bit=%0d",bitpos);
        bitpos=0;
      end
      if(bitpos<10)begin
        w0[bitpos]=h0;w1[bitpos]=h1;w2[bitpos]=h2;
        if(words>16 && hclk!==((bitpos<5)?clock_word[0]:!clock_word[0]))$fatal(1,"forwarded clock duty bit=%0d",bitpos);
        if(bitpos==9)begin
          words=words+1;
          if(words>16)begin
            if(latency<0)begin
              found=-1;
              for(integer i=0;i<13;i=i+1)
                if(w0===value(0,generated-i) && w1===value(1,generated-i) && w2===value(2,generated-i))found=i;
              if(found<0)$fatal(1,"no whole word alignment %h/%h/%h",w0,w1,w2);
              latency=found;
            end
            if(w0!==value(0,generated-latency) || w1!==value(1,generated-latency) || w2!==value(2,generated-latency))
              $fatal(1,"serial word mismatch generated=%0d latency=%0d got=%h/%h/%h",generated,latency,w0,w1,w2);
            checked=checked+1;
            if(last_index>=0 && generated-latency!=last_index+1)$fatal(1,"captured TMDS word skipped or repeated");
            last_index=generated-latency;
            if(last_index>=64 && last_index<64+TOTAL)payload_checked=payload_checked+1;
            if(last_index==TOTAL+63)begin total=total+checked;payload_total=payload_total+payload_checked;done=1;$display("CAPTURE_OK words=%0d payload=%0d latency=%0d",checked,payload_checked,latency);end
          end
        end
        bitpos=bitpos+1;
      end
      previous_clock=hclk;
    end
  end
  initial begin
    for(boot=1;boot<=3;boot=boot+1)begin
      phy_rst=1;pll_rst=1;#1000;pll_rst=0;
      wait(locked===1);repeat(64)@(negedge pclk);#(boot*0.317);phy_rst=0;
      wait(done===1);@(negedge pclk);phy_rst=1;
      repeat(3)@(negedge sclk);
    end
    if(payload_total!=3*TOTAL)$fatal(1,"incomplete captured payload %0d",payload_checked);
    $display("PASS service_phy starts=3 actual_core_TMDScycles=73728 payload_bits=2211840 lanes=3 actual_vendor_PLL shared_serial_reset_three_edges exact_word_and_bit_order no_SDF_no_receiver_eye");$finish;
  end
  initial begin #3000000;$fatal(1,"timeout boot=%0d checked=%0d lock=%b",boot,checked,locked);end
endmodule
