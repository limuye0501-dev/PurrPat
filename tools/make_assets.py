#!/usr/bin/env python3
"""Build the app icon and the original hand overlays from the keyed source photo."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = Path("/opt/cursor/artifacts/assets/hand-sleeve.jpg")
ASSETS = ROOT / "PurrPat" / "Resources" / "Assets.xcassets"


def key_hand(path: Path) -> Image.Image:
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # The plate is compressed magenta, about (249, 3, 202), not pure #FF00FF.
    # Skin and the grey sleeve both have a real green channel; the plate does not.
    mag = np.clip((np.minimum(r, b + 50) - g - 30) / 70.0, 0, 1)
    alpha = 1.0 - mag
    # Despill the fringe so skin doesn't pick up a pink rim.
    spill = np.clip(np.minimum(r, b + 40) - g, 0, None) * mag
    r = np.clip(r - spill * 0.85, 0, 255)
    b = np.clip(b - spill * 0.55, 0, 255)
    rgba = np.dstack([r, g, b, alpha * 255]).astype(np.uint8)
    im = Image.fromarray(rgba, "RGBA")
    bbox = im.getbbox()
    im = im.crop(bbox)
    long_edge = max(im.size)
    if long_edge > 1400:
        s = 1400 / long_edge
        im = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
    return im


def recolor_sleeve(im: Image.Image, target: tuple[int, int, int] | None) -> Image.Image:
    if target is None:
        return im
    arr = np.asarray(im).astype(np.float32)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = (mx - mn) / (mx + 1)
    h, w = a.shape
    ys = np.linspace(0, 1, h)[:, None]
    # Sleeve sits in the lower portion; nails and skin stay put.
    # Everything grey below the wrist, including the ribbed cuff.
    sleeve = (a > 16) & (sat < 0.22) & (ys > 0.33) & (np.abs(r - b) < 36)
    lum = (0.30 * r + 0.55 * g + 0.15 * b) / 255.0
    scale = lum / 0.58
    tr, tg, tb = target
    arr[..., 0] = np.where(sleeve, np.clip(tr * scale, 0, 255), r)
    arr[..., 1] = np.where(sleeve, np.clip(tg * scale, 0, 255), g)
    arr[..., 2] = np.where(sleeve, np.clip(tb * scale, 0, 255), b)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def fingertip_anchor(im: Image.Image) -> tuple[float, float]:
    """Unit point between the finger pads, a little below the nails."""
    arr = np.asarray(im)
    a = arr[..., 3]
    ys, xs = np.where(a > 80)
    top = int(ys.min())
    # The pads are the opaque row just under the nail line.
    band_y0, band_y1 = top + int(im.height * 0.02), top + int(im.height * 0.07)
    band = (ys >= band_y0) & (ys <= band_y1)
    ax = float(xs[band].mean() / im.width)
    ay = float(ys[band].mean() / im.height)
    return (ax, ay)


def write_imageset(name: str, image: Image.Image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }, indent=2))


def make_icon():
    s = 1024
    im = Image.new("RGBA", (s, s), (244, 228, 208, 255))
    d = ImageDraw.Draw(im, "RGBA")
    d.rounded_rectangle([88, 250, 936, 820], radius=100, fill=(222, 202, 176, 255))
    streak = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(streak).polygon(
        [(120, 260), (300, 230), (560, 800), (340, 840)], fill=(255, 246, 226, 90)
    )
    im.alpha_composite(streak.filter(ImageFilter.GaussianBlur(20)))
    fur = (42, 36, 40, 255)
    d = ImageDraw.Draw(im, "RGBA")
    # shadow
    sh = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([230, 500, 820, 700], fill=(90, 60, 40, 45))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(16)))
    d = ImageDraw.Draw(im, "RGBA")
    d.ellipse([250, 430, 800, 640], fill=fur)
    d.ellipse([190, 455, 390, 640], fill=fur)
    # ears, short triangles on the crown
    d.polygon([(230, 500), (250, 400), (310, 490)], fill=fur)
    d.polygon([(300, 495), (345, 405), (390, 520)], fill=fur)
    d.polygon([(248, 470), (258, 430), (286, 478)], fill=(196, 140, 132, 255))
    d.polygon([(322, 478), (348, 438), (372, 500)], fill=(196, 140, 132, 255))
    # tail curling up-right
    d.line([(760, 520), (860, 470), (900, 540)], fill=fur, width=34)
    d.ellipse([868, 500, 930, 575], fill=fur)
    # one content eye
    d.arc([210, 530, 270, 575], 200, 340, fill=(255, 220, 210, 180), width=4)
    out = ASSETS / "AppIcon.appiconset"
    out.mkdir(parents=True, exist_ok=True)
    im.convert("RGB").save(out / "AppIcon.png", quality=95)
    (out / "Contents.json").write_text(json.dumps({
        "images": [{
            "filename": "AppIcon.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))


def main():
    hand = key_hand(SRC)
    anchor = fingertip_anchor(hand)
    print("fingertip", round(anchor[0], 4), round(anchor[1], 4), "size", hand.size)
    styles = {
        "HandMist": None,
        "HandCream": (214, 198, 176),
        "HandNavy": (54, 70, 108),
        "HandInk": (46, 44, 48),
    }
    for name, color in styles.items():
        write_imageset(name, recolor_sleeve(hand, color))
    # debug dot
    bg = Image.new("RGBA", hand.size, (232, 214, 192, 255))
    bg.alpha_composite(hand)
    dd = ImageDraw.Draw(bg)
    x, y = anchor[0] * hand.width, anchor[1] * hand.height
    dd.ellipse([x - 10, y - 10, x + 10, y + 10], outline=(220, 40, 40, 255), width=4)
    bg.convert("RGB").save("/tmp/purrpreview/hand_anchor.png", quality=90)
    make_icon()
    print("assets ok")


if __name__ == "__main__":
    main()
