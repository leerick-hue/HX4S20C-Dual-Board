"""Record user-reported cold-start success without changing FPGA sources/bits."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json
P=Path(__file__).resolve().parents[1]
now=datetime.now(timezone(timedelta(hours=8))).isoformat()
items=[('video_step2_tf_retry_20261029','HX4S20C_VIDEO_STEP2_TF_FIX_A672C369.bit',
 'a672c36951ff2de2bc419fd44087c871732b28dddbdec48b5067e14f11ebd148',
 '这版也对了 冷启动就对了'),
 ('video_step2_tf_probe_20261029','HX4S20C_VIDEO_STEP2_PROBE_DEFA1889.bit',
 'defa188978407a6c570f98bf3a1864cadb67b3e73d763ae900e6c5e98eb70d64',
 '出现正常画面了')]
for folder,name,h,quote in items:
 bit=P/name;assert hashlib.sha256(bit.read_bytes()).hexdigest()==h
 r=P/folder;p=r/'DELIVERY.json';j=json.loads(p.read_text(encoding='utf8'))
 history=j.setdefault('board_feedback_history',[])
 if j.get('board_feedback') and j['board_feedback'] not in history:history.append(j['board_feedback'])
 observation=dict(recorded_at=now,condition='User cold power cycle; probe trial also reseated TF and reloaded SRAM.',
   user_report=quote,result='normal picture/function reported after cold start',
   sustained_duration_seconds=None,measured_fps=None,
   audio_evidence='Audio was reported audible before cold start; no separate cold-start audio measurement.',
   root_cause='Unresolved initialization/startup condition. No exact card failure mechanism established.')
 j.update(state='user_reported_cold_start_pass_warm_start_unresolved',hardware_tested=True,board_feedback=observation)
 j['actual_hardware_fps']=None
 j['limitations']=[v for v in j['limitations'] if v not in [
  'New candidate not yet board-tested; simulated matching failure does not exclude additional hardware issues.',
  'Observation only: does not claim to fix the black display.']]
 j['limitations'].append('User reports cold-start success. Earlier black-display startup remains unresolved; sustained playback and warm-reset repeatability not yet measured.')
 p.write_text(json.dumps(j,ensure_ascii=False,indent=2),encoding='utf8')
 (r/'BOARD_RESULT.json').write_text(json.dumps(dict(bit=str(bit),sha256=h,latest=observation,prior=history),ensure_ascii=False,indent=2),encoding='utf8')

baseline=dict(recorded_at=now,preferred_bit=str(P/items[0][1]),sha256=items[0][2],
 source=str(P/items[0][0]),status='user_reported_working_after_cold_start',
 diagnostic_bit=str(P/items[1][1]),movie_soundtrack_enabled=False,
 next_checks=['Sustained video loop and reference tone','Warm reset/startup repeatability'],
 unchanged_sources=True,unchanged_bit_files=True)
(P/'VIDEO_CURRENT_BASELINE.json').write_text(json.dumps(baseline,ensure_ascii=False,indent=2),encoding='utf8')
notice='''> 2026-10-29 最新实板反馈：用户确认 A672C369 与 DEFA1889 冷启动后画面正常。当前常规视频基线采用 A672C369；DEFA1889 保留作诊断。先断电、确认 TF 插好，再上电重新 SRAM 下载。此前出现过 TF 初始化未完成，启动稳定性仍待排查；连续播放时长与实测帧率未确认。声音仍为固定测试音。以下保留原交付说明及历史测试范围。

'''
for filename in ['VIDEO_STEP2_TF_FIX_TEST_STEPS.md','VIDEO_STEP2_TF_PROBE_TEST_STEPS.md']:
 p=P/filename;s=p.read_text(encoding='utf8')
 if not s.startswith('> 2026-10-29 最新实板反馈'):p.write_text(notice+s,encoding='utf8')
print(json.dumps(baseline,ensure_ascii=False,indent=2))
