"""Draws the Hisaab logo and writes every Android launcher size.

Usage:  python -I tool/make_logo.py

The mark is an "H" for Hisaab whose crossbar is a rising chart line ending in a
cyan node: keeping the tally, and the line going the right way. It sits on the
app's hero gradient (violet -> indigo -> navy) with the same magenta and cyan
blooms, so the icon and the app read as one product.

Outputs (all generated, never hand-edited):
  android/app/src/main/res/mipmap-*/ic_launcher.png            legacy, squircle
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png adaptive fg
  android/app/src/main/res/mipmap-*/ic_launcher_background.png adaptive bg
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png themed icons
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  assets/brand/logo.png (1024, squircle) and assets/brand/mark.png (white mark)
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048  # work size; everything is downsampled for anti-aliasing
RES = 'android/app/src/main/res'

VIOLET = (106, 76, 255)
INDIGO = (67, 56, 202)
NAVY = (30, 58, 138)
MAGENTA = (255, 92, 200)
CYAN = (103, 232, 249)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background(size=S):
    """Diagonal violet -> indigo -> navy with two soft blooms."""
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = lerp(VIOLET, INDIGO, t / 0.55) if t < 0.55 else lerp(INDIGO, NAVY, (t - 0.55) / 0.45)
    for centre, radius, colour, strength in [
        ((size * 0.92, size * 0.04), size * 0.62, MAGENTA, 0.42),
        ((size * 0.04, size * 1.02), size * 0.70, CYAN, 0.30),
    ]:
        glow = Image.new('L', (size, size), 0)
        d = ImageDraw.Draw(glow)
        cx, cy = centre
        d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=int(255 * strength))
        glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.45))
        img = Image.composite(Image.new('RGB', (size, size), colour), img, glow)
    return img


def mark(size=S, scale=1.0, colour=(255, 255, 255), node=CYAN):
    """The H-with-rising-crossbar on transparency. [scale] shrinks it about the
    centre (adaptive icons keep content inside the central 66/108)."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def p(x, y):  # design space 0..1024 -> canvas, scaled about the centre
        c = 512
        return ((c + (x - c) * scale) * size / 1024, (c + (y - c) * scale) * size / 1024)

    w = 92 * scale * size / 1024  # stroke width

    def stroke(a, b):
        d.line([p(*a), p(*b)], fill=colour, width=int(w))
        for x, y in (a, b):
            cx, cy = p(x, y)
            d.ellipse([cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2], fill=colour)

    stroke((330, 258), (330, 766))   # left stem, full height
    stroke((694, 470), (694, 766))   # right stem, shorter: the chart's last bar
    stroke((330, 600), (694, 418))   # rising crossbar
    # The node where the line lands: a cyan dot with a white core.
    cx, cy = p(694, 418)
    r = 74 * scale * size / 1024
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=node + (255,) if len(node) == 3 else node)
    r2 = 30 * scale * size / 1024
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(255, 255, 255, 255))
    return img


def with_shadow(fg, size=S):
    """A soft indigo drop shadow under the mark, for depth on the gradient."""
    alpha = fg.split()[3]
    shadow = Image.new('RGBA', (size, size), (20, 12, 80, 0))
    shadow.putalpha(alpha.point(lambda a: int(a * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.018))
    offset = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    offset.paste(shadow, (0, int(size * 0.014)), shadow)
    return Image.alpha_composite(offset, fg)


def squircle_mask(size=S, radius_ratio=0.235):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    return m


def save(img, path, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(path, optimize=True)


def main():
    bg = background().convert('RGBA')
    full = Image.alpha_composite(bg, with_shadow(mark(scale=0.86)))
    legacy = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    legacy.paste(full, (0, 0), squircle_mask())

    adaptive_fg = with_shadow(mark(scale=0.60))
    mono = mark(scale=0.60, colour=(255, 255, 255), node=(255, 255, 255))

    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, f in densities.items():
        folder = f'{RES}/mipmap-{name}'
        save(legacy, f'{folder}/ic_launcher.png', int(48 * f))
        save(adaptive_fg, f'{folder}/ic_launcher_foreground.png', int(108 * f))
        save(bg, f'{folder}/ic_launcher_background.png', int(108 * f))
        save(mono, f'{folder}/ic_launcher_monochrome.png', int(108 * f))

    os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
    with open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', 'w', encoding='utf-8') as fh:
        fh.write('''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_logo.py. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''')

    save(legacy, 'assets/brand/logo.png', 1024)
    save(mark(scale=0.9, node=CYAN), 'assets/brand/mark.png', 512)
    print('logo written')


if __name__ == '__main__':
    main()
