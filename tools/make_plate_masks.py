#!/usr/bin/env python3
"""Cut a cat out of a cushion plate.

Drop a new coat in as plate-<name>.jpg next to cushion.jpg (same 720x1280
overhead pose) and run:

    python3 tools/make_plate_masks.py

The script writes mask-<name>.png, a rim-lit plate-<name>.jpg, and a circular
swatch-<name>.png. The matte is a smoothed, eroded silhouette with a short
feather. Edge pixels are relit to the shared cushion so a coat's own brighter
fabric cannot show as a pale jagged outline.
"""

import argparse
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1] / "PurrPat" / "Resources" / "Plates"
LIGHT = {"white", "ragdoll", "siamese", "silvertabby"}


def largest(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count <= 1:
        return mask.astype(np.uint8)
    index = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (labels == index).astype(np.uint8)


def fill_small_holes(mask: np.ndarray, max_area: int = 1800) -> np.ndarray:
    inverse = (1 - mask).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(inverse, 8)
    out = mask.copy()
    height, width = mask.shape
    for index in range(1, count):
        x, y, w, h, area = stats[index]
        if x == 0 or y == 0 or x + w >= width or y + h >= height:
            continue
        if area <= max_area:
            out[labels == index] = 1
    return out


def segment_diff(cat: np.ndarray, empty: np.ndarray, core_t: float, fringe_t: float, fringe_px: float) -> np.ndarray:
    diff = cv2.absdiff(cat, empty).max(axis=2).astype(np.float32)
    diff = cv2.GaussianBlur(diff, (0, 0), 0.7)
    core = (diff > core_t).astype(np.uint8)
    small = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    close = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    core = cv2.morphologyEx(core, cv2.MORPH_OPEN, small, iterations=1)
    core = cv2.morphologyEx(core, cv2.MORPH_CLOSE, close, iterations=1)
    core = largest(core)
    core = fill_small_holes(core)
    distance = cv2.distanceTransform((1 - core).astype(np.uint8), cv2.DIST_L2, 3)
    fringe = ((distance > 0) & (distance <= fringe_px) & (diff > fringe_t)).astype(np.uint8)
    mask = largest(np.clip(core + fringe, 0, 1).astype(np.uint8))
    # Pale bellies fail the threshold but are enclosed by fur. The cushion itself touches the frame, so it is not filled.
    mask = fill_small_holes(mask, 10**9)
    return largest(mask)


def lighting_diff(cat: np.ndarray, empty: np.ndarray, outside: np.ndarray) -> np.ndarray:
    cat_f = cat.astype(np.float32)
    empty_f = empty.astype(np.float32)
    height, width = cat.shape[:2]
    small = (width // 4, height // 4)
    weight = cv2.resize(outside.astype(np.float32), small, interpolation=cv2.INTER_AREA)
    gain = np.ones_like(cat_f)
    for channel in range(3):
        num = cv2.GaussianBlur(cv2.resize(cat_f[:, :, channel] * outside, small, interpolation=cv2.INTER_AREA), (0, 0), 8)
        den = cv2.GaussianBlur(cv2.resize(empty_f[:, :, channel] * outside, small, interpolation=cv2.INTER_AREA), (0, 0), 8)
        blurred = cv2.GaussianBlur(weight, (0, 0), 8) + 1e-3
        fitted = np.clip((num / blurred) / (den / blurred + 1e-3), 0.5, 2.2)
        gain[:, :, channel] = cv2.resize(fitted, (width, height), interpolation=cv2.INTER_LINEAR)
    corrected = np.clip(empty_f * gain, 0, 255)
    return np.abs(cat_f - corrected).max(axis=2)


def segment_calico(cat: np.ndarray, empty: np.ndarray, black_mask: np.ndarray) -> np.ndarray:
    """Calico is lit brighter than cushion.jpg. Do not clip it to the black cat: that cut notches in the hip and left a pale gap by the tail."""
    outside = cv2.dilate(black_mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (31, 31))) == 0
    diff = cv2.GaussianBlur(lighting_diff(cat, empty, outside.astype(np.float32)), (0, 0), 0.8)
    raw = (diff > 36).astype(np.uint8)
    small = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    raw = cv2.morphologyEx(raw, cv2.MORPH_OPEN, small, iterations=1)
    raw = cv2.morphologyEx(raw, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)), iterations=2)
    raw = largest(fill_small_holes(raw, 10**9))
    raw = cv2.morphologyEx(raw, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (17, 17)), iterations=1)
    return largest(raw)


