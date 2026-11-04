"""Structural validator for the controlled "ultraembedded fixed-DHT baseline 4:2:0" JPEG profile.

Pure Python + Pillow. ``inspect_jpeg`` performs structural checks only: it never
entropy-decodes the scan. It verifies that a JPEG is a baseline (SOF0) 4:2:0 image
with the exact standard Huffman tables, 8-bit DQT ids 0/1, a single progressive-free
SOS, correctly FF00-stuffed entropy, and a trailing EOI.
"""

from __future__ import annotations

import io
from functools import lru_cache

from PIL import Image

# --------------------------------------------------------------------------- #
# Markers (the byte that follows 0xFF)
# --------------------------------------------------------------------------- #
SOI = 0xD8
EOI = 0xD9
SOF0 = 0xC0  # baseline, sequential DCT
SOF1 = 0xC1  # extended sequential
SOF2 = 0xC2  # progressive
SOF3 = 0xC3  # lossless / arithmetic
DHT = 0xC4
SOS = 0xDA
DQT = 0xDB
DRI = 0xDD
COM = 0xFE
_APP_LO = 0xE0
_APP_HI = 0xEF
_RST_LO = 0xD0
_RST_HI = 0xD7

# --------------------------------------------------------------------------- #
# Expected profile constants
# --------------------------------------------------------------------------- #
EXPECTED_PRECISION = 8
# (component id, horizontal factor, vertical factor, quant table id)
EXPECTED_COMPONENTS = (
    (1, 2, 2, 0),  # luma   Y   sampled 2x2
    (2, 1, 1, 1),  # chroma Cb  sampled 1x1
    (3, 1, 1, 1),  # chroma Cr  sampled 1x1
)
EXPECTED_DQT_IDS = (0, 1)
# SOS component selector -> (DC table, AC table) nibble-packed
EXPECTED_SOS_NS = 3
EXPECTED_SOS_IDS = (1, 2, 3)
EXPECTED_SOS_TABLES = (0x00, 0x11, 0x11)  # Y:0/0, Cb:1/1, Cr:1/1
EXPECTED_SOS_SS = 0
EXPECTED_SOS_SE = 63
EXPECTED_SOS_AHAL = 0
EXPECTED_SUBSAMPLING = "4:2:0"


class ProfileError(ValueError):
    """Raised when a JPEG does not match the controlled baseline 4:2:0 profile."""


# --------------------------------------------------------------------------- #
# Low-level helpers
# --------------------------------------------------------------------------- #
def _u16(data: bytes, i: int) -> int:
    if i + 2 > len(data):
        raise ProfileError("truncated 16-bit field at offset %d" % i)
    return (data[i] << 8) | data[i + 1]


def _split_headers(data: bytes):
    """Split the marker header run up to (and including) the first SOS.

    Returns ``(segments, entropy_start)`` where ``segments`` is a list of
    ``(marker, payload)`` tuples (payload is ``None`` for standalone markers)
    and ``entropy_start`` is the byte offset of the entropy-coded scan data.
    Only structural splitting is done here; profile validation lives elsewhere.
    """
    n = len(data)
    i = 0
    # Allow leading 0xFF fill bytes before SOI.
    while i < n and data[i] == 0xFF:
        i += 1
    if i == 0 or i >= n or data[i] != SOI:
        raise ProfileError("missing SOI marker")
    i += 1  # past 0xD8; next byte must begin the following marker (0xFF)

    segments = []
    saw_sos = False
    while i < n:
        if data[i] != 0xFF:
            if saw_sos:
                break  # we are inside the entropy stream
            raise ProfileError("expected marker at offset %d" % i)
        # Skip 0xFF fill bytes that precede a marker.
        while i < n and data[i] == 0xFF:
            i += 1
        if i >= n:
            raise ProfileError("truncated: dangling marker prefix")
        marker = data[i]
        i += 1

        if marker == SOI:
            segments.append((marker, None))
            continue
        if marker == EOI:
            segments.append((marker, None))
            break
        if _RST_LO <= marker <= _RST_HI:
            segments.append((marker, None))
            continue

        len_pos = i  # i points at the high byte of the segment length field
        seglen = _u16(data, len_pos)
        if seglen < 2:
            raise ProfileError("bad segment length %d for marker 0x%02X" % (seglen, marker))
        payload_start = len_pos + 2
        payload_end = len_pos + seglen
        if payload_end > n:
            raise ProfileError("truncated segment 0x%02X (needs %d bytes)" % (marker, payload_end - n))
        payload = data[payload_start:payload_end]
        segments.append((marker, payload))
        i = payload_end

        if marker == SOS:
            saw_sos = True
            break

    if not saw_sos:
        raise ProfileError("no SOS found before end of markers")
    return segments, i


