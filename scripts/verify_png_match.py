#!/usr/bin/env python3
import argparse
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
        0: 1,
        2: 3,
        4: 2,
        6: 4,
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

    pixels = bytearray()
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

        pixels.extend(row)
        prev = row

    return width, height, color_type, bpp, bytes(pixels)


def compare_pngs(actual_path, expected_path):
    actual = parse_png(actual_path)
    expected = parse_png(expected_path)
    if actual[:4] != expected[:4]:
        raise ValueError(
            "PNG metadata differs: "
            f"{actual_path}={actual[:4]} {expected_path}={expected[:4]}"
        )

    width, height, _color_type, bpp, actual_pixels = actual
    expected_pixels = expected[4]
    total_delta = 0
    max_delta = 0
    differing_pixels = 0

    for i in range(0, len(actual_pixels), bpp):
        pixel_differs = False
        for channel in range(bpp):
            delta = abs(actual_pixels[i + channel] - expected_pixels[i + channel])
            total_delta += delta
            if delta > max_delta:
                max_delta = delta
            if delta != 0:
                pixel_differs = True
        if pixel_differs:
            differing_pixels += 1

    pixel_count = width * height
    mean_abs_delta = total_delta / len(actual_pixels)
    differing_ratio = differing_pixels / pixel_count
    return {
        "width": width,
        "height": height,
        "channels": bpp,
        "pixels": pixel_count,
        "differing_pixels": differing_pixels,
        "differing_ratio": differing_ratio,
        "max_channel_delta": max_delta,
        "mean_abs_channel_delta": mean_abs_delta,
    }


def main(argv):
    parser = argparse.ArgumentParser(
        description="Compare two non-interlaced 8-bit PNG images with tolerances."
    )
    parser.add_argument("--max-mean-delta", type=float, default=0.0)
    parser.add_argument("--max-channel-delta", type=int, default=0)
    parser.add_argument("--max-differing-ratio", type=float, default=0.0)
    parser.add_argument("actual")
    parser.add_argument("expected")
    args = parser.parse_args(argv[1:])

    stats = compare_pngs(args.actual, args.expected)
    failed = (
        stats["mean_abs_channel_delta"] > args.max_mean_delta
        or stats["max_channel_delta"] > args.max_channel_delta
        or stats["differing_ratio"] > args.max_differing_ratio
    )

    message = (
        "verify-png-match: "
        f"width={stats['width']} height={stats['height']} "
        f"channels={stats['channels']} pixels={stats['pixels']} "
        f"differing_pixels={stats['differing_pixels']} "
        f"differing_ratio={stats['differing_ratio']:.8f} "
        f"max_channel_delta={stats['max_channel_delta']} "
        f"mean_abs_channel_delta={stats['mean_abs_channel_delta']:.8f}"
    )

    if failed:
        print(message, file=sys.stderr)
        return 1

    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
