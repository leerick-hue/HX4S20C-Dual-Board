"""Publish a new candidate only after every retained check and source audit passes."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,shutil,subprocess,sys
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
subprocess.run([sys.executable,str(R/'tools/audit_release.py')],check=True,cwd=R)
reports={}
for name in ['keymap','infrared','ack','scale','ui','album720','acr_service_top']:
 p=R/'sim_logs'/name/'summary.json';rec=json.loads(p.read_text(encoding='utf8'));assert rec['pass'],name
 for q,h in rec['sources'].items():assert sha(Path(q))==h,'Changed simulation input: '+q
 reports[name]={'path':str(p),'sha256':sha(p),'markers':rec.get('markers',rec.get('pass_lines',[])),'wall_seconds':rec['wall_seconds']}
audit=R/'audit/source_audit.json';a=json.loads(audit.read_text(encoding='utf8'));assert a['pass']
p=R/'build/hd720_controls_release/manifest.json';b=json.loads(p.read_text(encoding='utf8'))
assert b['pass']and b['timing_closed']
for e in b['sources']:assert sha(R/e['path'])==e['sha256']
src=p.parent/'HX4S20C_UNIFIED_TEST.bit';assert sha(src)==b['bit_sha256']
target=R.parent/'build/HX4S20C_Extensions_PHONE_IR_FIT_HD720_LINK_ACK.bit'
assert not target.exists(),'Never overwrite an existing release'
shutil.copy2(src,target);assert sha(target)==sha(src)
result={'utc':datetime.now(timezone.utc).isoformat(),'pass':True,'file':str(target),'sha256':sha(target),
 'hardware_programmed':False,'hardware_accepted':False,'status':'Candidate for user hardware acceptance',
 'build_manifest':{'path':str(p),'sha256':sha(p)},'source_audit':{'path':str(audit),'sha256':sha(audit)},
 'simulation_reports':reports,'setup_ns':b['setup_ns'],'hold_ns':b['hold_ns'],
 'old_releases_verified':a['old_releases_verified'],
 'limits':['Native1280x720 photos, RGB565 storage, nearest-neighbor aspect fit; video disabled.',
 'Existing5x7 ASCII font and logical640x480 UI canvas retained; no added glyph detail.',
 'Synthetic sector bytes and memory acceptance in media simulation; no physical SD/SDRAM/HDMI new-hardware validation.',
 'Full-top audio test uses deliberate PCM/ACR/lock/ack endpoint stimuli and actual vendor clock models; SDRAM hard-core model is empty.',
 'Board2 recognition firmware unchanged; voice transport and controls verified digitally, no new acoustic-recognition test.']}
(R/'delivery_hd720.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
lines=['# 验证记录','',f"新板一文件：`{target.name}`。SHA-256：`{sha(target)}`。",'',
 f"布局布线后的建立时间余量 **+{b['setup_ns']:.3f} ns**，保持时间余量 **+{b['hold_ns']:.3f} ns**，报告覆盖率 99.96%。保留原有时序约束，仅增加恢复的控制邮箱和 ACK 输出约束。",'',
 '资源：LUT 9,754/19,600；寄存器 7,774；BRAM9K 39/64；DSP 6/29；PLL 3/4。', '',
 f"相对实板通过的高清照片／声音基础，共 {len(a['unchanged_production_inputs'])} 个生产输入保持字节一致，修改 {len(a['changed_production_inputs'])} 个，新增 2 个 ACK 发送模块。SDRAM、HDMI、音频和时钟等主数据通路保持原代码。源文件差异见 `audit/production.diff`。",'',
 '| 检查 | 结果 |','|---|---|']
descriptions={
 'keymap':'74.25MHz：手机五键、原遥控器、地址过滤、长按节流、背压',
 'infrared':'74.25/40MHz：真实 NEC 波形经过接收器、映射、跨时钟邮箱和控制，五键及未知键',
 'ack':'50/40MHz、115200：回传、坏包重发、确认丢失、去重、忙时排队、断线恢复',
 'scale':'5 个完整 1280×720 帧：每像素地址／RGB／黑边，横竖图、BMP 方向、原生尺寸、随机阻塞',
 'ui':'74 项断言：六个按键模式、16 个 UART 快捷操作、双方向控制邮箱、音量饱和／静音／播放',
 'album720':'3 个完整 720p 帧、1,382,400 个 RGB565 字：手动切图、自动回绕／关闭、双缓冲、淡入淡出、共享 SD／PCM／DMA、暂停继续，音频无欠载',
 'acr_service_top':'完整顶层及供应商时钟模型：64 个立体声样本、4 次 ACR，锁定／确认等待、默认控制和诊断同步'}
for n in reports:lines.append(f'| {descriptions[n]} | 通过 |')
lines += ['','仿真来源、输入哈希和详细范围见各 `sim_logs/*/summary.json`。相册测试加速了自动播放计时和帧边界，但使用实际 40/50/74.25/100MHz 数据时钟。控制功能测试加速了去抖／串口比特；真实 NEC 和原生 115200 回传另行验证。', '',
 '本文件记录软件和实现结果；**没有下载硬件，也没有宣称新固件实板通过**。板二原语音识别和训练代码未改，未新增声学识别试验。', '',
 '旧手机红外、旧等比例版本和板二语音固件的哈希均与各自交付记录一致。新文件独立命名；现有 TF 卡未改写。']
(R/'VALIDATION.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
print('Published candidate:',target,'SHA256',sha(target),flush=True)
