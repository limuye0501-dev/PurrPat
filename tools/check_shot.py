#!/usr/bin/env python3
"""Reject a simulator screenshot that is not the requested Purr Pat frame.

Springboard on this runner is a black home screen, and an early app frame is a
flat navy view. Neither is caught by a single cyan-wallpaper test.
"""

import struct
import sys
import zlib
from pathlib import Path


def read_png(path: Path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    width = height = None
    color = None
    chunks = []
    index = 8
    while index < len(data):
        length = struct.unpack(">I", data[index : index + 4])[0]
        kind = data[index + 4 : index + 8]
        chunk = data[index + 8 : index + 8 + length]
        index += 12 + length
        if kind == b"IHDR":
            width, height, bit, color, *_ = struct.unpack(">IIBBBBB", chunk)
            if bit != 8 or color not in (2, 6):
                raise SystemExit(f"{path} is not 8-bit RGB")
        elif kind == b"IDAT":
            chunks.append(chunk)
        elif kind == b"IEND":
            break
    raw = zlib.decompress(b"".join(chunks))
    channels = 3 if color == 2 else 4
    stride = width * channels
    rows = []
    source = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[source]
        source += 1
        row = bytearray(raw[source : source + stride])
        source += stride
        if filter_type == 1:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                row[i] = (row[i] + left) & 255
        elif filter_type == 2:
            for i in range(stride):
                row[i] = (row[i] + previous[i]) & 255
        elif filter_type == 3:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                row[i] = (row[i] + ((left + previous[i]) // 2)) & 255
        elif filter_type == 4:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                up = previous[i]
                up_left = previous[i - channels] if i >= channels else 0
                row[i] = (row[i] + paeth(left, up, up_left)) & 255
        elif filter_type != 0:
            raise SystemExit(f"{path} uses PNG filter {filter_type}")
        previous = row
        rows.append(bytes(row))
    return width, height, channels, rows


def paeth(left: int, up: int, up_left: int) -> int:
    estimate = left + up - up_left
    distance_left = abs(estimate - left)
    distance_up = abs(estimate - up)
    distance_up_left = abs(estimate - up_left)
    if distance_left <= distance_up and distance_left <= distance_up_left:
        return left
    if distance_up <= distance_up_left:
        return up
    return up_left


def pixel(rows, channels, x: int, y: int):
    sample = rows[y][x * channels : x * channels + 3]
    return sample[0], sample[1], sample[2]


def luminance(rgb) -> float:
    red, green, blue = rgb
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def region_stats(rows, channels, width, height, box):
    x0, y0, x1, y1 = box
    count = 0
    total = 0.0
    squares = 0.0
    dark = 0
    values = []
    for y in range(y0, y1, 3):
        for x in range(x0, x1, 3):
            value = luminance(pixel(rows, channels, x, y))
            values.append(value)
            total += value
            squares += value * value
            count += 1
            if value < 45:
                dark += 1
    mean = total / max(count, 1)
    variance = max(0.0, squares / max(count, 1) - mean * mean)
    values.sort()
    tenth = values[len(values) // 10] if values else 0
    return mean, variance ** 0.5, tenth, dark


def count_where(rows, channels, width, height, box, predicate) -> int:
    found, _ = cover(rows, channels, box, predicate)
    return found


def cover(rows, channels, box, predicate) -> tuple[int, int]:
    x0, y0, x1, y1 = box
    found = 0
    seen = 0
    for y in range(y0, y1, 2):
        for x in range(x0, x1, 2):
            seen += 1
            if predicate(pixel(rows, channels, x, y)):
                found += 1
    return found, max(seen, 1)


def beige(rgb) -> bool:
    red, green, blue = rgb
    return red > 145 and green > 125 and blue > 95 and red + 8 > green > blue - 5 and red - blue < 90


def sleeve(rgb) -> bool:
    red, green, blue = rgb
    return abs(red - green) < 16 and abs(green - blue) < 16 and 125 < red < 205


def orange(rgb) -> bool:
    red, green, blue = rgb
    return red > 150 and 50 < green < 170 and blue < 110 and red > green + 25


def paper(rgb) -> bool:
    red, green, blue = rgb
    return red > 235 and green > 220 and blue > 200


def brown(rgb) -> bool:
    red, green, blue = rgb
    return 70 < red < 150 and 35 < green < 100 and 15 < blue < 80 and red > green + 15


def check(path: Path, kind: str) -> None:
    width, height, channels, rows = read_png(path)
    full = (0, 0, width, height)
    margin = (int(width * 0.05), int(height * 0.38), int(width * 0.16), int(height * 0.55))
    torso = (int(width * 0.34), int(height * 0.28), int(width * 0.66), int(height * 0.46))
    lower = (int(width * 0.15), int(height * 0.42), int(width * 0.85), int(height * 0.92))
    bottom = (int(width * 0.1), int(height * 0.72), int(width * 0.9), height - 4)
    mean, spread, tenth, _ = region_stats(rows, channels, width, height, full)
    torso_mean, torso_spread, torso_tenth, _ = region_stats(rows, channels, width, height, torso)
    margin_mean, _, _, _ = region_stats(rows, channels, width, height, margin)
    beige_count = count_where(rows, channels, width, height, margin, beige)
    problems = []

    if kind == "day":
        if mean < 50:
            problems.append(f"too dark for the cushion ({mean:.0f}), likely the home screen")
        if beige_count < 30:
            problems.append("left side is not the linen cushion")
        if torso_tenth > 70:
            problems.append("black cat is missing from the torso")
        sleeve_count, sleeve_seen = cover(rows, channels, bottom, sleeve)
        # The linen is not this grey. A life-size sleeve reaching the bottom edge is.
        if sleeve_count / sleeve_seen < 0.02:
            problems.append(f"sleeve does not enter from the bottom ({sleeve_count / sleeve_seen:.1%} grey)")
    elif kind == "night":
        if spread < 12 and torso_spread < 12:
            problems.append(f"flat night frame (spread {spread:.1f}), cat was not drawn")
        if torso_tenth > margin_mean - 15:
            problems.append("night cat is not darker than the cushion")
        margin_pixel = pixel(rows, channels, width // 10, height // 2)
        if margin_pixel[2] + 8 < margin_pixel[0]:
            problems.append("night cushion is not moonlit")
    elif kind == "coats":
        if beige_count < 20:
            problems.append("coat shot is missing the cushion")
        oranges = count_where(rows, channels, width, height, full, orange)
        if oranges < 400:
            problems.append(f"calico orange patches missing ({oranges})")
        if torso_spread < 8:
            problems.append("calico torso has no fur detail")
    elif kind == "paywall":
        papers = count_where(rows, channels, width, height, lower, paper)
        buttons = count_where(rows, channels, width, height, lower, brown)
        if papers < 400:
            problems.append("paywall sheet is not visible")
        if buttons < 80:
            problems.append("paywall button is not visible")
    elif kind == "stroke":
        if mean < 50 or beige_count < 20:
            problems.append("stroke clip is not showing the cushion")
        if count_where(rows, channels, width, height, full, orange) < 300:
            problems.append("ginger cat is not visible for the stroke clip")
    else:
        raise SystemExit(f"unknown shot {kind}")

    if problems:
        raise SystemExit(f"{path.name}: " + "; ".join(problems))
    print(f"{path.name}: ok ({width}x{height}, mean {mean:.0f}, torso {torso_mean:.0f}/{torso_tenth:.0f})")


def main() -> None:
    if len(sys.argv) == 3:
        check(Path(sys.argv[1]), sys.argv[2])
        return
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_shot.py SHOTS_DIR | check_shot.py FILE KIND")
    directory = Path(sys.argv[1])
    for kind in ("day", "night", "coats", "paywall"):
        check(directory / f"en-{kind}.png", kind)


if __name__ == "__main__":
    main()
