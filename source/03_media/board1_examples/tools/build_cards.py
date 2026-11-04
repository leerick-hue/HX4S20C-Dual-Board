"""Prepare three ordinary card image files; no physical device access."""
from pathlib import Path
import hashlib, io, json, shutil, struct, subprocess, sys, wave
from PIL import Image, ImageDraw, ImageFont, ImageOps
import hxjv
from pack_tf_audio import pack_images

R=Path(__file__).resolve().parents[1]
FF=Path('E:/HX4S20C_Test_20261026/tools/ffmpeg.exe')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',9)
photos=[('moraine','梦莲湖与雪山','https://commons.wikimedia.org/wiki/File:Moraine_Lake_17092005.jpg'),
 ('mist','云雾群山','photo-1470071459604-3b5ec3a7fe05'),
 ('valley','山谷溪流','photo-1506744038136-46273834b3fb'),
 ('forest','林间阳光','photo-1441974231531-c6227db76b6e'),
 ('mountain','雪山群峰','photo-1464822759023-fed622ff2c3b'),
 ('desert','红岩荒漠','photo-1509316785289-025f5b846b35')]
sources=[]
for key,title,url in photos:
    p=R/'sources/photos'/(key+'.jpg');assert p.exists()
    if key=='moraine':
        source=dict(author='Gorgo',license='Public domain',license_url='https://creativecommons.org/publicdomain/mark/1.0/',source_url=url)
    else:
        width=1440 if key=='mountain' else 1920
        source=dict(author='Not independently resolved; attribution is optional under Unsplash License',license='Unsplash License',license_url='https://unsplash.com/license',source_url=f'https://images.unsplash.com/{url}?auto=format&fit=max&w={width}&q=90&fm=jpg')
    sources.append(dict(id=key,title=title,local_path=str(p.relative_to(R)),sha256=sha(p),**source))
