"""Encode the 854x480 source to true 640x480/15fps; only ordinary files."""
from pathlib import Path
import hashlib, io, json, shutil, struct, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

R=Path(__file__).resolve().parent
TOOLS=R/'tools';TOOLS.mkdir(exist_ok=True)
for name in ('hxjv.py','jpeg_profile.py'):
    shutil.copy2(R.parents[1]/'tools'/name,TOOLS/name)
sys.path.insert(0,str(TOOLS));import hxjv
hxjv.WIDTH,hxjv.HEIGHT=640,480
FF=R.parents[1]/'tools/ffmpeg.exe'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=json.loads((R/'SOURCE.json').read_text())
assert sha(R/'source_hd.mp4')==source['sha256']
frames=R/'frames';frames.mkdir(exist_ok=True)
assert not list(frames.glob('*.jpg')), 'Do not mix frame sets'
fps,duration,start=15,20,10
cmd=[str(FF),'-hide_banner','-nostdin','-loglevel','error','-ss',str(start),'-i',str(R/'source_hd.mp4'),
     '-t',str(duration),'-map','0:v:0','-an','-vf','fps=15,crop=640:480',
     '-frames:v',str(fps*duration),'-pix_fmt','rgb24','-f','rawvideo','pipe:1']
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',13)
details=[]
with (R/'extract.log').open('wb') as log:
    proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=log)
    try:
        for i in range(fps*duration):
            raw=proc.stdout.read(640*480*3)
            assert len(raw)==640*480*3, f'short frame {i}'
            im=Image.frombytes('RGB',(640,480),raw)
            draw=ImageDraw.Draw(im)
            text='Big Buck Bunny | (c)2008 Blender Foundation | CC BY 3.0'
            draw.text((8,459),text,font=font,fill='white',stroke_width=1,stroke_fill='black')
            blob,q=hxjv.encode_rgb(im,quality=78,max_bytes=50000,min_quality=40)
            hxjv.inspect_jpeg(blob,640,480)
            decoded=Image.open(io.BytesIO(blob));decoded.load();assert decoded.size==(640,480)
            (frames/f'frame_{i:08d}.jpg').write_bytes(blob)
            details.append(dict(frame=i,jpeg_bytes=len(blob),quality=q))
        assert not proc.stdout.read(1)
        assert proc.wait()==0
    finally:
        if proc.poll() is None:proc.terminate();proc.wait()
        proc.stdout.close()
player=R/'BBB_HXJV_640x480_15fps.img'
pack=hxjv.pack_sequence(frames,player,fps=fps,budget=1000000)
hxjv.inspect_image(player,budget=1000000)
assert pack['bandwidth']['every_frame_interval_within_budget']
old=R.parents[1]/'board2_adaptive_voice_20261101/media_bbb_20261102/DELIVERY/CARD_BBB_20s_320x240_25fps.img'
prefix=bytearray(old.read_bytes()[:4096]);video=player.read_bytes();count=len(video)//512
struct.pack_into('<3I',prefix,40,8,count,8+count)
out=R.parent/'DELIVERY';out.mkdir(exist_ok=True)
card=out/'CARD_BBB_20s_640x480_15fps.img';card.write_bytes(prefix+video)
assert card.read_bytes()[4096:4100]==b'HXJV'
preview=out/'BBB_480p15_preview.mp4'
subprocess.run([str(FF),'-hide_banner','-nostdin','-loglevel','error','-framerate','15','-i',str(frames/'frame_%08d.jpg'),
                '-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart','-y',str(preview)],check=True)
Image.open(frames/'frame_00000150.jpg').save(out/'preview_640x480.png')
report=dict(state='encoded_checked_pending_RTL',width=640,height=480,fps=fps,frames=300,duration_seconds=20,audio=False,
            source=source,source_start_seconds=10,source_dimensions=[854,480],
            modifications='Centre crop from854x480 to640x480 without upscaling; sample15fps; visible attribution; baseline420 standard Huffman JPEG',
            card=dict(path=str(card),bytes=card.stat().st_size,sha256=sha(card)),
            preview=dict(path=str(preview),sha256=sha(preview)),
            frame_max_bytes=max(d['jpeg_bytes'] for d in details),quality_min=min(d['quality'] for d in details),
            bandwidth=pack['bandwidth'],all_profiles_checked=True,all_software_decoded=True,hardware_tested=False,
            frames_detail=details,tool_hashes={str(p):sha(p) for p in (Path(__file__),TOOLS/'hxjv.py',TOOLS/'jpeg_profile.py',FF)})
(R/'MEDIA_REPORT.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:report[k] for k in ('card','frame_max_bytes','quality_min','bandwidth')},indent=2))
