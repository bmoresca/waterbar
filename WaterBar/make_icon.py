#!/usr/bin/env python3
"""Draw WaterBar's droplet icon and assemble WaterBar.icns.

Optional: build.sh skips this (and the app just uses the generic icon) if
Pillow or iconutil aren't around.
"""

import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersample factor; everything is drawn big and scaled down
TOP = (86, 190, 245)
BOTTOM = (14, 78, 152)
ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def droplet_path(cx, cy_circle, radius, tip_y, steps=400):
    """Classic teardrop: a circle, plus the two tangent lines from a point above it."""
    d = cy_circle - tip_y
    if d <= radius:
        raise ValueError("tip must sit outside the circle")
    alpha = math.acos(radius / d)          # half-angle to the tangent points
    start = -math.pi / 2 + alpha           # measured from the circle's centre
    sweep = 2 * math.pi - 2 * alpha

    points = [(cx, tip_y)]
    for i in range(steps + 1):
        theta = start + sweep * (i / steps)
        points.append((cx + radius * math.cos(theta), cy_circle + radius * math.sin(theta)))
    return points


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((size, size), Image.BILINEAR)


def render(size):
    S = size * SS
    mask = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(mask)

    radius = S * 0.285
    cy = S * 0.635
    tip = S * 0.085
    draw.polygon(droplet_path(S / 2, cy, radius, tip), fill=255)

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.paste(vertical_gradient(S, TOP, BOTTOM), (0, 0), mask)

    # A soft highlight, so it reads as a volume of water rather than a blue blob.
    gloss = Image.new("L", (S, S), 0)
    gdraw = ImageDraw.Draw(gloss)
    gdraw.ellipse([S * 0.35, S * 0.52, S * 0.46, S * 0.70], fill=80)
    gloss = gloss.filter(ImageFilter.GaussianBlur(S * 0.02))
    gloss = Image.composite(gloss, Image.new("L", (S, S), 0), mask)
    canvas.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), gloss)

    return canvas.resize((size, size), Image.LANCZOS)


def main(out_path):
    iconset = out_path.replace(".icns", ".iconset")
    os.makedirs(iconset, exist_ok=True)
    for size in ICNS_SIZES:
        img = render(size)
        if size <= 512:
            img.save(os.path.join(iconset, "icon_%dx%d.png" % (size, size)))
        if size >= 32:
            half = size // 2
            img.save(os.path.join(iconset, "icon_%dx%d@2x.png" % (half, half)))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out_path], check=True)
    print("wrote", out_path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "WaterBar.icns")
