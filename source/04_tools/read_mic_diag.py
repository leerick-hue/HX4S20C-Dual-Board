#!/usr/bin/env python3
"""Read MD01 48-byte microphone diagnostic frames from UART1 (host side only).

Usage:
  python tools/read_mic_diag.py --port COM3 --seconds 8 --output capture.json
  python tools/read_mic_diag.py --self-test
"""

import argparse
import json
import math
import random
import struct
import sys
import time

HEADER = (0xC3, 0x3C)
PROTOCOL = 1
LENGTH = 48
TAG = b"MD01"
FRAME_LEN = LENGTH
BAUD = 1000000
READ_SIZE = 256
READ_TIMEOUT = 0.05

CRC_POLY = 0x07
STAT_KEYS = (
    "bytes_read", "reads", "read_timeouts", "read_errors",
    "frames_ok", "crc_errors", "version_errors", "length_errors",
    "tag_errors", "discarded_bytes", "port_open_errors",
)


def crc8(data):
    """CRC-8, poly 0x07, init 0x00, MSB first."""
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ CRC_POLY) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def u32(data, off):
    return struct.unpack_from("<I", data, off)[0]


def i16(data, off):
    return struct.unpack_from("<h", data, off)[0]


def s24(data, off):
    val = data[off] | (data[off + 1] << 8) | (data[off + 2] << 16)
    return val - (1 << 24) if val & 0x800000 else val


def s24_bytes(val):
    val &= 0xFFFFFF
    return bytes([val & 0xFF, (val >> 8) & 0xFF, (val >> 16) & 0xFF])


def wrap32(new, old):
    """Difference of two cumulative uint32 counters, wrap aware."""
    return (new - old) & 0xFFFFFFFF


FLAG_BITS = ((0, "sck"), (1, "ws"), (2, "sd"))


def decode_frame(raw):
    """Return (frame_dict, None) or (None, reject_reason)."""
    if len(raw) != FRAME_LEN:
        return None, "length"
    if raw[0] != HEADER[0] or raw[1] != HEADER[1]:
        return None, "header"
    if raw[2] != PROTOCOL:
        return None, "version"
    if raw[3] != LENGTH:
        return None, "length"
    if raw[4:8] != TAG:
        return None, "tag"
    if crc8(raw[2:47]) != raw[47]:
        return None, "crc"
    flags = raw[37]
    return {
        "frame_seq": u32(raw, 8),
        "sd_edges": u32(raw, 12),
        "left_min": s24(raw, 16),
        "left_max": s24(raw, 19),
        "right_min": s24(raw, 22),
        "right_max": s24(raw, 25),
        "ref_min": i16(raw, 28),
        "ref_max": i16(raw, 30),
        "agc_min": i16(raw, 32),
        "agc_max": i16(raw, 34),
        "gain": raw[36],
        "flags": flags,
        "flags_bits": {name: (flags >> bit) & 1 for bit, name in FLAG_BITS},
        "left_samples": u32(raw, 38),
        "right_samples": u32(raw, 42),
        "dropped": raw[46],
        "raw_hex": raw.hex(),
    }, None


def encode_frame(seq=0, sd_edges=0, left_min=-1000, left_max=1000,
                 right_min=-2000, right_max=2000, ref_min=-3, ref_max=4,
                 agc_min=-5, agc_max=6, gain=7, flags=0b111, left_samples=0,
                 right_samples=0, dropped=0, protocol=PROTOCOL, length=LENGTH,
                 tag=TAG, bad_crc=False):
    """Build a frame; keyword overrides exist for the self-test only."""
    body = bytearray()
    body.append(protocol)
    body.append(length)
    body += tag
    body += struct.pack("<II", seq & 0xFFFFFFFF, sd_edges & 0xFFFFFFFF)
    body += s24_bytes(left_min) + s24_bytes(left_max)
    body += s24_bytes(right_min) + s24_bytes(right_max)
    body += struct.pack("<hhhh", ref_min, ref_max, agc_min, agc_max)
    body.append(gain)
    body.append(flags)
    body += struct.pack("<II", left_samples & 0xFFFFFFFF,
                        right_samples & 0xFFFFFFFF)
    body.append(dropped)
    crc = crc8(body)
    if bad_crc:
        crc ^= 0xFF
    return bytes(bytearray(HEADER) + body + bytes([crc]))


