#!/usr/bin/env python3
"""Exit 0 when a simulator screenshot is the app, 1 when it is Springboard."""

import struct
import subprocess
import sys

def main() -> int:
    src = sys.argv[1]
    bmp = "/tmp/purrpat-probe.bmp"
    subprocess.check_call(
        ["sips", "-s", "format", "bmp", src, "--out", bmp],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    data = open(bmp, "rb").read()
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0] // 8
    row = (width * bpp + 3) & ~3

    def pixel(x: int, y: int) -> tuple[int, int, int]:
        # BMP rows are stored bottom-up.
        index = offset + y * row + x * bpp
        blue, green, red = data[index], data[index + 1], data[index + 2]
        return red, green, blue

    red, green, blue = pixel(width // 2, height // 2)
    # The home screen center is a bright cyan wallpaper. The cat and the paywall are not.
    springboard = (red + green + blue) > 450 and blue > red + 15
    print(f"center {red},{green},{blue} springboard={springboard}")
    return 1 if springboard else 0


if __name__ == "__main__":
    raise SystemExit(main())
