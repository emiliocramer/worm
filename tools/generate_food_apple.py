#!/usr/bin/env python3
"""Generate the placeholder FoodApple asset: a clean glossy 2D apple, high-res,
transparent background. This is a PLACEHOLDER — swap the PNG for real art. The
app composites each node's logo/emblem onto the center of this apple.

Run: python3 tools/generate_food_apple.py
Writes: Worm/Assets.xcassets/FoodApple.imageset/food-apple.png (1024x1024)
"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 3                      # supersample factor
OUT = 1024
W = OUT * SS

cx = W / 2
cy = W * 0.545              # apple body sits a touch low, room for stem/leaf


def apple_mask():
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    rx, ry = W * 0.255, W * 0.315
    dx = W * 0.118
    for ox in (-dx, dx):
        d.ellipse([cx + ox - rx, cy - ry, cx + ox + rx, cy + ry], fill=255)
    # fill the valley between the two lobes on the lower half so the belly is solid
    d.ellipse([cx - rx * 0.9, cy - ry * 0.2, cx + rx * 0.9, cy + ry], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(SS * 1.2))
    return m


def body():
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    # light source upper-left
    lx, ly = cx - W * 0.14, cy - W * 0.20
    dist = np.sqrt((xx - lx) ** 2 + (yy - ly) ** 2)
    t = np.clip(1.0 - dist / (W * 0.62), 0.0, 1.0) ** 1.35      # highlight weight
    # vertical ambient: brighter mid, darker toward bottom
    v = np.clip((yy - (cy - W * 0.33)) / (W * 0.72), 0.0, 1.0)
    shade = 1.0 - 0.34 * v

    dark = np.array([150, 20, 30], np.float32)
    mid = np.array([206, 36, 44], np.float32)
    light = np.array([242, 104, 82], np.float32)

    col = mid[None, None, :] + (light - mid)[None, None, :] * t[..., None]
    col = col * shade[..., None]
    col = np.clip(col, 0, 255).astype(np.uint8)
    return Image.fromarray(col, "RGB")


def specular(img):
    spec = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(spec)
    sx, sy = cx - W * 0.12, cy - W * 0.20
    d.ellipse([sx - W * 0.11, sy - W * 0.16, sx + W * 0.11, sy + W * 0.16], fill=150)
    spec = spec.filter(ImageFilter.GaussianBlur(W * 0.03))
    white = Image.new("RGB", (W, W), (255, 235, 225))
    return Image.composite(white, img, spec)


def top_pit(img):
    """Darken a soft well at the top-centre where the stem seats — real apples
    have a stem cavity, not a stem stuck onto a smooth dome."""
    pit = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(pit)
    px, py = cx + W * 0.008, cy - W * 0.295
    d.ellipse([px - W * 0.09, py - W * 0.04, px + W * 0.09, py + W * 0.075], fill=150)
    pit = pit.filter(ImageFilter.GaussianBlur(W * 0.038))
    dark = Image.new("RGB", (W, W), (120, 20, 30))
    return Image.composite(dark, img, pit)


def stem(img):
    """A woody stem that rises out of the pit with a slight curve and taper."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bx, by = cx + W * 0.004, cy - W * 0.30       # seated down in the pit
    tx, ty = cx + W * 0.028, cy - W * 0.455      # curves a touch to one side
    ctrlx, ctrly = cx + W * 0.004, cy - W * 0.40
    n = 26
    wb, wt = W * 0.026, W * 0.014
    left, right, spine = [], [], []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * bx + 2 * (1 - t) * t * ctrlx + t * t * tx
        y = (1 - t) ** 2 * by + 2 * (1 - t) * t * ctrly + t * t * ty
        w = wb + (wt - wb) * t
        left.append((x - w, y))
        right.append((x + w, y))
        spine.append((x, y))
    d.polygon(left + right[::-1], fill=(96, 61, 36, 255))
    # rounded cap + a lit edge down one side for roundness
    d.ellipse([tx - wt, ty - wt, tx + wt, ty + wt], fill=(96, 61, 36, 255))
    d.line(left, fill=(128, 88, 55, 255), width=max(2, int(W * 0.006)))
    img.paste(layer, (0, 0), layer)
    return img


def leaf(img):
    """A pointed, veined leaf that springs from the base of the stem — attached,
    not a detached ellipse floating off to the side."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ax, ay = cx + W * 0.012, cy - W * 0.325       # petiole, at the stem base
    length, maxw = W * 0.235, W * 0.135
    n = 56
    top, bot, spine = [], [], []
    for i in range(n + 1):
        t = i / n
        x = ax + t * length
        sy = ay - math.sin(t * math.pi) * length * 0.12    # leaf arcs over
        w = math.sin(math.pi * (t ** 0.8)) * (maxw / 2) * (1 - 0.22 * t)  # taper to a point
        top.append((x, sy - w))
        bot.append((x, sy + w))
        spine.append((x, sy))
    d.polygon(top + bot[::-1], fill=(83, 144, 62, 255))
    d.polygon(top + spine[::-1], fill=(122, 176, 88, 255))   # lit upper half
    d.line(spine, fill=(58, 108, 44, 255), width=max(2, int(maxw * 0.05)))
    for k in range(1, 5):                                    # side veins, swept forward
        t = k / 5.0
        i = int(t * n)
        sx, sy = spine[i]
        wv = math.sin(math.pi * (t ** 0.8)) * (maxw / 2) * (1 - 0.22 * t)
        d.line([(sx, sy), (sx + length * 0.13, sy - wv * 0.72)], fill=(64, 116, 48, 200), width=max(1, int(maxw * 0.028)))
        d.line([(sx, sy), (sx + length * 0.13, sy + wv * 0.72)], fill=(48, 94, 36, 200), width=max(1, int(maxw * 0.028)))
    # Rotate about the petiole so the leaf lifts up and away from the stem.
    layer = layer.rotate(128, center=(ax, ay), resample=Image.BICUBIC)
    img.paste(layer, (0, 0), layer)
    return img


def main():
    img = body()
    img = specular(img)
    img = top_pit(img)
    img = img.convert("RGBA")
    img.putalpha(apple_mask())
    img = leaf(img)      # leaf tucks behind the stem
    img = stem(img)
    img = img.resize((OUT, OUT), Image.LANCZOS)

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dest_dir = os.path.join(here, "Worm/Assets.xcassets/FoodApple.imageset")
    os.makedirs(dest_dir, exist_ok=True)
    img.save(os.path.join(dest_dir, "food-apple.png"))
    print("wrote", os.path.join(dest_dir, "food-apple.png"))


if __name__ == "__main__":
    main()