class Decoder:
    """Stream decoder: keeps a tail, resyncs one byte at a time."""

    def __init__(self):
        self.buf = bytearray()
        self.stats = {key: 0 for key in STAT_KEYS}

    def feed(self, data):
        self.buf.extend(data)
        return self._drain()

    def _reject(self, reason):
        bucket = {"crc": "crc_errors", "version": "version_errors",
                  "length": "length_errors", "tag": "tag_errors"}.get(reason)
        if bucket:
            self.stats[bucket] += 1
        self.stats["discarded_bytes"] += 1

    def _drain(self):
        frames = []
        while len(self.buf) >= FRAME_LEN:
            head = self.buf.find(bytes(HEADER))
            if head < 0:
                keep = 1 if self.buf.endswith(bytes(HEADER[:1])) else 0
                drop = len(self.buf) - keep
                self.stats["discarded_bytes"] += drop
                del self.buf[:drop]
                break
            if head > 0:
                self.stats["discarded_bytes"] += head
                del self.buf[:head]
            if len(self.buf) < FRAME_LEN:
                break
            frame, reason = decode_frame(bytes(self.buf[:FRAME_LEN]))
            if frame is not None:
                self.stats["frames_ok"] += 1
                frames.append(frame)
                del self.buf[:FRAME_LEN]
            else:
                self._reject(reason)
                del self.buf[:1]  # byte-wise resync
        return frames


def classify(stats, port_error=None):
    """'no frames' is never a success."""
    if port_error:
        return False, "port_error: %s" % port_error
    if stats["frames_ok"] == 0:
        if stats["bytes_read"] == 0:
            return False, "no_frames: UART carried no bytes"
        if stats["crc_errors"]:
            return False, "no_frames: bytes arrived but every candidate failed CRC"
        if stats["version_errors"] or stats["length_errors"] or stats["tag_errors"]:
            return False, "no_frames: header found but version/length/tag rejected"
        return False, "no_frames: no C3 3C frame ever assembled"
    return True, "ok"


def live_capture(port, seconds):
    decoder = Decoder()
    frames = []
    try:
        import serial
    except ImportError as exc:
        decoder.stats["port_open_errors"] += 1
        return decoder.stats, [], "pyserial unavailable: %s" % exc
    try:
        ser = serial.Serial(port, BAUD, bytesize=8, parity="N", stopbits=1,
                            timeout=READ_TIMEOUT)
    except Exception as exc:
        decoder.stats["port_open_errors"] += 1
        return decoder.stats, [], "cannot open %s: %s" % (port, exc)

    ser.reset_input_buffer()
    started = time.monotonic()  # measured after open and flushing stale bytes
    last_report = started
    last = {"sd_edges": None, "left_samples": None, "right_samples": None}
    window = []
    try:
        while True:
            now = time.monotonic()
            if now - started >= seconds:
                break
            try:
                chunk = ser.read(READ_SIZE)
            except Exception as exc:
                decoder.stats["read_errors"] += 1
                print("  read error: %s" % exc)
                continue
            decoder.stats["reads"] += 1
            if not chunk:
                decoder.stats["read_timeouts"] += 1
                continue
            decoder.stats["bytes_read"] += len(chunk)
            for frame in decoder.feed(chunk):
                frames.append(frame)
                window.append(frame)

            if time.monotonic() - last_report >= 1.0:
                elapsed = time.monotonic() - started
                print(window_line(elapsed, window, last, decoder.stats))
                for key in last:
                    if window:
                        last[key] = window[-1][key]
                window = []
                last_report = time.monotonic()
    finally:
        ser.close()
    decoder.stats["trailing_bytes"] = len(decoder.buf)
    decoder.stats["elapsed_seconds"] = time.monotonic() - started
    if window:
        print(window_line(time.monotonic() - started, window, last, decoder.stats))
    return decoder.stats, frames, None


def flag_names(flags):
    return "|".join(name.upper() for bit, name in FLAG_BITS
                    if (flags >> bit) & 1) or "-"


def window_line(elapsed, window, last, stats):
    if not window:
        return "t=%5.2fs frames=0 (nothing decoded) crc_err=%d" % (
            elapsed, stats["crc_errors"])
    left = (min(f["left_min"] for f in window), max(f["left_max"] for f in window))
    right = (min(f["right_min"] for f in window), max(f["right_max"] for f in window))
    parts = ["t=%5.2fs" % elapsed, "frames=%d" % len(window),
             "left[%d..%d]" % left, "right[%d..%d]" % right,
             "gain=%d" % window[-1]["gain"],
             "flags=%s" % flag_names(window[-1]["flags"]),
             "crc_err=%d" % stats["crc_errors"]]
    for key, label in (("sd_edges", "sd_edges/s"), ("left_samples", "L/s"),
                       ("right_samples", "R/s")):
        new, prev = window[-1][key], last[key]
        parts.append("%s=%s" % (label, "n/a" if prev is None
                                else "+%d" % wrap32(new, prev)))
    parts.append("seq=%d" % window[-1]["frame_seq"])
    return " ".join(parts)


