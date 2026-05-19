#!/usr/bin/env python3
"""Generates AppIcon.iconset for AI Usage — a usage gauge on an indigo squircle."""
from PIL import Image, ImageDraw
import math, os

OUT = "AppIcon.iconset"
os.makedirs(OUT, exist_ok=True)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gauge_color(t):
    # green -> amber -> red, as the gauge fills up
    green, amber, red = (54, 206, 127), (242, 182, 58), (231, 86, 71)
    return lerp(green, amber, t / 0.5) if t < 0.5 else lerp(amber, red, (t - 0.5) / 0.5)


def render(S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    margin = S * 0.085
    radius = (S - 2 * margin) * 0.2237

    # indigo vertical-gradient background, clipped to a rounded square
    strip = Image.new("RGBA", (1, S))
    top, bottom = (98, 86, 188), (44, 36, 96)
    for y in range(S):
        strip.putpixel((0, y), lerp(top, bottom, y / (S - 1)) + (255,))
    strip = strip.resize((S, S))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, S - margin, S - margin], radius=radius, fill=255)
    img.paste(strip, (0, 0), mask)

    d = ImageDraw.Draw(img)
    cx, cy = S / 2, S / 2 + S * 0.015
    R = (S - 2 * margin) * 0.30
    W = S * 0.088
    box = [cx - R, cy - R, cx + R, cy + R]
    start, span, frac = 135, 270, 0.70

    # faint track
    d.arc(box, start, start + span, fill=(255, 255, 255, 42), width=int(round(W)))

    # value arc — segmented so it fades green -> red
    steps = 160
    for i in range(steps):
        a0 = start + span * frac * (i / steps)
        a1 = start + span * frac * ((i + 1) / steps) + 0.9
        d.arc(box, a0, a1, fill=gauge_color(i / steps) + (255,), width=int(round(W)))

    # rounded caps at both ends of the value arc
    for ang, t in [(start, 0.0), (start + span * frac, 1.0)]:
        rr = math.radians(ang)
        px, py = cx + R * math.cos(rr), cy + R * math.sin(rr)
        d.ellipse([px - W / 2, py - W / 2, px + W / 2, py + W / 2],
                  fill=gauge_color(t) + (255,))

    # needle
    ang = math.radians(start + span * frac)
    tip = (cx + (R + W * 0.18) * math.cos(ang), cy + (R + W * 0.18) * math.sin(ang))
    perp = ang + math.pi / 2
    bw = W * 0.32
    base1 = (cx + bw * math.cos(perp), cy + bw * math.sin(perp))
    base2 = (cx - bw * math.cos(perp), cy - bw * math.sin(perp))
    d.polygon([tip, base1, base2], fill=(255, 255, 255, 255))

    # center hub
    hub = W * 0.60
    d.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=(255, 255, 255, 255))
    d.ellipse([cx - hub * 0.48, cy - hub * 0.48, cx + hub * 0.48, cy + hub * 0.48],
              fill=(70, 58, 132, 255))
    return img


SIZES = {
    16:  ["16x16"],
    32:  ["16x16@2x", "32x32"],
    64:  ["32x32@2x"],
    128: ["128x128"],
    256: ["128x128@2x", "256x256"],
    512: ["256x256@2x", "512x512"],
    1024: ["512x512@2x"],
}
for size, names in SIZES.items():
    im = render(size)
    for name in names:
        im.save(os.path.join(OUT, f"icon_{name}.png"))
print("AppIcon.iconset written")
