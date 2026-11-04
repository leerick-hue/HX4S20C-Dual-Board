import hashlib
import json
import struct
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = Path("E:/HX4S20C_Extensions/hx4s20c_media_core/board/mjpeg_20261023/decode_sim")
PLAYER_IMG = SRC / "player_fixture" / "player_3frame_30fps.img"
REF_PNGS = [
    SRC / "results_final_reference" / "move0_fast" / "decoded_0.png",
    SRC / "results_final_parser" / "move1_fast" / "decoded_0.png",
    SRC / "results_final_reference" / "move2_fast" / "decoded_0.png",
]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def logical(w, h, mult, add):
    return [
        [
            (lambda v: ((v >> 16) & 255, (v >> 8) & 255, v & 255))(
                (y * w + x) * mult + add
            )
            for x in range(w)
        ]
        for y in range(h)
    ]


def encode_bmp(px, w, h, top_down):
    stride = (w * 3 + 3) & ~3
    pad = b"\x00" * (stride - w * 3)
    body = b"".join(
        b"".join(bytes((px[y][x][2], px[y][x][1], px[y][x][0])) for x in range(w)) + pad
        for y in (range(h) if top_down else range(h - 1, -1, -1))
    )
    size = 54 + len(body)
    hdr = (
        b"BM"
        + struct.pack("<IHHI", size, 0, 0, 54)
        + struct.pack(
            "<IiiHHIIiiII", 40, w, -h if top_down else h, 1, 24, 0, len(body),
            2835, 2835, 0, 0,
        )
    )
    return hdr + body


def verify_bmp(bmp, px, w, h):
    p = HERE / "_verify.bmp"
    p.write_bytes(bmp)
    im = Image.open(p)
    im.load()
    assert im.size == (w, h), im.size
    for y in range(h):
        for x in range(w):
            assert im.getpixel((x, y)) == px[y][x], (x, y)
    p.unlink()


def nearest565(px, w, h, W=1280, H=720):
    vals = [
        (lambda r, g, b: ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))(
            *px[y * h // H][x * w // W]
        )
        for y in range(H)
        for x in range(W)
    ]
    return [vals[i] | (vals[i + 1] << 16) for i in range(0, len(vals), 2)]


def png(path, px, w, h):
    Image.frombytes("RGB", (w, h), b"".join(bytes(c) for row in px for c in row)).save(path)


def hex_words(words):
    return "".join(f"{w:08x}\n" for w in words)


