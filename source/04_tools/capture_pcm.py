#!/usr/bin/env python3
"""PC-side microphone capture over UART.

Board sends 6-byte packets: A5 5A sample_lo sample_hi seq8 crc8
CRC-8 poly=0x07 init=0, over (lo, hi, seq), MSB-first, no xorout/reflection.
Captured samples are stitched into a 16 kHz mono 16-bit PCM WAV file.
"""

import argparse
import json
import math
from pathlib import Path
import struct
import sys
import time
import wave

HEADER = b"\xa5\x5a"
PACKET_LEN = 6
BAUD = 1000000
SAMPLE_RATE = 16000
MAX_READ = 256
MAX_TIMEOUT = 0.05


def crc8(data, crc=0):
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x07) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc


def make_packet(sample, seq):
    lo_hi = struct.pack("<h", sample)
    payload = lo_hi + bytes([seq & 0xFF])
    return HEADER + payload + bytes([crc8(payload)])


def decode_bytes(data):
    """Return (signed sample/sequence records, incomplete tail, CRC/junk stats).

    Valid frames consume all six bytes, including payload containing A5 5A.
    CRC failures advance one byte to recover a real header in a damaged frame.
    """
    records = []
    pos = crc_errors = discarded = 0
    while True:
        start = data.find(HEADER, pos)
        if start < 0:
            keep = len(data) - 1 if data[pos:].endswith(b"\xa5") else len(data)
            discarded += keep - pos
            return records, data[keep:], {"crc_errors": crc_errors,
                                          "discarded_bytes": discarded}
        discarded += start - pos
        if len(data) - start < PACKET_LEN:
            return records, data[start:], {"crc_errors": crc_errors,
                                           "discarded_bytes": discarded}
        payload = data[start + 2:start + 5]
        if crc8(payload) != data[start + 5]:
            crc_errors += 1
            discarded += 1
            pos = start + 1
        else:
            records.append((struct.unpack_from("<h", payload)[0], payload[2]))
            pos = start + PACKET_LEN


def stitch_pcm(records, last_sequence=None):
    """Convert (sample, seq) records to little-endian int16 PCM bytes.

    Sequence gaps (mod 256) are filled with zero samples and counted in
    stats["missing_samples"]; a record whose seq equals the previous seq is
    dropped as a duplicate. An 8-bit sequence cannot detect losses that are
    exact multiples of 256 samples.
    """
    out = bytearray()
    missing = 0
    duplicates = 0
    last = last_sequence
    for sample, seq in records:
        if last is not None:
            if seq == last:
                duplicates += 1
                continue
            gap = (seq - (last + 1)) & 0xFF
            if gap:
                out.extend(b"\x00\x00" * gap)
                missing += gap
        out.extend(struct.pack("<h", sample))
        last = seq
    return bytes(out), last, {"missing_samples": missing,
                              "duplicates": duplicates}


def write_wav(path, pcm):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)