CAUTION = (
    "Caution: static raw values can come from the mic clocks, power, the I2S "
    "channel/SD line or this receiver -- they do not by themselves prove the "
    "audio path is dead. Likewise SCK/WS/SD flag toggles only prove the FPGA saw "
    "digital transitions, not real analog audio or physically valid clock levels. "
    "Cross-check with a scope/analyzer before concluding."
)


def run(args):
    if args.self_test:
        return self_test()
    stats, frames, port_error = live_capture(args.port, args.seconds)
    stats = stats or {key: 0 for key in STAT_KEYS}
    ok, reason = classify(stats, port_error)
    totals = {}
    if frames:
        for key in ("sd_edges", "left_samples", "right_samples"):
            totals[key] = frames[-1][key]
        # The board reports a saturating cumulative counter, not a per-frame delta.
        totals["board_reported_dropped"] = frames[-1]["dropped"]
        totals["missing_frames"] = 0
        totals["duplicate_frames"] = 0
        totals["backward_sequence_events"] = 0
        for before, after in zip(frames, frames[1:]):
            step = wrap32(after["frame_seq"], before["frame_seq"])
            if step == 0:
                totals["duplicate_frames"] += 1
            elif step > 0x80000000:
                totals["backward_sequence_events"] += 1
            else:
                totals["missing_frames"] += step - 1
        totals["min_span"] = {"left": [min(f["left_min"] for f in frames),
                                       max(f["left_max"] for f in frames)],
                              "right": [min(f["right_min"] for f in frames),
                                        max(f["right_max"] for f in frames)]}
        totals["left_static"] = all(f["left_min"] == f["left_max"] == frames[0]["left_min"] for f in frames)
        totals["right_static"] = all(f["right_min"] == f["right_max"] == frames[0]["right_min"] for f in frames)
    result = {
        "meta": {"port": args.port, "seconds": args.seconds, "baud": BAUD,
                 "frame": "MD01 48B header C3 3C crc8-poly07",
                 "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())},
        "stats": stats,
        "totals": totals,
        "verdict": {"ok": ok, "reason": reason},
        "frames": frames,
    }
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=1)
    print()
    print("frames=%d bytes=%d crc_err=%d discard=%d" % (
        stats["frames_ok"], stats["bytes_read"], stats["crc_errors"],
        stats["discarded_bytes"]))
    print("VERDICT: %s -- %s" % ("OK" if ok else "FAIL", reason))
    print(CAUTION)
    print("saved %s" % args.output)
    return 0 if ok else 2


