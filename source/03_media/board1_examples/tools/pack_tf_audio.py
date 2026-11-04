"""Pack photos plus PCM WAV into the Board1 HXAU raw card image; no device access."""
from pathlib import Path
import argparse, hashlib, json, math, struct, wave

SECTOR=512
MAX_IMAGE_BYTES=512*1024*1024  # Conservative limit for the user's 1 GB card.
class PackError(ValueError): pass

def inspect_bmp(path):
    p=Path(path)
    with p.open('rb') as f: h=f.read(54)
    if len(h)<54 or h[:2]!=b'BM': raise PackError(f'{p.name}: invalid/truncated BMP')
    size,offset=struct.unpack_from('<I',h,2)[0],struct.unpack_from('<I',h,10)[0]
    dib,w,height,planes,bits,compression=struct.unpack_from('<IiiHHI',h,14)
    stride=(w*3+3)&~3
    if not (dib>=40 and 1<=w<=1920 and 1<=abs(height)<=1080 and planes==1 and bits==24 and compression==0):
        raise PackError(f'{p.name}: need uncompressed RGB24 BMP, width<=1920, height<=1080')
    if size!=p.stat().st_size or offset<14+dib or offset+stride*abs(height)>size:
        raise PackError(f'{p.name}: truncated/inconsistent BMP size or pixel offset')
    return {'path':str(p.resolve()),'name':p.name,'size_bytes':size,'width':w,'height':height}

def wav_info(path):
    try:
        with wave.open(str(path),'rb') as f:
            if (f.getframerate(),f.getnchannels(),f.getsampwidth(),f.getcomptype())!=(48000,2,2,'NONE'):
                raise PackError('WAV must be 48000 Hz, stereo, signed 16-bit PCM')
            frames=f.getnframes()
            if frames<128: raise PackError('WAV must contain at least 128 stereo frames')
    except (wave.Error,EOFError) as e: raise PackError(f'Invalid/uncompressed PCM WAV required: {e}') from e
    return frames

def pack_images(images_dir,wav_path,output_path):
    folder=Path(images_dir)
    if not folder.is_dir(): raise PackError('Photo directory does not exist')
    paths=sorted((p for p in folder.iterdir() if p.is_file() and p.suffix.lower()=='.bmp'),key=lambda p:p.name)
    if not 1<=len(paths)<=4: raise PackError('Provide 1..4 BMP photos')
    photos=[inspect_bmp(p) for p in paths]
    frames=wav_info(wav_path)
    photo_end=1
    for p in photos:
        p['start_sector']=photo_end
        photo_end+=(p['size_bytes']+511)//512
        p['end_sector_exclusive']=photo_end
    total=photo_end+(frames*4+511)//512
    if total*512>MAX_IMAGE_BYTES: raise PackError('Image exceeds the first version 512 MiB limit')
    text=str(output_path)
    if text.replace(chr(92),'/').startswith(('//./','//?/','/dev/')): raise PackError('Output must be an image file')
    out=Path(output_path).resolve()
    if not out.parent.is_dir() or out.is_dir(): raise PackError('Output file directory does not exist')
    if out in {Path(p['path']) for p in photos}|{Path(wav_path).resolve()}: raise PackError('Output must differ from inputs')
    image_hash=hashlib.sha256();audio_hash=hashlib.sha256()
    header=struct.pack('<4s9I',b'HXAU',1,48000,2,16,photo_end,frames,photo_end,len(photos),total)
    with out.open('wb') as target:
        def emit(data): target.write(data);image_hash.update(data)
        emit(header+bytes(512-len(header)))
        for p in photos:
            digest=hashlib.sha256()
            with Path(p['path']).open('rb') as f:
                for data in iter(lambda:f.read(65536),b''):
                    emit(data);digest.update(data)
            emit(bytes((-p['size_bytes'])%512));p['sha256']=digest.hexdigest()
        with wave.open(str(wav_path),'rb') as f:
            left=frames
            while left:
                count=min(left,16384);data=f.readframes(count)
                if len(data)!=count*4: raise PackError('Truncated WAV PCM data')
                emit(data);audio_hash.update(data);left-=count
        emit(bytes((-(frames*4))%512))
    report={'format':'HXAU v1','sector_size':512,'header':{
        'version':1,'sample_rate':48000,'channels':2,'bits_per_sample':16,
        'audio_start_sector':photo_end,'audio_frame_count':frames,
        'photo_end_sector_exclusive':photo_end,'photo_count':len(photos),'total_image_sectors':total},
        'output':{'path':str(out),'size_bytes':total*512,'sha256':image_hash.hexdigest()},
        'photos':photos,'audio':{'path':str(Path(wav_path).resolve()),'frame_count':frames,
        'seconds':frames/48000,'payload_sha256':audio_hash.hexdigest()}}
    Path(str(out)+'.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return report

def generate_demo_wav(path,seconds=12):
    notes=[261.63,329.63,392,293.66,523.25,440,659.25,329.63]
    total=int(seconds*48000);per_note=max(1,total//len(notes))
    with wave.open(str(path),'wb') as f:
        f.setparams((2,2,48000,0,'NONE','not compressed'))
        for start in range(0,total,4800):
            block=bytearray()
            for i in range(start,min(start+4800,total)):
                n=min(i//per_note,len(notes)-1);pos=(i%per_note)/per_note
                level=(0.8 if n%2==0 else 0.08)*min(1,pos*40,(1-pos)*30)
                l=int(32767*level*math.sin(2*math.pi*notes[n]*i/48000))
                r=int(28000*level*math.sin(math.pi*notes[n]*i/48000))
                block.extend(struct.pack('<hh',l,r))
            f.writeframes(block)
    return str(Path(path).resolve())

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--images');p.add_argument('--wav');p.add_argument('--output');p.add_argument('--demo-wav')
    a=p.parse_args(argv)
    try:
        if a.demo_wav:
            generate_demo_wav(a.demo_wav);a.wav=a.wav or a.demo_wav
            if not a.images and not a.output: print('Generated',a.demo_wav);return 0
        if not all((a.images,a.wav,a.output)): p.error('Packing requires --images DIR --wav FILE --output FILE')
        report=pack_images(a.images,a.wav,a.output)
        print(json.dumps(report['output'],indent=2));print('Photos:',len(report['photos']),'Audio seconds:',report['audio']['seconds'])
    except (PackError,OSError) as e: print('ERROR:',e);return 2
    return 0
if __name__=='__main__': raise SystemExit(main())
