from pathlib import Path
import re
r=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/album_hd_prefetch_20261029')
p=r/'src/td_project/HX4S20C_Extensions.al'
t=p.read_text(encoding='utf-8')
t=re.sub(r'<File Path="../user_source/hdl_source/extensions/(?:event_packet_tx|uart_tx)\.v">.*?</File>','',t)
template=re.search(r'            <File Path="../user_source/hdl_source/extensions/uart_rx.v">.*?</File>',t,re.S).group()
tags='\n'.join(template.replace('uart_rx.v',n+'.v').replace('Val="100"','Val="110"') for n in ['event_packet_tx','uart_tx'])
t=t.replace('</Verilog>',tags+'\n        </Verilog>')
p.write_text(t,encoding='utf-8')
print('TD source entries normalized')
