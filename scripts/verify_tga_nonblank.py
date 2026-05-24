#!/usr/bin/env python3
import argparse
import sys


def decode_tga(path):
    with open(path, "rb") as f:
        data = f.read()

    if len(data) < 18:
        raise ValueError("file too small for TGA header")

    id_length = data[0]
    color_map_type = data[1]
    image_type = data[2]
    width = int.from_bytes(data[12:14], "little")
    height = int.from_bytes(data[14:16], "little")
    pixel_depth = data[16]

    if color_map_type != 0:
        raise ValueError("color-mapped TGA files are unsupported")
    if image_type not in (2, 3, 10, 11):
        raise ValueError(f"unsupported TGA image type: {image_type}")
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid dimensions: {width}x{height}")
    if pixel_depth not in (8, 24, 32):
        raise ValueError(f"unsupported TGA pixel depth: {pixel_depth}")

    channels = pixel_depth // 8
    offset = 18 + id_length
    pixel_count = width * height

    if image_type in (2, 3):
        expected = pixel_count * channels
        pixels = data[offset : offset + expected]
        if len(pixels) != expected:
            raise ValueError("truncated TGA pixel data")
        return width, height, channels, pixels

    pixels = bytearray()
    pos = offset
    while len(pixels) < pixel_count * channels:
        if pos >= len(data):
            raise ValueError("truncated TGA RLE packet")
        packet = data[pos]
        pos += 1
        count = (packet & 0x7F) + 1
        if packet & 0x80:
            pixel = data[pos : pos + channels]
            pos += channels
            if len(pixel) != channels:
                raise ValueError("truncated TGA RLE pixel")
            pixels.extend(pixel * count)
        else:
            byte_count = count * channels
            chunk = data[pos : pos + byte_count]
            pos += byte_count
            if len(chunk) != byte_count:
                raise ValueError("truncated TGA raw packet")
            pixels.extend(chunk)

    pixels = bytes(pixels[: pixel_count * channels])
    return width, height, channels, pixels


def stats(path):
    width, height, channels, pixels = decode_tga(path)
    distinct = set()
    nonzero = 0
    for i in range(0, len(pixels), channels):
        pixel = pixels[i : i + channels]
        distinct.add(pixel)
        color = pixel[:3] if channels >= 3 else pixel[:1]
        if any(component != 0 for component in color):
            nonzero += 1
    return width, height, len(distinct), nonzero


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-nonzero", type=int, default=1)
    parser.add_argument("tga", nargs="+")
    args = parser.parse_args(argv[1:])

    for path in args.tga:
        width, height, distinct, nonzero = stats(path)
        if distinct < 2:
            print(f"verify-tga-nonblank: single-color TGA: {path}", file=sys.stderr)
            return 1
        if nonzero < args.min_nonzero:
            print(
                f"verify-tga-nonblank: insufficient nonzero pixels: {path} "
                f"nonzero={nonzero} min={args.min_nonzero}",
                file=sys.stderr,
            )
            return 1
        print(
            f"width={width} height={height} distinct={distinct} nonzero={nonzero}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
