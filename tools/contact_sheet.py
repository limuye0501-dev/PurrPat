#!/usr/bin/env python3
"""Composite every coat on the shared cushion and write one contact sheet.

The matte is the mask asset itself (the same alpha the renderer uses).
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "PurrPat" / "Resources" / "Plates"
ORDER = [
    "black",
    "ginger",
    "white",
    "calico",
    "silvertabby",
    "tuxedo",
    "bluegrey",
    "ragdoll",
    "tortie",
    "browntabby",
    "siamese",
]


def composite(folder: Path, name: str, width: int) -> Image.Image:
    plate = Image.open(folder / f"plate-{name}.jpg").convert("RGB")
    mask = Image.open(folder / f"mask-{name}.png").convert("L")
    cushion = Image.open(folder / "cushion.jpg").convert("RGB")
    if mask.size != plate.size:
        mask = mask.resize(plate.size, Image.Resampling.BILINEAR)
    if cushion.size != plate.size:
        cushion = cushion.resize(plate.size, Image.Resampling.BILINEAR)
    image = Image.composite(plate, cushion, mask)
    height = max(1, round(width * image.height / image.width))
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, width, 28), fill=(245, 236, 220))
    draw.text((8, 6), name, fill=(50, 36, 24))
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--dir", type=Path, default=ROOT)
    parser.add_argument("--width", type=int, default=280)
    args = parser.parse_args()
    tiles = [composite(args.dir, name, args.width) for name in ORDER]
    columns = 4
    rows = (len(tiles) + columns - 1) // columns
    gap = 8
    cell_w, cell_h = tiles[0].size
    sheet = Image.new("RGB", (columns * cell_w + (columns + 1) * gap, rows * cell_h + (rows + 1) * gap), (232, 224, 210))
    for index, tile in enumerate(tiles):
        x = gap + (index % columns) * (cell_w + gap)
        y = gap + (index // columns) * (cell_h + gap)
        sheet.paste(tile, (x, y))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    print(f"wrote {args.output} {sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