def _parse_dht(payload: bytes) -> dict:
    """Decode one DHT segment into ``{(class, id): counts+symbols bytes}``."""
    tables = {}
    p = 0
    end = len(payload)
    while p < end:
        tc = payload[p]
        klass = tc >> 4
        tid = tc & 0x0F
        if p + 17 > end:
            raise ProfileError("truncated DHT counts")
        counts = payload[p + 1:p + 17]
        total = sum(counts)
        if p + 17 + total > end:
            raise ProfileError("truncated DHT symbols")
        symbols = payload[p + 17:p + 17 + total]
        tables[(klass, tid)] = bytes(counts) + bytes(symbols)
        p += 17 + total
    return tables


def _parse_dqt(payload: bytes) -> dict:
    """Decode one DQT segment into ``{id: precision}`` (0=8-bit, 1=16-bit)."""
    tables = {}
    p = 0
    end = len(payload)
    while p < end:
        q = payload[p]
        prec = q >> 4
        tid = q & 0x0F
        size = 128 if prec else 64
        if p + 1 + size > end:
            raise ProfileError("truncated DQT table %d" % tid)
        tables[tid] = prec
        p += 1 + size
    return tables


# --------------------------------------------------------------------------- #
# Reference (ground-truth) Huffman tables, extracted once from Pillow
# --------------------------------------------------------------------------- #
@lru_cache(maxsize=1)
def _reference_dht() -> dict:
    """Standard four Huffman tables from a Pillow-generated baseline 4:2:0 JPEG."""
    img = Image.new("RGB", (16, 16), (120, 80, 200))
    buf = io.BytesIO()
    img.save(
        buf,
        format="JPEG",
        optimize=False,
        subsampling=2,        # 4:2:0
        progressive=False,
    )
    segments, _ = _split_headers(buf.getvalue())
    tables = {}
    for marker, payload in segments:
        if marker == DHT:
            tables.update(_parse_dht(payload))
    expected_keys = {(0, 0), (1, 0), (0, 1), (1, 1)}
    if set(tables) != expected_keys:
        raise RuntimeError(
            "reference DHT extraction produced %s, expected the four standard tables"
            % sorted(tables)
        )
    return tables