def refine(binary: np.ndarray, erode_px: int = 3, feather: float = 2.6) -> tuple[np.ndarray, np.ndarray]:
    """Round the contour, drop the cushion fringe, and feather inside the fur."""
    soft = cv2.GaussianBlur(binary.astype(np.float32), (0, 0), 2.2)
    smooth = largest((soft > 0.55).astype(np.uint8))
    smooth = fill_small_holes(smooth, 2000)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    tight = largest(cv2.erode(smooth, kernel, iterations=erode_px))
    if int(tight.sum()) < 1000:
        tight = smooth
    distance = cv2.distanceTransform(tight, cv2.DIST_L2, 5)
    alpha = np.clip(distance / feather, 0.0, 1.0)
    # A sub-pixel blur removes the stair-step the distance field inherits from the grid.
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.7)
    alpha = np.where(cv2.distanceTransform((1 - tight).astype(np.uint8), cv2.DIST_L2, 3) > feather + 1.5, 0.0, alpha)
    return tight, np.clip(alpha, 0.0, 1.0).astype(np.float32)


def match_edge_light(plate: np.ndarray, cushion: np.ndarray, tight: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Relight the outer fur to the shared cushion, and replace the plate's own fabric outside the matte."""
    distance = cv2.distanceTransform(tight, cv2.DIST_L2, 5)
    background = cv2.inpaint(plate, (tight * 255).astype(np.uint8), 8, cv2.INPAINT_TELEA).astype(np.float32)
    destination = cv2.GaussianBlur(cushion.astype(np.float32), (0, 0), 14)
    source = cv2.GaussianBlur(background, (0, 0), 14) + 1.0
    gain = np.clip(destination / source, 0.7, 1.15)
    weight = np.clip((7.0 - distance) / 7.0, 0.0, 1.0) * (tight == 1)
    fur = plate.astype(np.float32)
    corrected = np.clip(fur * gain, 0, 255)
    lit = fur * (1.0 - weight[..., None]) + corrected * weight[..., None]
    # Anything the matte does not cover is the shared cushion, so a soft sample cannot reveal the plate fabric.
    lit = np.where(alpha[..., None] > 0.01, lit, cushion.astype(np.float32))
    return lit.astype(np.uint8)


def swatch(plate: np.ndarray) -> np.ndarray:
    height, width = plate.shape[:2]
    cx, cy, radius = int(0.50 * width), int(0.46 * height), 54
    crop = cv2.resize(plate[cy - radius : cy + radius, cx - radius : cx + radius], (128, 128))
    yy, xx = np.mgrid[0:128, 0:128]
    circle = (xx - 64) ** 2 + (yy - 64) ** 2 <= 62 ** 2
    image = np.zeros((128, 128, 4), np.uint8)
    image[circle, :3] = crop[circle]
    image[circle, 3] = 255
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=Path, default=ROOT)
    args = parser.parse_args()
    folder = args.dir
    empty = cv2.imread(str(folder / "cushion.jpg"))
    if empty is None:
        raise SystemExit(f"missing {folder / 'cushion.jpg'}")
    plates = sorted(folder.glob("plate-*.jpg"))
    if not plates:
        raise SystemExit(f"no plate-*.jpg in {folder}")

    black = cv2.imread(str(folder / "plate-black.jpg"))
    black_mask = segment_diff(black, empty, 46, 16, 4) if black is not None else None

    for path in plates:
        name = path.stem.removeprefix("plate-")
        cat = cv2.imread(str(path))
        if name == "calico" and black_mask is not None:
            binary = segment_calico(cat, empty, black_mask)
        elif name in LIGHT:
            binary = segment_diff(cat, empty, 26, 13, 5)
        else:
            binary = segment_diff(cat, empty, 40, 16, 5)
        # Light fur is already close to the cloth, so erode less or the body opens up.
        tight, alpha = refine(binary, erode_px=2 if name in LIGHT or name == "calico" else 3)
        cleaned = match_edge_light(cat, empty, tight, alpha)
        cv2.imwrite(str(folder / f"mask-{name}.png"), (alpha * 255.0).astype(np.uint8))
        cv2.imwrite(str(folder / f"plate-{name}.jpg"), cleaned, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
        cv2.imwrite(str(folder / f"swatch-{name}.png"), swatch(cleaned))
        print(f"{name:12} {(alpha > 0.2).mean():.3f}")


if __name__ == "__main__":
    main()
