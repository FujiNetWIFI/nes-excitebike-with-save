#!/usr/bin/env python3
"""bps.py -- a minimal BPS patch writer and applier.

BPS (byuu's beat) can express the one thing this project needs that IPS cannot:
the original 16K PRG moving 16K further into the file when the ROM grows to
NROM-256. The patch therefore carries only the new bank and the handful of
changed bytes, never the game's own code.

    bps.py create <source> <target> <patch>
    bps.py apply  <source> <patch>  <output>
"""
import sys
import zlib

SOURCE_READ, TARGET_READ, SOURCE_COPY, TARGET_COPY = 0, 1, 2, 3


def _varint(n):
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return bytes(out)
        out.append(x)
        n -= 1


def _read_varint(data, pos):
    result, shift = 0, 1
    while True:
        x = data[pos]
        pos += 1
        result += (x & 0x7F) * shift
        if x & 0x80:
            return result, pos
        shift <<= 7
        result += shift


def _action(cmd, length):
    return _varint(((length - 1) << 2) | cmd)


def create(source, target, source_of):
    """Build a patch. source_of(t) gives the source offset that target offset t
    mirrors, or None where the target is new data."""
    out = bytearray(b"BPS1")
    out += _varint(len(source)) + _varint(len(target)) + _varint(0)
    src_rel = 0
    t = 0
    while t < len(target):
        s = source_of(t)
        same = s is not None and target[t] == source[s]
        n = 1
        while t + n < len(target):
            s2 = source_of(t + n)
            same2 = s2 is not None and target[t + n] == source[s2]
            if same2 != same or (same and s2 != s + n):
                break
            n += 1
        if same:
            out += _action(SOURCE_COPY, n)
            d = s - src_rel
            out += _varint((abs(d) << 1) | (1 if d < 0 else 0))
            src_rel = s + n
        else:
            out += _action(TARGET_READ, n)
            out += target[t:t + n]
        t += n
    out += zlib.crc32(source).to_bytes(4, "little")
    out += zlib.crc32(target).to_bytes(4, "little")
    out += zlib.crc32(bytes(out)).to_bytes(4, "little")
    return bytes(out)


def apply(source, patch):
    if patch[:4] != b"BPS1":
        raise ValueError("not a BPS patch")
    if zlib.crc32(patch[:-4]) != int.from_bytes(patch[-4:], "little"):
        raise ValueError("patch checksum mismatch")
    if zlib.crc32(source) != int.from_bytes(patch[-12:-8], "little"):
        raise ValueError("source checksum mismatch: wrong input file")
    pos = 4
    src_size, pos = _read_varint(patch, pos)
    tgt_size, pos = _read_varint(patch, pos)
    meta_size, pos = _read_varint(patch, pos)
    pos += meta_size
    if len(source) != src_size:
        raise ValueError("source size mismatch")
    target = bytearray(tgt_size)
    out = src_rel = tgt_rel = 0
    end = len(patch) - 12
    while pos < end:
        data, pos = _read_varint(patch, pos)
        cmd, length = data & 3, (data >> 2) + 1
        if cmd == SOURCE_READ:
            target[out:out + length] = source[out:out + length]
            out += length
        elif cmd == TARGET_READ:
            target[out:out + length] = patch[pos:pos + length]
            pos += length
            out += length
        elif cmd == SOURCE_COPY:
            d, pos = _read_varint(patch, pos)
            src_rel += -(d >> 1) if d & 1 else (d >> 1)
            target[out:out + length] = source[src_rel:src_rel + length]
            src_rel += length
            out += length
        else:
            d, pos = _read_varint(patch, pos)
            tgt_rel += -(d >> 1) if d & 1 else (d >> 1)
            for _ in range(length):          # may overlap itself
                target[out] = target[tgt_rel]
                out += 1
                tgt_rel += 1
    if zlib.crc32(target) != int.from_bytes(patch[-8:-4], "little"):
        raise ValueError("target checksum mismatch")
    return bytes(target)


def main(argv):
    if len(argv) == 5 and argv[1] == "create":
        source = open(argv[2], "rb").read()
        target = open(argv[3], "rb").read()
        shift = len(target) - len(source)

        def source_of(t):           # the tail of the target mirrors the source
            s = t - shift
            return s if 16 <= s < len(source) else None
        open(argv[4], "wb").write(create(source, target, source_of))
    elif len(argv) == 5 and argv[1] == "apply":
        source = open(argv[2], "rb").read()
        patch = open(argv[3], "rb").read()
        open(argv[4], "wb").write(apply(source, patch))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
