"""Production-source native-clock regressions; no hardware acceptance claim."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,time
R=Path(__file__).resolve().parents[1];H=R/'src/user_source/hdl_source';E=H/'extensions'
B=Path('E:/Modelsim/modelsim_ase/win32aloem')
B2=Path('E:/HX4S20C_Board2/work/link_ack_20261026/rtl')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
parser=argparse.ArgumentParser();parser.add_argument('job',choices=['keymap','infrared','ack','scale','ui']);a=parser.parse_args()
job=a.job;stage=Path(tempfile.mkdtemp(prefix='hx720_'+job+'_'));out=R/'sim_logs'/job;out.mkdir(parents=True,exist_ok=False)
common=['ir_keymap.v','us_tick_1m.v','ir_nec_rx.v','ir_media_bridge.v','media_command_cdc.v','key_debounce.v']
files={
 'keymap':[E/n for n in ['ir_keymap.v','us_tick_1m.v']],
 'infrared':[E/n for n in common]+[H/'board_video_controls.v'],
 'scale':[E/'bmp24_scale_stream.v'],
 'ui':[E/n for n in common+['media_control_arbiter.v','board_remote_control.v','event_packet_rx.v','uart_rx.v','event_fifo.v']]+[H/'board_video_controls.v',R/'rtl/media_mode_reset.v'],
 'ack':[E/n for n in ['board_remote_control.v','event_packet_rx.v','event_packet_tx.v','uart_tx.v','uart_rx.v','event_fifo.v']]
}[job]
top={'keymap':'tb_phone_keymap','infrared':'tb_phone_ir_media','ack':'tb_link_ack','scale':'tb_scale','ui':'tb_unified_controls'}[job]
bench=R/'sim'/(top+'.sv');inputs=files+[bench];commands=[['vlib.exe','work']]
if job=='ack':
 b2=[B2/n for n in ['reliable_event_link.v','event_packet_tx.v','event_packet_rx.v','uart_tx.v','uart_rx.v']]
 inputs+=b2
 commands += [['vlib.exe','b1'],['vlib.exe','b2'],['vlog.exe','-work','b1',*map(str,files)],['vlog.exe','-work','b2',*map(str,b2)]]
 config=stage/'bindings.v';config.write_text('''config ack_config;
 design work.tb_link_ack;
 default liblist work b2 b1;
 instance tb_link_ack.receiver use b1.board_remote_control;
 instance tb_link_ack.receiver.decoder use b1.event_packet_rx;
 instance tb_link_ack.receiver.remote_uart use b1.uart_rx;
 instance tb_link_ack.ack_packets use b1.event_packet_tx;
 instance tb_link_ack.ack_transport use b1.uart_tx;
endconfig
''',encoding='utf8')
 commands += [['vlog.exe','-sv',str(bench)],['vlog.exe',str(config)]];target='ack_config'
else:
 commands += [['vlog.exe','-sv',*map(str,files),str(bench)]];target=top
commands += [['vsim.exe','-c','-t','1ps','-onfinish','stop','work.'+target,'-do','onerror {quit -code 1}; run -all; quit -code 0']]
rec={'pass':False,'stage':str(stage),'sources':{str(p):sha(p) for p in inputs},'commands':commands};start=time.monotonic()
try:
 for i,c in enumerate(commands):
  print(job,'step',i,flush=True)
  p=subprocess.run([str(B/c[0]),*c[1:]],cwd=stage,capture_output=True,timeout=900)
  s=(p.stdout+p.stderr).decode(errors='replace');(out/f'{i}.log').write_text(s,encoding='utf8')
  assert not p.returncode and '** Error:' not in s and '** Fatal:' not in s,s[-6000:]
 markers=[x for x in s.splitlines()if 'PASS 'in x];assert markers,s[-3000:]
 if job=='ack':assert 'Loading b1.event_packet_rx' in s and 'Loading b2.event_packet_rx' in s
 assert all(sha(Path(p))==h for p,h in rec['sources'].items())
 rec.update({'pass':True,'markers':markers});print('\n'.join(markers),flush=True)
except Exception as e:
 rec['error']=str(e);print(str(e)[-6000:],flush=True)
finally:
 rec['wall_seconds']=time.monotonic()-start;(out/'summary.json').write_text(json.dumps(rec,indent=2)+'\n',encoding='utf8')
raise SystemExit(0 if rec['pass']else 1)
