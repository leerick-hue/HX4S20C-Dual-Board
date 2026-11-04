"""Independent file-format acceptance tests, using known BMP/WAV bytes."""
from pathlib import Path
import hashlib,json,struct,tempfile,unittest,wave
from pack_tf_audio import pack_images,PackError,generate_demo_wav

def bmp(w,h):
    payload=bytes((i*17+3)%256 for i in range(((w*3+3)&~3)*abs(h)))
    return b'BM'+struct.pack('<IHHI',54+len(payload),0,0,54)+struct.pack('<IiiHHIIiiII',40,w,h,1,24,0,len(payload),0,0,0,0)+payload

def wav(path,frames=257,rate=48000,ch=2,width=2):
    data=b''.join(struct.pack('<hh',(i*173)%65536-32768,32767-(i*67)%65536) for i in range(frames))
    with wave.open(str(path),'wb') as f:
        f.setparams((ch,width,rate,0,'NONE','not compressed'));f.writeframes(data)
    return data

class Acceptance(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.images=self.root/'photos';self.images.mkdir()
        self.audio=self.root/'music.wav';self.output=self.root/'card.img'
    def test_exact_layout_audio_and_padding(self):
        for count,frames in ((1,257),(4,256)):
            with self.subTest(count=count,frames=frames):
                originals=[]
                for i in range(count):
                    content=bmp(3+i,-(2+i) if i%2 else 2+i)
                    (self.images/f'{i}.BMP').write_bytes(content);originals.append(content)
                pcm=wav(self.audio,frames);report=pack_images(self.images,self.audio,self.output)
                blob=self.output.read_bytes();head=struct.unpack_from('<4s9I',blob)
                end=1+sum((len(b)+511)//512 for b in originals)
                total=end+(len(pcm)+511)//512
                self.assertEqual(head,(b'HXAU',1,48000,2,16,end,frames,end,count,total))
                self.assertEqual(blob[40:512],bytes(472));self.assertEqual(len(blob),total*512)
                sector=1
                for original in originals:
                    at=sector*512;self.assertEqual(blob[at:at+len(original)],original)
                    padded=((len(original)+511)//512)*512
                    self.assertEqual(blob[at+len(original):at+padded],bytes(padded-len(original)))
                    sector+=padded//512
                self.assertEqual(blob[end*512:end*512+len(pcm)],pcm)
                self.assertEqual(blob[end*512+len(pcm):],bytes((-len(pcm))%512))
                saved=json.loads(Path(str(self.output)+'.json').read_text())
                self.assertEqual(saved['output']['sha256'],hashlib.sha256(blob).hexdigest())
                self.assertEqual(report['audio']['payload_sha256'],hashlib.sha256(pcm).hexdigest())
    def test_reject_unsupported_audio(self):
        (self.images/'a.bmp').write_bytes(bmp(3,2))
        for kw in ({'rate':44100},{'ch':1},{'width':1},{'frames':1}):
            with self.subTest(kw=kw):
                wav(self.audio,**kw)
                with self.assertRaises(PackError):pack_images(self.images,self.audio,self.output)
    def test_reject_empty_or_truncated_photos(self):
        wav(self.audio)
        with self.assertRaises(PackError):pack_images(self.images,self.audio,self.output)
        (self.images/'a.bmp').write_bytes(bmp(3,2)[:-1])
        with self.assertRaises(PackError):pack_images(self.images,self.audio,self.output)
    def test_truncated_audio_is_not_accepted(self):
        (self.images/'a.bmp').write_bytes(bmp(3,2));wav(self.audio)
        b=self.audio.read_bytes();self.audio.write_bytes(b[:-4])
        with self.assertRaises(PackError):pack_images(self.images,self.audio,self.output)
    def test_demo_has_loud_and_quiet_sections(self):
        generate_demo_wav(self.audio)
        with wave.open(str(self.audio),'rb') as f:
            self.assertEqual((f.getframerate(),f.getnchannels(),f.getsampwidth(),f.getnframes()),(48000,2,2,576000))
            samples=struct.unpack('<'+str(576000*2)+'h',f.readframes(576000))
        loud=max(abs(v) for v in samples[24000:72000]);quiet=max(abs(v) for v in samples[168000:216000])
        self.assertGreater(loud,quiet*5)
if __name__=='__main__':unittest.main()
