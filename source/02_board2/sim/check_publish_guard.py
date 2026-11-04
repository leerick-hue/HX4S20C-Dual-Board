"""Exercise the real publication gate with invalid release evidence; no FPGA build."""
from pathlib import Path
import ast, hashlib, json, uuid

R=Path(__file__).resolve().parents[1]
case=R/'sim_stages'/('publish_guard_'+uuid.uuid4().hex[:10])
case.mkdir(parents=True)
source=case/'source.v';source.write_text('original input\n')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
tree=ast.parse((R/'publish.py').read_text(encoding='utf8'))
functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ('read','checked_test')]
ns=dict(R=case,Path=Path,json=json,sha=sha)
exec(compile(ast.Module(body=functions,type_ignores=[]),'publish.py','exec'),ns)
gate=ns['checked_test']
results=[]

def report(group,run,data):
 p=case/'sim_logs'/f'{group}_{run}'/'summary.json';p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(data),encoding='utf8');return p

def blocked(label,pattern,*args):
 try:gate(pattern,*args)
 except AssertionError as e:results.append(dict(case=label,blocked=True,reason=str(e)))
 else:raise AssertionError('Publication incorrectly accepted '+label)

good=dict(passed=True,sources={str(source):sha(source)},results=['PASS'],scope='guard fixture')
report('test','20260101',good)
assert gate('test_*/summary.json')['results']==['PASS']
results.append(dict(case='valid matching evidence',accepted=True))
report('test','20260102',dict(good,passed=False))
blocked('newer failure overrides older pass','test_*/summary.json')
report('empty','20260101',dict(good,sources={}))
blocked('empty source evidence','empty_*/summary.json')
report('changed','20260101',good)
source.write_text('modified after test\n')
blocked('modified source after passing test','changed_*/summary.json')
source.write_text('original input\n')
phy=dict(good,pass_lines=['PASS PHY']);phy.pop('passed');phy['pass']=True
report('phy','20260101',phy)
assert gate('phy_*/summary.json','pass','pass_lines')['results']==['PASS PHY']
report('phy','20260102',dict(phy,**{'pass':False}))
blocked('newer PHY failure overrides older pass','phy_*/summary.json','pass','pass_lines')
output=dict(passed=True,publish_sha256=sha(R/'publish.py'),results=results,stage=str(case))
(R/'PUBLISH_GUARD_CHECK.json').write_text(json.dumps(output,indent=2),encoding='utf8')
print(json.dumps(output,indent=2))