def self_test():
    checks = []

    def check(name, cond):
        checks.append((name, bool(cond)))

    check("crc8 known vector", crc8(b"123456789") == 0xF4)
    check("short frame rejected", decode_frame(b"")[1] == "length")

    # signed24 extremes and round trip
    f = decode_frame(encode_frame(left_min=-8388608, left_max=8388607,
                                  right_min=-1, right_max=0))[0]
    check("signed24 extremes", (f["left_min"], f["left_max"], f["right_min"],
                                f["right_max"]) == (-8388608, 8388607, -1, 0))
    vals = [-8388608, -4096, -1, 0, 1, 32767, 8388607]
    check("signed24 round trip",
          all(decode_frame(encode_frame(left_min=v, left_max=v))
              [0]["left_min"] == v for v in vals))
    check("s24 little endian bytes", s24_bytes(-1) == b"\xff\xff\xff")

    # full field round trip
    raw = encode_frame(seq=1234, sd_edges=5678, ref_min=-2000, ref_max=1999,
                       agc_min=-30000, agc_max=30000, gain=255, flags=0b101,
                       left_samples=999, right_samples=1001, dropped=3)
    f = decode_frame(raw)[0]
    check("field round trip", (f["frame_seq"], f["sd_edges"], f["ref_min"],
                               f["ref_max"], f["agc_min"], f["agc_max"], f["gain"],
                               f["flags"], f["left_samples"], f["right_samples"],
                               f["dropped"], f["flags_bits"]["ws"])
          == (1234, 5678, -2000, 1999, -30000, 30000, 255, 5, 999, 1001, 3, 0))

    # split packets: odd chunk sizes, two frames back to back
    d = Decoder()
    stream = encode_frame(seq=1) + encode_frame(seq=2)
    got, i, step = [], 0, 1
    while i < len(stream):
        n = min(step, len(stream) - i)
        got += d.feed(stream[i:i + n])
        i += n
        step = 5 if step == 1 else 1
    check("split packets decode", [g["frame_seq"] for g in got] == [1, 2]
          and d.stats["frames_ok"] == 2 and d.stats["crc_errors"] == 0)

    # corruption: one flipped payload byte is a CRC error, not a frame
    d = Decoder()
    bad = bytearray(encode_frame(seq=1))
    bad[17] ^= 0x01
    check("corruption rejected", d.feed(bytes(bad)) == []
          and d.stats["crc_errors"] == 1 and d.stats["frames_ok"] == 0)

    # crc resync: good frame still lands after a corrupted one
    d = Decoder()
    out = d.feed(encode_frame(seq=1, bad_crc=True) + encode_frame(seq=2))
    check("resync after bad crc", [o["frame_seq"] for o in out] == [2]
          and d.stats["crc_errors"] == 1 and d.stats["discarded_bytes"] > 0)

    # byte-wise resync through a fake header and mid-frame noise
    d = Decoder()
    junk = bytes(HEADER) + b"\x00MD01" + bytes(range(40))
    out = d.feed(junk + encode_frame(seq=7))
    check("resync to real header", [o["frame_seq"] for o in out] == [7]
          and d.stats["discarded_bytes"] >= 1)

    # header split across reads must not be dropped
    d = Decoder()
    tail = encode_frame(seq=8)
    out = d.feed(b"abc\x00" + tail[:1]) + d.feed(tail[1:])
    check("header kept across reads", [o["frame_seq"] for o in out] == [8]
          and d.stats["discarded_bytes"] == 4)

    # wrong version / length / tag each counted in their own bucket
    for kw, key in (({"protocol": 2}, "version_errors"),
                    ({"length": 47}, "length_errors"),
                    ({"tag": b"MD02"}, "tag_errors")):
        d = Decoder()
        check("reject %s" % kw, d.feed(encode_frame(**kw)) == []
              and d.stats[key] == 1 and d.stats["frames_ok"] == 0)

    # noise: never crashes, never invents a frame
    rnd = random.Random(20261102)
    d = Decoder()
    for _ in range(60):
        d.feed(bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 300))))
    check("noise yields no frames", d.stats["frames_ok"] == 0)
    check("noise classified fail", classify(d.stats)[0] is False)

    # nonzero starting seq + uint32 wrap on every cumulative counter
    check("wrap32", wrap32(2, 0xFFFFFFFE) == 4 and wrap32(0, 0xFFFFFFFF) == 1)
    d = Decoder()
    seqs = [0xFFFFFFF0 + i for i in range(16 + 3)]
    out = d.feed(b"".join(encode_frame(seq=s & 0xFFFFFFFF,
                                       sd_edges=0xFFFFFFF8 + n,
                                       left_samples=0xFFFFFFF8 + n,
                                       right_samples=0xFFFFFFF8 + n)
                          for n, s in enumerate(seqs)))
    check("seq wrap decode", [o["frame_seq"] for o in out[:3]]
          == [0xFFFFFFF0, 0xFFFFFFF1, 0xFFFFFFF2])
    deltas = [wrap32(b["sd_edges"], a["sd_edges"]) for a, b in zip(out, out[1:])]
    check("cumulative wrap delta", deltas and set(deltas) == {1}
          and out[0]["frame_seq"] != 0)
    check("first seq need not be 0", out[0]["frame_seq"] != 0)

    # classify: empty port vs bytes-but-no-frame vs healthy
    st = {k: 0 for k in STAT_KEYS}
    check("classify no bytes", classify(st)[0] is False)
    st2 = dict(st, bytes_read=512)
    ok, why = classify(st2)
    check("classify bytes no frame", ok is False and "no_frames" in why)
    st3 = dict(st, bytes_read=512, crc_errors=4)
    check("classify crc only", "CRC" in classify(st3)[1] and classify(st3)[0] is False)
    st4 = dict(st, bytes_read=512, frames_ok=3)
    check("classify ok", classify(st4) == (True, "ok"))

    # live_capture without hardware must report an open error, not fake success
    stats, frames, err = live_capture("__no_such_port__", 0.2)
    check("missing port error", err and stats["port_open_errors"] == 1
          and not frames and classify(stats, err)[0] is False)

    failed = [name for name, passed in checks if not passed]
    for name, passed in checks:
        print("%s %s" % ("PASS" if passed else "FAIL", name))
    print("%d/%d checks passed" % (len(checks) - len(failed), len(checks)))
    if failed:
        print("FAILED: " + ", ".join(failed))
    return 1 if failed else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", default="COM3", help="serial port (default COM3)")
    ap.add_argument("--seconds", type=float, default=8.0, help="capture window")
    ap.add_argument("--output", default="capture.json", help="JSON capture file")
    ap.add_argument("--self-test", action="store_true", help="run tests, no hardware")
    args = ap.parse_args(argv)
    if not math.isfinite(args.seconds) or args.seconds <= 0:
        ap.error("--seconds must be finite and positive")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
