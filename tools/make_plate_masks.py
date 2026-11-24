#!/usr/bin/env python3
"""Cut a cat out of a cushion plate.

Drop a new coat in as plate-<name>.jpg next to cushion.jpg (same 720x1280
overhead pose) and run:

    python3 tools/make_plate_masks.py

The script writes mask-<name>.png, a decontaminated plate-<name>.jpg, and a
circular swatch-<name>.png. Calico is lit differently from the empty cushion,
so it is segmented with a low-frequency lighting correction. Every matte is
then eroded, feathered, and unmixed so the photo's own cushion cannot show
as a pale cutout against cushion.jpg.
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
    mask = fill_small_holes(mask, 1200)
    mask = cv2.erode(mask, small, iterations=1)
    return largest(mask)


def lighting_diff(cat: np.ndarray, empty: np.ndarray, outside: np.ndarray) -> np.ndarray:
    cat_f = cat.astype(np.float32)
    empty_f = empty.astype(np.float32)
    height, width = cat.shape[:2]
    small = (width // 4, height // 4)
    weight = cv2.resize(outside.astype(np.float32), small, interpolation=cv2.INTER_AREA)
    gain = np.ones_like(cat_f)
    for channel in range(3):
        num = cv2.GaussianBlur(cv2.resize(cat_f[:, :, channel] * outside, small, interpolation=cv2.INTER_AREA), (0, 0), 10)
        den = cv2.GaussianBlur(cv2.resize(empty_f[:, :, channel] * outside, small, interpolation=cv2.INTER_AREA), (0, 0), 10)
        blurred = cv2.GaussianBlur(weight, (0, 0), 10) + 1e-3
        fitted = np.clip((num / blurred) / (den / blurred + 1e-3), 0.45, 2.4)
        gain[:, :, channel] = cv2.resize(fitted, (width, height), interpolation=cv2.INTER_LINEAR)
    corrected = np.clip(empty_f * gain, 0, 255)
    return np.abs(cat_f - corrected).max(axis=2)


def tighten_and_clean(plate: np.ndarray, cushion: np.ndarray, mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Erode, feather, and unmix the plate's own cushion out of the fur edge.

    A hard pale silhouette is the photo's brighter cushion left inside the matte.
    The rim is solved back to fur colour against that local background, then
    stored over the shared cushion so a soft edge cannot reveal a second fabric.
    """
    binary = (mask > 0).astype(np.uint8)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    core = largest(cv2.erode(binary, kernel, iterations=2))
    if int(core.sum()) < 1000:
        core = binary
    soft = cv2.GaussianBlur(core.astype(np.float32), (0, 0), 1.6)
    outside = cv2.distanceTransform((1 - core).astype(np.uint8), cv2.DIST_L2, 3)
    soft = np.where(outside > 3.0, 0.0, soft)
    soft = np.clip(soft * 1.25, 0.0, 1.0)
    background = cv2.inpaint(plate, (core * 255).astype(np.uint8), 8, cv2.INPAINT_NS)
    alpha = soft[..., None]
    fur = (plate.astype(np.float32) - background.astype(np.float32) * (1.0 - alpha)) / np.maximum(alpha, 0.2)
    fur = np.clip(fur, 0, 255)
    depth = cv2.distanceTransform(core, cv2.DIST_L2, 3)
    deep = np.clip((depth - 4.0) / 3.0, 0.0, 1.0)[..., None]
    fur = fur * (1.0 - deep) + plate.astype(np.float32) * deep
    cleaned = np.where(alpha > 0.02, fur, cushion.astype(np.float32))
    return cleaned.astype(np.uint8), (soft * 255.0).astype(np.uint8)


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

    black_path = folder / "plate-black.jpg"
    black = cv2.imread(str(black_path)) if black_path.exists() else None
    black_mask = segment_diff(black, empty, 46, 16, 6) if black is not None else None
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    allowed = cv2.dilate(black_mask, kernel, iterations=3) if black_mask is not None else None
    core = cv2.erode(black_mask, kernel, iterations=1) if black_mask is not None else None
    outside = cv2.dilate(black_mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (31, 31))) == 0 if black_mask is not None else None

    for path in plates:
        name = path.stem.removeprefix("plate-")
        cat = cv2.imread(str(path))
        if name == "calico" and outside is not None:
            diff = cv2.GaussianBlur(lighting_diff(cat, empty, outside), (0, 0), 0.8)
            raw = (diff > 32).astype(np.uint8)
            small = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
            raw = cv2.morphologyEx(raw, cv2.MORPH_OPEN, small, iterations=1)
            raw = cv2.morphologyEx(raw, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)), iterations=2)
            raw = fill_small_holes(largest(raw), 2000)
            mask = largest(fill_small_holes(raw, 1500))
        elif name in LIGHT:
            mask = segment_diff(cat, empty, 26, 13, 5)
        else:
            mask = segment_diff(cat, empty, 40, 16, 5)
        if allowed is not None and core is not None:
            mask = largest(cv2.bitwise_or(cv2.bitwise_and(mask, allowed), core))
        cleaned, alpha = tighten_and_clean(cat, empty, mask)
        cv2.imwrite(str(folder / f"mask-{name}.png"), alpha)
        cv2.imwrite(str(folder / f"plate-{name}.jpg"), cleaned, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
        cv2.imwrite(str(folder / f"swatch-{name}.png"), swatch(cleaned))
        print(f"{name:12} {(alpha > 16).mean():.3f}")


if __name__ == "__main__":
    main()
