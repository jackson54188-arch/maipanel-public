#!/usr/bin/env python3
"""Regenerate tools/frames/*.jpg, the synthetic loop demo_sender.py streams.

Requires Pillow. The picture is a 9:16 game frame (540x960): a name strip in
the top 23.4% and the play disc at 71.9% height, matching what the app crops.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent / "frames"
SIZE = (540, 960)
DISC_CENTER = (269, 690)
DISC_RADIUS = 270
FRAMES = 12


def font(size, bold=False):
    names = (
        "C:/Windows/Fonts/seguisb.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf",
    )
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_frame(index):
    image = Image.new("RGB", SIZE, (11, 11, 18))
    draw = ImageDraw.Draw(image)

    # Name strip: top 23.4% of the frame.
    strip_bottom = round(0.234 * SIZE[1])
    draw.rectangle((0, 0, SIZE[0], strip_bottom), fill=(24, 24, 36))
    draw.rectangle((0, strip_bottom - 12, SIZE[0], strip_bottom - 6), fill=(255, 105, 180))
    draw.text((36, 96), "MAIPANEL", font=font(74, True), fill=(245, 245, 250))
    draw.text((38, 176), "FRAME + STREAM DEMO", font=font(22), fill=(160, 160, 185))

    # Play disc: colour wheel that rotates one step per frame.
    cx, cy = DISC_CENTER
    box = (cx - DISC_RADIUS, cy - DISC_RADIUS, cx + DISC_RADIUS, cy + DISC_RADIUS)
    draw.ellipse(box, fill=(20, 20, 30), outline=(60, 60, 82), width=3)
    for step in range(12):
        start = step * 30 + index * (360 / FRAMES)
        colour = (
            int(120 + 100 * ((step * 37) % 100) / 100),
            int(80 + 90 * ((step * 53) % 100) / 100),
            int(150 + 90 * ((step * 71) % 100) / 100),
        )
        draw.arc(
            (cx - 246, cy - 246, cx + 246, cy + 246),
            start=start,
            end=start + 24,
            fill=colour,
            width=18,
        )
    dot_angle = math.radians(index * (360 / FRAMES))
    dot_x = cx + 210 * math.cos(dot_angle)
    dot_y = cy + 210 * math.sin(dot_angle)
    draw.ellipse((dot_x - 14, dot_y - 14, dot_x + 14, dot_y + 14), fill=(255, 255, 255))

    draw.text((cx, cy - 34), "STREAM", font=font(52, True), fill=(240, 240, 250), anchor="mm")
    draw.text((cx, cy + 34), f"FRAME {index + 1:02d}", font=font(26), fill=(150, 150, 175), anchor="mm")
    return image


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for index in range(FRAMES):
        path = OUT / f"frame_{index:02d}.jpg"
        draw_frame(index).save(path, quality=62, optimize=True)
        print(f"{path} {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