(R/'sources/photos/SOURCES.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2),encoding='utf8')

groups=[('01_ALBUM_USER2_SCENERY2_BOARD1.img','album1_bmp',
 [('user_1','你提供的乡村水岸'),('user_2','你提供的灯塔'),('moraine','梦莲湖与雪山'),('mist','云雾群山')]),
 ('02_ALBUM_SCENERY4_BOARD1.img','album2_bmp',
 [('valley','山谷溪流'),('forest','林间阳光'),('mountain','雪山群峰'),('desert','红岩荒漠')])]
music=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/tf_audio_20261022/demo_music.wav')
shutil.copy2(music,R/'sources/album_existing_demo_music.wav')
albums=[]
for output,folder,items in groups:
    grid=Image.new('RGB',(960,612),'#111111');draw=ImageDraw.Draw(grid);details=[]
    for i,(key,label) in enumerate(items):
        p=R/'sources/photos'/(key+'.jpg');h0=sha(p)
        with Image.open(p) as source:
            image=ImageOps.exif_transpose(source).convert('RGB');original=image.size
            image.thumbnail((1920,1080),Image.Resampling.LANCZOS)
            dest=R/folder/f'{i+1:04d}.BMP';image.save(dest,format='BMP')
            with Image.open(dest) as check:
                assert check.mode=='RGB' and check.tobytes()==image.tobytes()
            thumb=ImageOps.contain(image,(480,270),Image.Resampling.LANCZOS)
            x=(i%2)*480;y=(i//2)*306
            grid.paste(thumb,(x+(480-thumb.width)//2,y+(270-thumb.height)//2))
            draw.text((x+12,y+274),f'{i+1}. {label}',font=font,fill='white')
            details.append(dict(index=i+1,title=label,source=str(p.relative_to(R)),original_size=original,
                bmp_size=image.size,bmp_sha256=sha(dest),modification='EXIF orientation, RGB24 BMP; shrink only when exceeding1920x1080; no crop or color enhancement'))
        assert sha(p)==h0
    preview=R/'previews'/('album1.jpg' if folder=='album1_bmp' else 'album2.jpg')
    grid.save(preview,quality=92)
    result=pack_images(R/folder,R/'sources/album_existing_demo_music.wav',R/'DELIVERY'/output)
    albums.append(dict(file=output,photos=details,pack=result,preview=str(preview.relative_to(R))))
    print('ALBUM_READY',output,result['output']['size_bytes'],flush=True)
(R/'reports/ALBUMS.json').write_text(json.dumps(albums,ensure_ascii=False,indent=2),encoding='utf8')
if '--albums-only' in sys.argv:raise SystemExit(0)

hxjv.WIDTH,hxjv.HEIGHT=320,240
frames=R/'frames'
generation=R/'reports/FRAME_GENERATION.json'
signature=dict(source_sha256=sha(R/'sources/cartoon/source.mp4'),width=320,height=240,fps=25,quality=72,max_bytes=20000,min_quality=35)
if generation.exists():
    d=json.loads(generation.read_text(encoding='utf8'));assert d['signature']==signature
    assert len(list(frames.glob('*.jpg')))==d['count']
else:
    assert not any(frames.glob('*.jpg')),'Refusing to mix existing frame sets'
    command=[str(FF),'-hide_banner','-nostdin','-loglevel','error','-i',str(R/'sources/cartoon/source.mp4'),
      '-map','0:v:0','-an','-vf','fps=25,scale=320:240:force_original_aspect_ratio=decrease:flags=lanczos,pad=320:240:(ow-iw)/2:(oh-ih)/2:black',
      '-pix_fmt','rgb24','-f','rawvideo','pipe:1']
    details=[]
    with (R/'reports/ffmpeg_extract.log').open('wb') as error:
        process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=error)
        try:
            index=0
            while True:
                data=process.stdout.read(320*240*3)
                if not data:break
                assert len(data)==320*240*3,('short frame',index)
                image=Image.frombytes('RGB',(320,240),data);draw=ImageDraw.Draw(image)
                credit='Blender Foundation / caminandes.com'
                draw.text(((320-draw.textlength(credit,font=small))/2,222),credit,font=small,fill='white')
                blob,q=hxjv.encode_rgb(image,quality=72,max_bytes=20000,min_quality=35)
                hxjv.inspect_jpeg(blob,320,240)
                with Image.open(io.BytesIO(blob)) as decoded:
                    decoded.load();assert decoded.size==(320,240)
                (frames/f'frame_{index:08d}.jpg').write_bytes(blob)
                details.append(dict(frame=index,bytes=len(blob),quality=q));index+=1
                if index%500==0:print('ENCODED_FRAMES',index,flush=True)
            assert process.wait()==0,'ffmpeg failed'
        finally:
            if process.poll() is None:process.terminate();process.wait()
            process.stdout.close()
    assert 3600<=len(details)<=3700,('unexpected film frame count',len(details))
    d=dict(signature=signature,count=len(details),duration_seconds=len(details)/25,details=details)
    generation.write_text(json.dumps(d,indent=2),encoding='utf8')
player=R/'cartoon_player.img'
packed=hxjv.pack_sequence(frames,player,fps=25,budget=1000000)
checked=hxjv.inspect_image(player,budget=1000000)
assert packed['header']['flags']==0 and packed['bandwidth']['every_frame_interval_within_budget']
known=Path('E:/HX4S20C_Test_20261026/group2_voice_robust_20261102/DELIVERY/CARD_BBB_20s_320x240_25fps.img')
prefix=bytearray(known.read_bytes()[:4096]);assert prefix[36:40]==b'HXUV'
blob=player.read_bytes();assert len(blob)%512==0
struct.pack_into('<3I',prefix,40,8,len(blob)//512,8+len(blob)//512)
out=R/'DELIVERY/03_CARTOON_GRAN_DILLAMA_BOARD2.img';out.write_bytes(prefix+blob)
assert struct.unpack_from('<I',out.read_bytes(),48)[0]*512==out.stat().st_size
preview=R/'previews/03_CARTOON_PREVIEW.mp4'
subprocess.run([str(FF),'-hide_banner','-nostdin','-loglevel','error','-framerate','25','-i',str(frames/'frame_%08d.jpg'),
 '-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart','-y',str(preview)],check=True)
contact=Image.new('RGB',(960,480))
chosen=[min(d['count']-1,n*25) for n in [8,25,50,75,100,125]]
for i,index in enumerate(chosen):
    with Image.open(frames/f'frame_{index:08d}.jpg') as im:contact.paste(im,((i%3)*320,(i//3)*240))
contact.save(R/'previews/cartoon.jpg',quality=92)
report=dict(file=out.name,sha256=sha(out),bytes=out.stat().st_size,film='Caminandes 2: Gran Dillama',
 duration_seconds=d['duration_seconds'],frames=d['count'],width=320,height=240,fps=25,audio=False,
 frame_max_bytes=packed['header']['max_jpeg_bytes'],all_frames_profile_and_software_decode_pass=True,
 bandwidth=packed['bandwidth'],video_base_lba=8,hardware_tested=False,
 note='Full short film incl original credits, 24-to25fps, aspect-fit letterbox, extra visible author URL, silent current Board2 firmware')
(R/'reports/VIDEO.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('THREE_CARDS_READY',json.dumps(report),flush=True)
