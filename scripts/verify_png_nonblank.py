#!/usr/bin/env python3
import struct
import sys
import zlib


def paeth(a, b, c):
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def bytes_per_pixel(color_type):
    channels_by_type = {
        0: 1,  # greyscale
        2: 3,  # truecolor
        4: 2,  # greyscale + alpha
        6: 4,  # truecolor + alpha
    }
    return channels_by_type[color_type]


def parse_png(path):
    with open(path, "rb") as f:
        data = f.read()

    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("not a PNG file")

    pos = 8
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()

    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        chunk_type = data[pos + 4 : pos + 8]
        chunk_data = data[pos + 8 : pos + 8 + length]
        pos += 12 + length

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _compression, _filter, interlace = (
                struct.unpack(">IIBBBBB", chunk_data)
            )
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    if width is None:
        raise ValueError("missing IHDR")
    if bit_depth != 8:
        raise ValueError(f"unsupported bit depth: {bit_depth}")
    if color_type not in (0, 2, 4, 6):
        raise ValueError(f"unsupported color type: {color_type}")
    if interlace != 0:
        raise ValueError("interlaced PNGs are unsupported")

    bpp = bytes_per_pixel(color_type)
    stride = width * bpp
    raw = zlib.decompress(bytes(compressed))
    expected = height * (stride + 1)
    if len(raw) != expected:
        raise ValueError(f"unexpected decompressed size: {len(raw)} != {expected}")

    rows = []
    prev = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset : offset + stride])
        offset += stride

        for i in range(stride):
            left = row[i - bpp] if i >= bpp else 0
            up = prev[i]
            up_left = prev[i - bpp] if i >= bpp else 0
            if filter_type == 0:
                pass
            elif filter_type == 1:
                row[i] = (row[i] + left) & 0xFF
            elif filter_type == 2:
                row[i] = (row[i] + up) & 0xFF
            elif filter_type == 3:
                row[i] = (row[i] + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                row[i] = (row[i] + paeth(left, up, up_left)) & 0xFF
            else:
                raise ValueError(f"unsupported filter type: {filter_type}")

        rows.append(bytes(row))
        prev = row

    first_pixel = rows[0][:bpp]
    distinct = {first_pixel}
    for row in rows:
        for i in range(0, len(row), bpp):
            distinct.add(row[i : i + bpp])
            if len(distinct) > 1:
                return width, height, len(distinct)

    return width, height, len(distinct)


def main(argv):
    if len(argv) < 2:
        print("usage: verify_png_nonblank.py PNG ...", file=sys.stderr)
        return 2

    for path in argv[1:]:
        width, height, distinct = parse_png(path)
        if width <= 0 or height <= 0:
            print(f"verify-png-nonblank: invalid dimensions: {path}", file=sys.stderr)
            return 1
        if distinct < 2:
            print(f"verify-png-nonblank: single-color PNG: {path}", file=sys.stderr)
            return 1
        print(f"verify-png-nonblank: ok {path} width={width} height={height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
