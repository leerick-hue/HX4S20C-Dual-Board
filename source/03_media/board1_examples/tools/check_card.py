r"""校验 HXAU 相册卡：打印文件头字段，并可逐字节比对参考镜像。

用于"写完卡先验卡再上板"这一步。只读，不写任何设备。

用法:
    py -3 tools/check_card.py E:/HX4S20C_Test_20261026/album_source.img
    py -3 tools/check_card.py --ref E:/HX4S20C_Test_20261026/album_source.img \\.\E:

TARGET 既可以是 .img 文件，也可以是物理盘符（\\\\.\\X:，需要管理员权限）。
物理盘只读参考镜像长度那么多字节，不会碰卡上其余内容。
"""
from __future__ import annotations

import argparse
import hashlib
import struct
import sys

SECTOR = 512
HEADER = struct.Struct("<4s8I")
FIELDS = ("version", "sample_rate", "channels", "bits_per_sample",
          "audio_start_lba", "audio_sample_frames",
          "photo_end_sector_exclusive", "photo_count")
MAGIC = b"HXAU"
PATCH_MAGIC = b"HXUV"


def read_head(stream, n):
    data = b""
    while len(data) < n:
        chunk = stream.read(n - len(data))
        if not chunk:
            break
        data += chunk
    return data


def parse_header(head: bytes):
    if len(head) < HEADER.size:
        raise SystemExit("ERROR: 读到的数据不足 20 字节，不是 HXAU 镜像")
    if head[:4] != MAGIC:
        raise SystemExit(f"ERROR: 魔数不是 HXAU，实际是 {head[:4]!r}"
                         "（卡没写进去，或者写成了 FAT32 文件拷贝）")
    values = HEADER.unpack_from(head, 0)
    info = dict(zip(FIELDS, values[1:]))
    patch = head[36:36 + 16]
    info["hxuv_patch"] = patch[:4] == PATCH_MAGIC
    if info["hxuv_patch"]:
        info["video_base_lba"], info["video_sectors"], info["total_sectors"] = \
            struct.unpack_from("<3I", head, 40)
    audio_bytes = (info["audio_sample_frames"] * info["channels"]
                   * max(1, info["bits_per_sample"] // 8))
    info["photo_bytes"] = info["photo_end_sector_exclusive"] * SECTOR
    info["audio_bytes"] = audio_bytes
    info["audio_end"] = info["audio_start_lba"] * SECTOR + audio_bytes
    info["payload_bytes"] = max(info["photo_bytes"], info["audio_end"])
    if info["hxuv_patch"] and info.get("total_sectors"):
        info["payload_bytes"] = max(info["payload_bytes"],
                                    info["total_sectors"] * SECTOR)
    return info


def digest(stream, limit):
    stream.seek(0)
    h = hashlib.sha256()
    left = limit
    while left > 0:
        chunk = stream.read(min(1 << 20, left))
        if not chunk:
            break
        h.update(chunk)
        left -= len(chunk)
    return h.hexdigest(), limit - left


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("target", help=r"镜像文件，或物理盘符 \\.\E:")
    ap.add_argument("--ref", help="参考镜像，给出则逐字节比对")
    args = ap.parse_args()

    try:
        with open(args.target, "rb") as stream:
            head = read_head(stream, SECTOR)
            info = parse_header(head)
            print(f"target : {args.target}")
            print(f"  magic        : HXAU v{info['version']}")
            print(f"  照片         : {info['photo_count']} 张，占用 "
                  f"{info['photo_end_sector_exclusive']} 扇区 = {info['photo_bytes']} 字节")
            print(f"  音频         : {info['sample_rate']} Hz / {info['channels']} ch / "
                  f"{info['bits_per_sample']} bit，起始 LBA {info['audio_start_lba']}，"
                  f"{info['audio_sample_frames']} 帧")
            print(f"  音频时长     : {info['audio_sample_frames'] / max(1, info['sample_rate']):.2f} 秒")
            print(f"  含视频段     : {'是' if info['hxuv_patch'] else '否'}")

            if not args.ref:
                return 0

            with open(args.ref, "rb") as ref:
                ref_info = parse_header(read_head(ref, SECTOR))
                limit = ref_info["payload_bytes"]
                want, _ = digest(ref, limit)
                got, n = digest(stream, limit)
                print(f"ref    : {args.ref}")
                print(f"  比对长度     : {limit} 字节（实际读到 {n}）")
                print(f"  参考 SHA256  : {want}")
                print(f"  目标 SHA256  : {got}")
                if n != limit:
                    print("RESULT: FAIL —— 目标数据比参考短，卡可能没写完整或容量不足")
                    return 1
                if want != got:
                    print("RESULT: FAIL —— 前 %d 字节与参考不一致" % limit)
                    return 1
                print("RESULT: PASS —— 前 %d 字节与参考镜像完全一致" % limit)
                return 0
    except PermissionError:
        print("ERROR: 没有权限读取该设备，请用管理员命令行运行", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