def build():
    photos = [
        dict(w=13, h=9, top_down=False, mult=6700417, add=0x134567),
        dict(w=19, h=11, top_down=True, mult=7919, add=0x984521),
    ]
    bmps = []
    for i, ph in enumerate(photos):
        px = logical(ph["w"], ph["h"], ph["mult"], ph["add"])
        bmp = encode_bmp(px, ph["w"], ph["h"], ph["top_down"])
        assert len(bmp) == (414 if i == 0 else 714), (i, len(bmp))
        verify_bmp(bmp, px, ph["w"], ph["h"])
        (HERE / f"photo{i}.bmp").write_bytes(bmp)
        words = nearest565(px, ph["w"], ph["h"])
        (HERE / f"photo{i}.hex").write_text(hex_words(words))
        png(HERE / f"source{i}.png", px, ph["w"], ph["h"])
        spx = [[px[y * ph["h"] // 720][x * ph["w"] // 1280] for x in range(1280)] for y in range(720)]
        png(HERE / f"stretch{i}.png", spx, 1280, 720)
        bmps.append(dict(data=bmp, px=px, words=words, **ph))

    pcm = b"".join(struct.pack("<hh", 1000 + 13 * n, -2000 - 7 * n) for n in range(512))
    pcm_words = struct.unpack(f"<{len(pcm) // 4}I", pcm)
    (HERE / "pcm_album.hex").write_text(hex_words(pcm_words))

    player = PLAYER_IMG.read_bytes()
    assert len(player) % 512 == 0, len(player)
    video_sectors = len(player) // 512
    audio_start, audio_frames = struct.unpack_from("<II", player, 48)
    off = audio_start * 512
    assert player[:4] == b"HXJV" and audio_frames == 4800
    assert off + audio_frames * 4 <= len(player), (off, audio_frames, len(player))
    pcm_video = player[off : off + audio_frames * 4]
    (HERE / "pcm_video.hex").write_text(
        hex_words(struct.unpack(f"<{len(pcm_video) // 4}I", pcm_video))
    )

    header = struct.pack(
        "<13I", 0x55415848, 1, 48000, 2, 16, 4, 512, 4, 2,
        0x56555848, 8, video_sectors, 8 + video_sectors,
    ).ljust(512, b"\x00")
    combined = (
        header
        + bmps[0]["data"].ljust(512, b"\x00")
        + bmps[1]["data"].ljust(1024, b"\x00")
        + pcm
        + player
    )
    assert len(combined) == (8 + video_sectors) * 512
    assert combined[8 * 512:] == player
    (HERE / "combined.img").write_bytes(combined)
    (HERE / "combined.hex").write_text("".join(f"{b:02x}\n" for b in combined))

    videos = []
    for i, ref in enumerate(REF_PNGS):
        data = ref.read_bytes()
        im = Image.open(ref)
        im.load()
        rgb = im.convert("RGB")
        assert rgb.size == (640, 480)
        vals = [
            ((p[0] >> 3) << 11) | ((p[1] >> 2) << 5) | (p[2] >> 3)
            for p in rgb.getdata()
        ]
        words = [vals[j] | (vals[j + 1] << 16) for j in range(0, len(vals) & ~1, 2)]
        (HERE / f"video{i}.hex").write_text(hex_words(words))
        videos.append(
            dict(
                source=str(ref.relative_to(SRC)),
                sha256=sha256(data),
                width=rgb.width,
                height=rgb.height,
                even=len(vals) % 2 == 0,
                words=len(words),
            )
        )

    manifest = {
        "inputs": {
            "src_root": str(SRC),
            "player_img": dict(
                source=str(PLAYER_IMG.relative_to(SRC)),
                sha256=sha256(player),
                bytes=len(player),
                sectors=video_sectors,
                hxjv_audio_start_word=12,
                hxjv_audio_frames_word=13,
                audio_start=audio_start,
                audio_frames=audio_frames,
                pcm_byte_offset_in_video=off,
            ),
            "references": videos,
        },
        "photos": [
            dict(
                bmp_bytes=len(b["data"]),
                width=b["w"],
                height=b["h"],
                orientation="top-down" if b["top_down"] else "bottom-up",
                row_stride=(b["w"] * 3 + 3) & ~3,
                row_padding_bytes=(-b["w"] * 3) % 4,
                sha256=sha256(b["data"]),
                lba=1 + i,
                sectors=1 if i == 0 else 2,
                stretch_hex_words=len(b["words"]),
            )
            for i, b in enumerate(bmps)
        ],
        "album_pcm": dict(
            frames=512, channels=2, bits=16,
            formula="L=1000+13*n R=-2000-7*n",
            lba=4, sectors=4, bytes=len(pcm), sha256=sha256(pcm),
        ),
        "hxau_header": list(struct.unpack("<13I", header[:52])),
        "layout": [
            dict(lba=0, sectors=1, item="HXAU header"),
            dict(lba=1, sectors=1, item="photo0.bmp padded"),
            dict(lba=2, sectors=2, item="photo1.bmp padded"),
            dict(lba=4, sectors=4, item="album PCM (stereo s16)"),
            dict(lba=8, sectors=video_sectors, item="player_3frame_30fps.img"),
        ],
        "combined": dict(bytes=len(combined), sha256=sha256(combined)),
    }
    manifest["generated_files_sha256"] = {
        p.name: sha256(p.read_bytes()) for p in HERE.iterdir()
        if p.suffix in (".img", ".bmp", ".hex", ".png", ".py")
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest


if __name__ == "__main__":
    print(json.dumps(build(), indent=2))
