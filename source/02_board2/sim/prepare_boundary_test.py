"""Compose the real SPI pin model with production catalog/CDC/player header path."""
from pathlib import Path
import struct,hashlib,json
R=Path(__file__).resolve().parents[1]
image=R.parent/'TF_PHOTO_VIDEO_30FPS.img'
b=image.read_bytes();base=struct.unpack_from('<I',b,40)[0]
index=struct.unpack_from('<I',b,base*512+36)[0]
frame_lba,frame_bytes=struct.unpack_from('<II',b,(base+index)*512)
frame_sectors=(frame_bytes+511)//512
selected=b[:512]+b[base*512:(base+1)*512]+b[(base+index)*512:(base+index+1)*512]+b[(base+frame_lba)*512:(base+frame_lba+frame_sectors)*512]
(R/'sim/fixtures/card_boot.hex').write_text('\n'.join(f'{x:02x}' for x in selected)+'\n',encoding='ascii')
(R/'sim/fixtures/card_boot.json').write_text(json.dumps(dict(image=str(image),sha256=hashlib.sha256(b).hexdigest(),video_base=base,index_relative=index,frame_lba=frame_lba,frame_bytes=frame_bytes,frame_sectors=frame_sectors),indent=2),encoding='utf8')
s=(R/'sim/tb_spi_read.sv').read_text(encoding='utf8')
s=s.replace('module tb_spi_read;', 'module tb_card_boundary;')
s=s.replace('reg clk=0,rst=1,read_req=0,miso=1;reg[31:0]lba=7;', '''reg clk=0,rst=1,miso=1,decode_clk=0,mem_clk=0;
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
 reg[7:0]card_bytes[0:CARD_LAST];integer offset=0,ends=0;
 initial $readmemh("card_boot.hex",card_bytes);
 always @(posedge clk)if(!rst&&done)ends=ends+1;
 always @(posedge decode_clk)if(!rst&&source_error!=0)
  $fatal(1,"HEADER_FAILURE error=%h state=%h CMD17=%0d bytes=%0d magic=%h count=%0d base=%0d",source_error,source_state,cmd17s,compared,source.player.header[0],source.player.byte_index,source.video_base);'''.replace('CARD_LAST',str(len(selected)-1)))
start=s.index('       if(arg!==',s.index('      17:begin'));end=s.index('\n      end\n      default:',start)
s=s[:start]+f'''       $display("CARD_CMD17 n=%0d address=%0d requested=%0d time=%t",cmd17s+1,arg,lba,$time);
       cmd17s=cmd17s+1;push(0);push(8'hff);push(8'hfe);
       if(arg==0)offset=0;
       else if(arg=={base})offset=512;
       else if(arg=={base+index})offset=1024;
       else if(arg>={base+frame_lba}&&arg<{base+frame_lba+frame_sectors})offset=1536+(arg-{base+frame_lba})*512;
       else $fatal(1,"Unexpected address %0d",arg);
       for(integer k=0;k<512;k=k+1)push(card_bytes[offset+k]);
       push(8'hff);push(8'hff);'''+s[end:]
start=s.index(' always @(posedge clk)if(!rst&&valid)');s=s[:start]+'''
 always @(posedge clk)if(!rst&&valid)compared=compared+1;
 initial begin
  repeat(20)@(negedge clk);rst=0;
  wait(swap_valid);repeat(200)@(negedge clk);
  if(cmd17s!=EXPECTED_SECTORS||ends!=EXPECTED_SECTORS||compared!=EXPECTED_BYTES||source.player.media_ready!==1'b1||words!=153600||(&seen)!==1'b1)
   $fatal(1,"Request mismatch commands=%0d ends=%0d bytes=%0d",cmd17s,ends,compared);
  $display("PASS card_boundary actual_SPI_CDC_catalog_player JPEG_RGB565_first_frame words=%0d sectors=%0d bytes=%0d",words,ends,compared);$finish;
 end
 initial begin #50000000;$fatal(1,"boundary timeout");end
endmodule
'''.replace('EXPECTED_SECTORS',str(3+frame_sectors)).replace('EXPECTED_BYTES',str((3+frame_sectors)*512))
(R/'sim/tb_card_boundary.sv').write_text(s,encoding='utf8')
print('Created boundary regression for sectors',0,base,base+index)