def capture(port, seconds, output):
    try:
        import serial
    except ImportError:
        print("pyserial is required for capture; install it with: "
              "pip install pyserial", file=sys.stderr)
        return 1

    buf = b""
    records = []
    total_crc = 0
    total_discarded = 0
    try:
        with serial.Serial(port, BAUD, bytesize=8, parity="N",
                           stopbits=1, timeout=MAX_TIMEOUT) as ser:
            ser.reset_input_buffer()
            started = time.perf_counter()
            deadline = started + seconds
            print("Recording %.1f seconds on %s..." % (seconds, port), flush=True)
            while True:
                if time.perf_counter() >= deadline:
                    break
                # A timeout assignment invokes SetCommState on Windows, even
                # when its value is unchanged. Repeating it for every read
                # causes severe CH340 data loss. Keep the port configuration
                # fixed throughout capture; the final read may overrun by at
                # most MAX_TIMEOUT.
                chunk = ser.read(MAX_READ)
                if chunk:
                    records_, buf, stats = decode_bytes(buf + chunk)
                    records.extend(records_)
                    total_crc += stats["crc_errors"]
                    total_discarded += stats["discarded_bytes"]
            elapsed = time.perf_counter() - started
    except serial.SerialException as exc:
        print("serial error on %s: %s" % (port, exc), file=sys.stderr)
        return 1

    pcm, last_seq, sstats = stitch_pcm(records)
    if not records:
        print("error: no valid packets captured on %s (check wiring, "
              "baud %d 8N1, board firmware)" % (port, BAUD),
              file=sys.stderr)
        return 1

    write_wav(output, pcm)
    samples = struct.unpack("<%dh" % (len(pcm) // 2), pcm)
    clipped = sum(s in (-32768, 32767) for s in samples)
    clip_percent = 100.0 * clipped / len(samples)
    valid_rate = len(records) / elapsed
    duration = len(samples) / SAMPLE_RATE
    report = {
        "port": port, "baud": BAUD, "sample_rate": SAMPLE_RATE,
        "requested_seconds": seconds, "elapsed_seconds": elapsed,
        "wav_seconds": duration, "wav_samples": len(samples),
        "valid_packets": len(records), "valid_samples_per_second": valid_rate,
        **sstats, "crc_errors": total_crc,
        "discarded_bytes": total_discarded, "trailing_bytes": len(buf),
        "clipped_samples": clipped, "clipped_percent": clip_percent,
        "peak": max(abs(s) for s in samples),
        "mean": sum(samples) / len(samples),
        "rms": math.sqrt(sum(s * s for s in samples) / len(samples)),
    }
    report_path = Path(output).with_suffix(".capture.json")
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("captured %d frames -> %s" % (len(samples), output))
    print("  elapsed: %.3f s; WAV: %.3f s; valid rate: %.1f samples/s" %
          (elapsed, duration, valid_rate))
    print("  gaps filled: %d samples" % sstats["missing_samples"])
    print("  duplicates skipped: %d" % sstats["duplicates"])
    print("  crc errors: %d" % total_crc)
    print("  discarded bytes: %d" % total_discarded)
    print("  trailing bytes: %d" % len(buf))
    print("  clipped samples: %d (%.2f%%)" % (clipped, clip_percent))
    print("  statistics: %s" % report_path)
    if valid_rate < SAMPLE_RATE * 0.95:
        print("WARNING: capture is missing substantial data; do not use it for voice training.")
    if clip_percent > 0.5:
        print("WARNING: audio is clipped; test at normal speaking distance and lower FPGA input gain if it persists.")
    print("note: 8-bit seq cannot detect losses that are multiples of 256")
    return 0


# ---------------------------------------------------------------- self test

def _check(cond, msg):
    if not cond:
        print("FAIL: %s" % msg)
        return False
    return True


def self_test():
    ok = True

    # CRC-8 standard check value ("123456789")
    ok &= _check(crc8(b"123456789") == 0xF4,
                 "crc8('123456789') == 0xF4, got %02X" % crc8(b"123456789"))

    # roundtrip single packet
    recs, rem, stats = decode_bytes(make_packet(-12345, 7))
    ok &= _check(recs == [(-12345, 7)] and rem == b"" and
                 stats["crc_errors"] == 0 and stats["discarded_bytes"] == 0,
                 "single packet roundtrip")

    # exhaustive 65536 int16 values
    stream = b"".join(make_packet(v, (i * 7) & 0xFF)
                      for i, v in enumerate(range(-32768, 32768)))
    recs, rem, stats = decode_bytes(stream)
    ok &= _check(len(recs) == 65536 and rem == b"" and
                 all(s == v and seq == ((i * 7) & 0xFF)
                     for i, ((s, seq), v) in enumerate(zip(recs, range(-32768, 32768)))) and
                 stats["crc_errors"] == 0,
                 "exhaustive 65536-sample roundtrip")

    # min/max int16 explicitly
    for v in (-32768, 32767):
        recs, _, _ = decode_bytes(make_packet(v, 0))
        ok &= _check(recs == [(v, 0)], "int16 boundary %d" % v)

    # header bytes A5 5A legal inside payload
    recs, rem, stats = decode_bytes(make_packet(0x5AA5, 3))  # lo=A5 hi=5A
    ok &= _check(recs == [(0x5AA5, 3)] and stats["crc_errors"] == 0,
                 "A5 5A inside payload")

    # noisy prefix garbage
    recs, rem, stats = decode_bytes(b"\x00\xff\xa5\x11" + make_packet(100, 1))
    ok &= _check(recs == [(100, 1)] and stats["discarded_bytes"] == 4,
                 "noisy prefix discarded")

    pkt = make_packet(123, 4)
    recs, rem, stats = decode_bytes(b"\xa5\x00" + pkt[2:])
    ok &= _check(recs == [] and rem == b"", "both header bytes required")

    # half packet split: remainder concatenation across calls
    pkt = make_packet(-1, 255)
    for cut in range(1, PACKET_LEN):
        recs1, rem1, _ = decode_bytes(pkt[:cut])
        recs2, rem2, _ = decode_bytes(rem1 + pkt[cut:])
        ok &= _check(recs1 == [] and recs2 == [(-1, 255)] and rem2 == b"",
                     "half packet split at %d" % cut)

    # lone trailing A5 preserved
    recs, rem, stats = decode_bytes(make_packet(1, 1) + b"\xa5")
    ok &= _check(rem == b"\xa5" and stats["discarded_bytes"] == 0 and
                 recs == [(1, 1)], "lone trailing A5 kept")

    # CRC corruption then resync; a valid header nested after byte 1
    bad = bytearray(make_packet(5, 5))
    bad[5] ^= 0xFF
    good = make_packet(6, 6)
    recs, rem, stats = decode_bytes(bytes(bad) + good)
    ok &= _check(recs == [(6, 6)] and stats["crc_errors"] == 1,
                 "corrupt CRC packet rejected, next packet decoded")

    # corrupt packet whose bytes 2..3 look like a header must not resync there
    fake = bytearray(make_packet(0x5AA5, 9))
    fake[5] ^= 0xFF  # corrupt crc, payload carries A5 5A
    recs, rem, _ = decode_bytes(bytes(fake) + make_packet(1, 10))
    ok &= _check(len(recs) == 1 and recs[0] == (1, 10),
                 "no false sync inside corrupt A5 5A payload")

    # streamed chunking of a multi-packet mix
    mix = (b"\xaa\x55" + make_packet(7, 0) + make_packet(0x5AA5, 1) +
           b"\xa5\x5a" + make_packet(-7, 2) + b"\xa5")
    chunks = [mix[i:i + 3] for i in range(0, len(mix), 3)]
    rem = b""
    got = []
    crc_err = 0
    for c in chunks:
        r, rem, st = decode_bytes(rem + c)
        got.extend(r)
        crc_err += st["crc_errors"]
    ok &= _check(got == [(7, 0), (0x5AA5, 1), (-7, 2)] and rem == b"\xa5" and
                 crc_err >= 1, "chunked stream decode with garbage between")

    # stitch: first seq arbitrary, wrap 255 -> 0 without gap
    pcm, last, sstats = stitch_pcm([(10, 254), (20, 255), (30, 0), (40, 1)])
    ok &= _check(last == 1 and sstats["missing_samples"] == 0 and
                 sstats["duplicates"] == 0 and len(pcm) == 8,
                 "stitch seq wrap 255->0")

    # stitch: gap fills zeros (drop detection), mod-256 aware
    pcm, last, sstats = stitch_pcm([(1, 10), (2, 13)])
    expect = struct.pack("<4h", 1, 0, 0, 2)
    ok &= _check(pcm == expect and last == 13 and
                 sstats["missing_samples"] == 2, "stitch gap zero fill")

    # stitch: gap across wrap
    pcm, last, sstats = stitch_pcm([(1, 255), (2, 1)])
    ok &= _check(pcm == struct.pack("<3h", 1, 0, 2) and last == 1 and
                 sstats["missing_samples"] == 1, "stitch gap across wrap")

    # stitch: duplicate of last seq skipped
    pcm, last, sstats = stitch_pcm([(5, 1), (5, 1), (6, 2)])
    ok &= _check(pcm == struct.pack("<2h", 5, 6) and last == 2 and
                 sstats["duplicates"] == 1 and
                 sstats["missing_samples"] == 0, "stitch duplicate skipped")

    # stitch resumes from previous session's last seq
    pcm, last, sstats = stitch_pcm([(9, 4)], last_sequence=3)
    ok &= _check(pcm == struct.pack("<h", 9) and last == 4 and
                 sstats["missing_samples"] == 0, "stitch with last_sequence")

    # wav write/read roundtrip in a temp file
    import os
    import tempfile
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        data = struct.pack("<3h", -32768, 0, 32767)
        write_wav(tmp, data)
        with wave.open(tmp, "rb") as r:
            ok &= _check(r.getnchannels() == 1 and r.getsampwidth() == 2 and
                         r.getframerate() == SAMPLE_RATE and
                         r.readframes(r.getnframes()) == data,
                         "wav file roundtrip")
    finally:
        os.remove(tmp)

    print("self-test: %s" % ("PASS" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--port", help="serial port, e.g. COM3")
    p.add_argument("--seconds", type=float, default=3.0)
    p.add_argument("--output", default="mic.wav")
    p.add_argument("--self-test", action="store_true",
                   help="run built-in tests (no pyserial or hardware needed)")
    args = p.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.port:
        p.error("--port is required unless --self-test is used")
    if not math.isfinite(args.seconds) or args.seconds <= 0:
        p.error("--seconds must be a finite number > 0")
    return capture(args.port, args.seconds, args.output)


if __name__ == "__main__":
    sys.exit(main())
