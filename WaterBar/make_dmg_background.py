#!/usr/bin/env python3
"""Draw the DMG window background: a gradient with an arrow between the two icons."""

import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 600, 400
SS = 2  # supersample, then scale down for smooth edges
TOP = (238, 246, 252)
BOTTOM = (214, 232, 246)
ARROW = (140, 175, 200)


def background():
    img = Image.new("RGB", (W * SS, H * SS))
    draw = ImageDraw.Draw(img)
    for y in range(H * SS):
        t = y / (H * SS - 1)
        draw.line([(0, y), (W * SS, y)],
                  fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))

    # A faint droplet watermark, low enough not to fight the icons.
    mark = Image.new("L", (W * SS, H * SS), 0)
    mdraw = ImageDraw.Draw(mark)
    cx, cy, r = W * SS * 0.5, H * SS * 0.80, H * SS * 0.30
    mdraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=26)
    mark = mark.filter(ImageFilter.GaussianBlur(H * SS * 0.05))
    img.paste(Image.new("RGB", img.size, (255, 255, 255)), (0, 0), mark)

    # The drag arrow, sitting between where the two icons land.
    y = int(H * SS * 0.44)
    x0, x1 = int(W * SS * 0.40), int(W * SS * 0.60)
    shaft = int(H * SS * 0.012)
    draw.rounded_rectangle([x0, y - shaft, x1 - shaft * 5, y + shaft],
                           radius=shaft, fill=ARROW)
    draw.polygon([(x1, y), (x1 - shaft * 6, y - shaft * 4), (x1 - shaft * 6, y + shaft * 4)],
                 fill=ARROW)

    return img.resize((W, H), Image.LANCZOS)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "dmg-background.png"
    image = background()
    image.save(out)
    image.resize((W * 2, H * 2), Image.LANCZOS).save(out.replace(".png", "@2x.png"))
    print("wrote", out)
