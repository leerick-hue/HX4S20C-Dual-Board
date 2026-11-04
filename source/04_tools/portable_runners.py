"""Run release files in a new work copy, resolving packaged dependencies."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import runpy
import shutil
import sys
import re

PKG=Path(__file__).resolve().parents[1]
JOBS={
    'board1-unit':('01_board1','sim/run_period_unit.py',[]),
    'board1-album':('01_board1','sim/run_period_integration.py',['--jobs','album']),
    'board1-ui':('01_board1','sim/run_period_integration.py',['--jobs','ui']),
    'board1-infrared':('01_board1','sim/run_period_integration.py',['--jobs','infrared']),
    'board1-build':('01_board1','tools/build_video.py',['--name','album_period_seed11','--seed','11','--carry-min','5']),
    'board2-video':('02_board2','sim/run_480p_video.py',[]),
    'board2-rate':('02_board2','sim/run_480p_video.py',['--rate']),
    'board2-coexist':('02_board2','sim/run_coexist.py',[]),
    'board2-link':('02_board2','sim/run_coexist.py',['--link']),
    'board2-jpeg':('02_board2','media/check_rtl_samples.py',[]),
    'board2-build':('02_board2','build.py',[]),
}

def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()

def source_matches(path, expected):
    current=digest(path)
    if current==expected:return True
    revision=json.loads((PKG/'09_package_audit/TEXT_REVISION.json').read_text(encoding='utf8'))
    entry=revision['comment_only_sources'].get(path.relative_to(PKG).as_posix())
    if not entry or entry['original_sha256']!=expected or entry['current_sha256']!=current:return False
    text=path.read_text(encoding='utf-8-sig')
    if path.suffix in ('.v','.sv','.vh'):
        parts=re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/|[^\s]',text)
        content=[part for part in parts if not part.startswith(('//','/*'))]
    elif path.suffix in ('.adc','.sdc','.tcl'):
        content=[line for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    else:return False
    return hashlib.sha256(json.dumps(content,ensure_ascii=False).encode('utf8')).hexdigest()==entry['code_sha256']

def doctor():
    failures=[]
    selected=json.loads((PKG/'06_validation/INPUT_VERIFICATION.json').read_text(encoding='utf8'))
    for board,release in zip(('01_board1','02_board2'),selected['releases']):
        if digest(PKG/'00_firmware_current'/release['bit'])!=release['sha256']:
            failures.append(release['bit'])
    mapping=json.loads((PKG/'07_dependencies/PATH_MAP.json').read_text(encoding='utf8'))
    for path in mapping.values():
        if not (PKG/path).exists():failures.append(path)
    for folder in ('01_board1','02_board2'):
        d=json.loads((PKG/folder/'DELIVERY.json').read_text(encoding='utf8'))
        local_manifest=PKG/folder/('build/album_period_seed11/manifest.json' if folder=='01_board1' else 'build/manifest.json')
        m=json.loads(local_manifest.read_text(encoding='utf8'))
        entries=m['sources'].items() if isinstance(m['sources'],dict) else ((e['path'],e['sha256']) for e in m['sources'])
        for name,h in entries:
            if not source_matches(PKG/folder/name,h):failures.append(folder+'/'+name)
    # The installed proprietary vendor models remain an explicit tool dependency.
    sdk=json.loads((PKG/'07_dependencies/REQUIRED_VENDOR_MODELS.json').read_text(encoding='utf8'))
    td=os.environ.get('HX_TD_ROOT','E:/TD/TD')
    for name,h in sdk.items():
        path=Path(name.replace('E:\\TD\\TD',td).replace('E:/TD/TD',td))
        if not path.is_file() or digest(path)!=h:failures.append('Vendor model: '+str(path))
    report=dict(passed=not failures,failures=failures,selected_build_inputs=252,
                tool_config=dict(TD=td,ModelSim=os.environ.get('HX_MODELSIM_BIN','E:/Modelsim/modelsim_ase/win32aloem')))
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return not failures

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--doctor',action='store_true')
    parser.add_argument('--job',choices=JOBS)
    parser.add_argument('--workdir',type=Path,help='A new directory outside the package; never overwritten')
    args=parser.parse_args()
    if args.doctor:return 0 if doctor() else 1
    if not args.job or args.workdir is None:parser.error('--job requires --workdir')
    work=args.workdir.resolve()
    if work.exists() or work.is_relative_to(PKG):
        parser.error('Use a new, nonexistent work directory outside this package')
    board,entry,arguments=JOBS[args.job]
    shutil.copytree(PKG/board,work,ignore=shutil.ignore_patterns('__pycache__','sim_stages','build_stages'))
    source=work/entry
    code=source.read_text(encoding='utf8')
    mapping=json.loads((PKG/'07_dependencies/PATH_MAP.json').read_text(encoding='utf8'))
    for old,new in sorted(mapping.items(),key=lambda item:len(item[0]),reverse=True):
        code=code.replace(old,(PKG/new).as_posix())
    # Resolve relative references to sibling workspaces without editing the snapshot.
    code=code.replace("R.parent/'tools'","PKG/'04_tools/media_tools'")
    code=code.replace("R.parents[1]/'tools'","PKG/'04_tools/media_tools'")
    old="'board2_adaptive_voice_20261101/media_bbb_20261102/DELIVERY/CARD_BBB_20s_320x240_25fps.img'"
    code=code.replace('R.parent/'+old,"PKG/'07_dependencies/old320_prefix.img'")
    code=code.replace('R.parents[1]/'+old,"PKG/'07_dependencies/old320_prefix.img'")
    code=code.replace("rtlstage=Path(sample['stage'])","rtlstage=R/'media'/Path(sample['stage']).name")
    code=code.replace('E:/TD/TD',os.environ.get('HX_TD_ROOT','E:/TD/TD').replace('\\','/'))
    model=os.environ.get('HX_MODELSIM_BIN','E:/Modelsim/modelsim_ase/win32aloem').replace('\\','/')
    code=code.replace('E:/Modelsim/modelsim_ase/win32aloem',model)
    code=code.replace('E:/Modelsim/modelsim_ase',Path(model).parent.as_posix())
    # Golden PNGs and media are copied with the release; all identities are in MANIFEST.
    os.environ['HX_480_PREFIX_CARD']=str(PKG/'07_dependencies/old320_prefix.img')
    sys.argv=[str(source),*arguments]
    os.chdir(work)
    exec(compile(code,str(source),'exec'),dict(__name__='__main__',__file__=str(source),PKG=PKG))
    return 0

if __name__=='__main__':
    raise SystemExit(main())
