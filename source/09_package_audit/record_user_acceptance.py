"""Record explicit user acceptance, preserving original publication evidence."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[1]
destination=ROOT/'06_validation/USER_ACCEPTANCE_20261103.json'
assert not destination.exists(),destination
manifest=json.loads((ROOT/'MANIFEST.json').read_text(encoding='utf8'))
bits=manifest['current_bits']
for name,h in bits.items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==h
record=dict(recorded_at_Asia_Shanghai=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    recorded_date_Asia_Shanghai='2026-11-03',
    state='user_reported_both_boards_hardware_accepted',
    user_statement='这两板已经验收了啊 改一下',
    versions=['8EB7D133','6F5DD197'],current_bits=bits,
    hardware_tested=True,user_reported_hardware_accepted=True,agent_performed_hardware_test=False,
    scope='User explicitly confirms both selected boards have completed hardware acceptance; no additional per-feature measurements or test procedures inferred.',
    publication_history='Original per-board release/build/simulation records retain their publication-time pending status; this subsequent user confirmation supersedes that status for the selected bit hashes.',
    changes='Acceptance metadata, current documentation and package checksums only; firmware, RTL, constraints and original publication inputs unchanged.')
destination.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
for relative in ('06_validation/INPUT_VERIFICATION.json','09_package_audit/README_FACTS.json'):
    p=ROOT/relative
    history=p.parent/'history_before_user_acceptance'
    history.mkdir(exist_ok=True)
    shutil.copy2(p,history/p.name)
    value=json.loads(p.read_text(encoding='utf8'))
    for release in value['releases']:
        release.update(publication_hardware_tested=release['hardware_tested'],hardware_tested=True,
            user_reported_hardware_accepted=True,acceptance_record='06_validation/USER_ACCEPTANCE_20261103.json')
    value.update(current_state=record['state'],user_reported_hardware_accepted=True,
                 acceptance_record='06_validation/USER_ACCEPTANCE_20261103.json',agent_performed_hardware_test=False)
    value['note']='Current acceptance is the subsequent explicit user confirmation for both selected bit hashes. Original publication-time records remain historical; packaging did not operate hardware or cards.'
    p.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
for board in ('01_board1','02_board2'):
    (ROOT/board/'ACCEPTANCE_UPDATE.md').write_text(
        '# 当前实板验收状态\n\n'
        '用户于2026-11-03明确确认：板一 **8EB7D133**、板二 **6F5DD197** 均已验收。'
        '依据见 [用户验收记录](../06_validation/USER_ACCEPTANCE_20261103.json)，与其中完整位流哈希绑定。\n\n'
        '此目录原 DELIVERY.json、DELIVERY/README.md、ENGINEERING.md 与构建/仿真记录保留发布当时状态。'
        '其中“待实板验收”已由上述后续确认补充，不代表当前仍未验收。'
        '本轮只更新交付状态，没有重新烧录、测试板卡或改动源代码。\n',encoding='utf8')
print('Recorded user acceptance for both selected firmware hashes.')
