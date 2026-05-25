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


def compare_pixels(width, height, bpp, actual_pixels, expected_pixels):
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
        "shift_x": 0,
        "shift_y": 0,
    }


def crop_for_shift(width, height, bpp, pixels, dx, dy):
    x0 = max(0, dx)
    y0 = max(0, dy)
    x1 = min(width, width + dx)
    y1 = min(height, height + dy)
    cropped = bytearray()
    for y in range(y0, y1):
        start = (y * width + x0) * bpp
        end = (y * width + x1) * bpp
        cropped.extend(pixels[start:end])
    return x1 - x0, y1 - y0, bytes(cropped)


def shifted_expected_crop(width, height, bpp, pixels, dx, dy):
    x0 = max(0, -dx)
    y0 = max(0, -dy)
    x1 = min(width, width - dx)
    y1 = min(height, height - dy)
    cropped = bytearray()
    for y in range(y0, y1):
        start = (y * width + x0) * bpp
        end = (y * width + x1) * bpp
        cropped.extend(pixels[start:end])
    return bytes(cropped)


def crop_to_size(width, height, bpp, pixels, crop_width, crop_height):
    cropped = bytearray()
    row_bytes = crop_width * bpp
    stride = width * bpp
    for y in range(crop_height):
        start = y * stride
        cropped.extend(pixels[start : start + row_bytes])
    return bytes(cropped)


def sampled_shift_score(width, height, bpp, actual_pixels, expected_pixels, dx, dy):
    x0_actual = max(0, dx)
    y0_actual = max(0, dy)
    x0_expected = max(0, -dx)
    y0_expected = max(0, -dy)
    overlap_width = min(width, width + dx) - x0_actual
    overlap_height = min(height, height + dy) - y0_actual
    if overlap_width <= 0 or overlap_height <= 0:
        return None

    step = max(1, min(overlap_width, overlap_height) // 96)
    total_delta = 0
    samples = 0
    for y in range(0, overlap_height, step):
        actual_row = ((y0_actual + y) * width + x0_actual) * bpp
        expected_row = ((y0_expected + y) * width + x0_expected) * bpp
        for x in range(0, overlap_width, step):
            actual_i = actual_row + x * bpp
            expected_i = expected_row + x * bpp
            for channel in range(bpp):
                total_delta += abs(
                    actual_pixels[actual_i + channel]
                    - expected_pixels[expected_i + channel]
                )
            samples += bpp
    return total_delta / samples


def compare_pngs(actual_path, expected_path, max_shift, max_dimension_delta):
    actual = parse_png(actual_path)
    expected = parse_png(expected_path)
    if actual[2:4] != expected[2:4]:
        raise ValueError(
            "PNG metadata differs: "
            f"{actual_path}={actual[:4]} {expected_path}={expected[:4]}"
        )

    width, height, _color_type, bpp, actual_pixels = actual
    expected_width, expected_height, _expected_color_type, _expected_bpp = expected[:4]
    expected_pixels = expected[4]
    dimension_delta = max(abs(width - expected_width), abs(height - expected_height))
    if dimension_delta > max_dimension_delta:
        raise ValueError(
            "PNG dimensions differ beyond tolerance: "
            f"{actual_path}={actual[:4]} {expected_path}={expected[:4]} "
            f"max_dimension_delta={max_dimension_delta}"
        )
    if dimension_delta != 0:
        compare_width = min(width, expected_width)
        compare_height = min(height, expected_height)
        actual_pixels = crop_to_size(
            width, height, bpp, actual_pixels, compare_width, compare_height
        )
        expected_pixels = crop_to_size(
            expected_width,
            expected_height,
            bpp,
            expected_pixels,
            compare_width,
            compare_height,
        )
        width = compare_width
        height = compare_height

    best = compare_pixels(width, height, bpp, actual_pixels, expected_pixels)
    best["actual_width"] = actual[0]
    best["actual_height"] = actual[1]
    best["expected_width"] = expected[0]
    best["expected_height"] = expected[1]
    best["dimension_delta"] = dimension_delta

    best_shift = (0, 0)
    best_score = sampled_shift_score(
        width, height, bpp, actual_pixels, expected_pixels, 0, 0
    )
    for dy in range(-max_shift, max_shift + 1):
        for dx in range(-max_shift, max_shift + 1):
            if dx == 0 and dy == 0:
                continue
            score = sampled_shift_score(
                width, height, bpp, actual_pixels, expected_pixels, dx, dy
            )
            if score is not None and (best_score is None or score < best_score):
                best_score = score
                best_shift = (dx, dy)

    dx, dy = best_shift
    if dx != 0 or dy != 0:
        crop_width, crop_height, actual_crop = crop_for_shift(
            width, height, bpp, actual_pixels, dx, dy
        )
        expected_crop = shifted_expected_crop(
            width, height, bpp, expected_pixels, dx, dy
        )
        best = compare_pixels(
            crop_width, crop_height, bpp, actual_crop, expected_crop
        )
        best["shift_x"] = dx
        best["shift_y"] = dy
        best["actual_width"] = actual[0]
        best["actual_height"] = actual[1]
        best["expected_width"] = expected[0]
        best["expected_height"] = expected[1]
        best["dimension_delta"] = dimension_delta

    return best


def main(argv):
    parser = argparse.ArgumentParser(
        description="Compare two non-interlaced 8-bit PNG images with tolerances."
    )
    parser.add_argument("--max-mean-delta", type=float, default=0.0)
    parser.add_argument("--max-channel-delta", type=int, default=0)
    parser.add_argument("--max-differing-ratio", type=float, default=0.0)
    parser.add_argument(
        "--max-shift",
        type=int,
        default=0,
        help="try bounded x/y pixel translations and compare the best overlap",
    )
    parser.add_argument(
        "--max-dimension-delta",
        type=int,
        default=0,
        help="allow small width/height differences and compare the shared top-left extent",
    )
    parser.add_argument("actual")
    parser.add_argument("expected")
    args = parser.parse_args(argv[1:])

    stats = compare_pngs(
        args.actual, args.expected, args.max_shift, args.max_dimension_delta
    )
    failed = (
        stats["mean_abs_channel_delta"] > args.max_mean_delta
        or stats["max_channel_delta"] > args.max_channel_delta
        or stats["differing_ratio"] > args.max_differing_ratio
    )

    message = (
        "verify-png-match: "
        f"width={stats['width']} height={stats['height']} "
        f"actual_width={stats['actual_width']} actual_height={stats['actual_height']} "
        f"expected_width={stats['expected_width']} expected_height={stats['expected_height']} "
        f"dimension_delta={stats['dimension_delta']} "
        f"channels={stats['channels']} pixels={stats['pixels']} "
        f"differing_pixels={stats['differing_pixels']} "
        f"differing_ratio={stats['differing_ratio']:.8f} "
        f"max_channel_delta={stats['max_channel_delta']} "
        f"mean_abs_channel_delta={stats['mean_abs_channel_delta']:.8f} "
        f"shift_x={stats['shift_x']} shift_y={stats['shift_y']}"
    )

    if failed:
        print(message, file=sys.stderr)
        return 1

    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