# --------------------------------------------------------------------------- #
# Entropy-stream structural scan (byte stuffing only, no decoding)
# --------------------------------------------------------------------------- #
def _validate_entropy(data: bytes, start: int) -> None:
    n = len(data)
    i = start
    if i >= n:
        raise ProfileError("empty entropy-coded data")
    seen_any = False
    while i < n:
        if data[i] != 0xFF:
            seen_any = True
            i += 1
            continue
        # data[i] == 0xFF
        if i + 1 >= n:
            raise ProfileError("truncated: 0xFF with no following byte / EOI missing")
        marker = data[i + 1]
        if marker == 0x00:
            seen_any = True
            i += 2  # FF00 stuffed byte
            continue
        if marker == EOI:
            if not seen_any:
                raise ProfileError("empty entropy-coded data")
            if any(data[i + 2:]):
                raise ProfileError("nonzero trailing data after EOI")
            return
        if _RST_LO <= marker <= _RST_HI:
            raise ProfileError("restart markers (RSTn) are not allowed")
        if marker == 0xFF:
            raise ProfileError("invalid 0xFF fill inside entropy stream at offset %d" % i)
        if marker >= 0xC0:
            raise ProfileError("unexpected marker 0x%02X inside entropy stream at offset %d" % (marker, i))
        raise ProfileError("invalid 0xFF%02X sequence inside entropy stream at offset %d" % (marker, i))
    raise ProfileError("EOI missing")


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #
def inspect_jpeg(data: bytes, width: int = 640, height: int = 480) -> dict:
    """Validate that ``data`` is a controlled baseline 4:2:0 JPEG.

    Raises :class:`ProfileError` on any structural deviation. On success returns
    a dict with ``size_bytes``, ``width``, ``height``, ``components`` and
    ``subsampling``.
    """
    if not isinstance(data, (bytes, bytearray, memoryview)):
        raise ProfileError("data must be bytes-like")
    data = bytes(data)
    if not data:
        raise ProfileError("empty input")

    segments, entropy_start = _split_headers(data)

    ref_dht = _reference_dht()

    sof_payload = None
    dqt_ids = {}
    cand_dht = {}
    sos_payload = None

    for marker, payload in segments:
        if marker == SOI:
            continue
        if _APP_LO <= marker <= _APP_HI:
            continue  # ignore APPn
        if marker == COM:
            continue  # ignore comment
        if marker == DRI:
            raise ProfileError("DRI restart interval not allowed")
        if marker == SOF2:
            raise ProfileError("progressive JPEG not allowed")
        if marker == SOF3:
            raise ProfileError("arithmetic / lossless JPEG not allowed")
        if marker == SOF1:
            raise ProfileError("extended sequential (SOF1) not allowed")
        if marker == SOF0:
            if sof_payload is not None:
                raise ProfileError("duplicate SOF0")
            sof_payload = payload
        elif marker == DQT:
            dqt_ids.update(_parse_dqt(payload))
        elif marker == DHT:
            cand_dht.update(_parse_dht(payload))
        elif marker == SOS:
            if sos_payload is not None:
                raise ProfileError("multiple scans not allowed")
            sos_payload = payload
        else:
            raise ProfileError("unexpected marker 0x%02X" % marker)

    # ---- SOF0 -------------------------------------------------------------
    if sof_payload is None:
        raise ProfileError("missing SOF0")
    if len(sof_payload) < 8:
        raise ProfileError("truncated SOF0")
    precision = sof_payload[0]
    if precision != EXPECTED_PRECISION:
        raise ProfileError("SOF0 precision must be 8, got %d" % precision)
    img_h = (sof_payload[1] << 8) | sof_payload[2]
    img_w = (sof_payload[3] << 8) | sof_payload[4]
    ncomp = sof_payload[5]
    if (img_w, img_h) != (width, height):
        raise ProfileError(
            "dimensions mismatch: got %dx%d expected %dx%d" % (img_w, img_h, width, height)
        )
    if ncomp != EXPECTED_SOS_NS:
        raise ProfileError("expected 3 components for baseline 4:2:0, got %d" % ncomp)
    if len(sof_payload) != 6 + ncomp * 3:
        raise ProfileError("incorrect SOF0 component length")
    for idx in range(ncomp):
        cid = sof_payload[6 + idx * 3]
        samp = sof_payload[7 + idx * 3]
        tq = sof_payload[8 + idx * 3]
        hf = samp >> 4
        vf = samp & 0x0F
        exp_cid, exp_hf, exp_vf, exp_tq = EXPECTED_COMPONENTS[idx]
        if (cid, hf, vf, tq) != (exp_cid, exp_hf, exp_vf, exp_tq):
            raise ProfileError(
                "component %d is %d:%d tq=%d (id %d), not the required %d:%d tq=%d (id %d)"
                % (idx + 1, hf, vf, tq, cid, exp_hf, exp_vf, exp_tq, exp_cid)
            )

    # ---- DQT --------------------------------------------------------------
    if set(dqt_ids) != set(EXPECTED_DQT_IDS):
        raise ProfileError("expected DQT ids {0,1}, got %s" % sorted(dqt_ids))
    for tid, prec in dqt_ids.items():
        if prec != 0:
            raise ProfileError("DQT table %d must be 8-bit, got precision flag %d" % (tid, prec))

    # ---- DHT (must equal the standard reference tables) -------------------
    if set(cand_dht) != set(ref_dht):
        raise ProfileError(
            "DHT table set %s does not match the standard {DC0,AC0,DC1,AC1} tables (custom DHT)"
            % sorted(cand_dht)
        )
    for key, expected_bytes in ref_dht.items():
        if cand_dht[key] != expected_bytes:
            klass, tid = key
            raise ProfileError("custom Huffman table class=%d id=%d" % (klass, tid))

    # ---- SOS --------------------------------------------------------------
    if sos_payload is None:
        raise ProfileError("missing SOS")
    if not sos_payload:
        raise ProfileError("empty SOS")
    ns = sos_payload[0]
    if ns != EXPECTED_SOS_NS:
        raise ProfileError("SOS selector count must be 3, got %d" % ns)
    if len(sos_payload) != 1 + ns * 2 + 3:
        raise ProfileError("incorrect SOS length")
    for c in range(ns):
        cid = sos_payload[1 + c * 2]
        tdta = sos_payload[2 + c * 2]
        if cid != EXPECTED_SOS_IDS[c]:
            raise ProfileError("SOS component %d id %d != %d" % (c + 1, cid, EXPECTED_SOS_IDS[c]))
        if tdta != EXPECTED_SOS_TABLES[c]:
            raise ProfileError(
                "SOS component %d tables 0x%02X != 0x%02X" % (c + 1, tdta, EXPECTED_SOS_TABLES[c])
            )
    ss = sos_payload[1 + ns * 2]
    se = sos_payload[2 + ns * 2]
    ahal = sos_payload[3 + ns * 2]
    if (ss, se, ahal) != (EXPECTED_SOS_SS, EXPECTED_SOS_SE, EXPECTED_SOS_AHAL):
        raise ProfileError(
            "SOS spectral %d..%d ahal=0x%02X, expected baseline 0..63 ahal=0" % (ss, se, ahal)
        )

    # ---- Entropy-coded segment -------------------------------------------
    _validate_entropy(data, entropy_start)

    return {
        "size_bytes": len(data),
        "width": img_w,
        "height": img_h,
        "components": ncomp,
        "subsampling": EXPECTED_SUBSAMPLING,
    }


if __name__ == "__main__":  # pragma: no cover - manual smoke test
    import sys

    def _make(**kw):
        img = Image.new("RGB", (640, 480), (16, 128, 240))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", **kw)
        return buf.getvalue()

    ok = _make(optimize=False, subsampling=2, progressive=False)
    print("valid  :", inspect_jpeg(ok))
    open("jpeg_profile_sample.jpg", "wb").write(ok)  # relative to cwd

    failures = {
        "optimize (custom DHT)": _make(optimize=True, subsampling=2, progressive=False),
        "4:2:2": _make(optimize=False, subsampling=1, progressive=False),
        "progressive": _make(optimize=False, subsampling=2, progressive=True),
    }
    for label, blob in failures.items():
        try:
            inspect_jpeg(blob)
        except ProfileError as exc:
            print("reject %-22s -> %s" % (label, exc))
        else:
            print("!!! UNEXPECTED PASS: %s" % label)
            sys.exit(1)
