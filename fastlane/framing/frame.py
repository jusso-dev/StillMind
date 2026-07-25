#!/usr/bin/env python3
"""Add StillMind branding while preserving each App Store screenshot size."""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOP_GRADIENT = (249, 247, 243)
BOTTOM_GRADIENT = (226, 237, 222)
TEXT_COLOR = (45, 62, 48)
ACCENT_COLOR = (143, 174, 132)


def load_font(size):
    candidates = [
        ("/System/Library/Fonts/SFNSRounded.ttf", ["Bold", "Semibold"]),
        ("/System/Library/Fonts/SFNS.ttf", ["Bold"]),
        ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", [None]),
    ]
    for path, variations in candidates:
        if not os.path.exists(path):
            continue
        try:
            font = ImageFont.truetype(path, size)
        except Exception:
            continue
        for variation in variations:
            if variation is None:
                return font
            try:
                font.set_variation_by_name(variation)
                return font
            except Exception:
                continue
        return font
    return ImageFont.load_default()


def vertical_gradient(width, height):
    strip = Image.new("RGB", (1, height))
    for y in range(height):
        amount = y / max(1, height - 1)
        colour = tuple(
            int(TOP_GRADIENT[channel] * (1 - amount) + BOTTOM_GRADIENT[channel] * amount)
            for channel in range(3)
        )
        strip.putpixel((0, y), colour)
    return strip.resize((width, height))


def rounded(image, radius):
    image = image.convert("RGBA")
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, image.width, image.height],
        radius=radius,
        fill=255,
    )
    image.putalpha(mask)
    return image


def wrapped_lines(draw, text, font, maximum_width):
    lines = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=font) <= maximum_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def main():
    if len(sys.argv) != 4:
        raise SystemExit("Usage: frame.py INPUT CAPTION OUTPUT")

    input_path, caption, output_path = sys.argv[1:]
    screenshot = Image.open(input_path).convert("RGB")
    screenshot.load()
    canvas_width, canvas_height = screenshot.size
    scale = canvas_width / 1320

    canvas = vertical_gradient(canvas_width, canvas_height).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    font = load_font(max(48, int(82 * scale)))
    lines = wrapped_lines(draw, caption, font, canvas_width - int(180 * scale))

    line_height = int(font.size * 1.14)
    caption_y = int(canvas_height * 0.058)
    for line in lines:
        line_width = draw.textlength(line, font=font)
        draw.text(
            ((canvas_width - line_width) / 2, caption_y),
            line,
            font=font,
            fill=TEXT_COLOR,
        )
        caption_y += line_height

    underline_y = caption_y + int(22 * scale)
    underline_width = int(110 * scale)
    underline_height = max(8, int(10 * scale))
    draw.rounded_rectangle(
        [
            canvas_width / 2 - underline_width / 2,
            underline_y,
            canvas_width / 2 + underline_width / 2,
            underline_y + underline_height,
        ],
        radius=underline_height / 2,
        fill=ACCENT_COLOR,
    )

    content_top = underline_y + int(70 * scale)
    content_bottom = canvas_height - int(72 * scale)
    content_height = content_bottom - content_top
    maximum_width = canvas_width - int(250 * scale)
    image_scale = min(content_height / screenshot.height, maximum_width / screenshot.width)
    target_size = (
        int(screenshot.width * image_scale),
        int(screenshot.height * image_scale),
    )
    screenshot = rounded(
        screenshot.resize(target_size, Image.Resampling.LANCZOS),
        max(20, int(38 * scale)),
    )

    x = (canvas_width - screenshot.width) // 2
    y = int(content_top + max(0, (content_height - screenshot.height) / 2))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_mask = Image.new("L", screenshot.size, 0)
    radius = max(20, int(38 * scale))
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        [0, 0, screenshot.width, screenshot.height],
        radius=radius,
        fill=80,
    )
    shadow.paste(
        (24, 40, 28, 80),
        (x, y + int(22 * scale)),
        shadow_mask,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(18, int(34 * scale))))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(screenshot, (x, y), screenshot)
    canvas.convert("RGB").save(output_path, optimize=True)
    print(f"Framed {os.path.basename(output_path)} ({canvas_width}x{canvas_height})")


if __name__ == "__main__":
    main()
