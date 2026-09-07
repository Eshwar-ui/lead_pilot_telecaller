#!/usr/bin/env python3
"""Regenerate every Asan Innovators image in this app from one source file.

    python3 tool/brand/generate_brand_assets.py     # needs Pillow + numpy

`asan_icon_source.png` is the supplied brand icon: the lockup printed on a
white plate. This script lifts the lockup off that plate into a transparent
`assets/images/asan_logo.png` — the single mark the UI draws — and then rebuilds
the launcher/splash/web icons around it, so every surface is the same artwork
instead of the several hand-made variants that used to drift apart.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

APP = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).with_name('asan_icon_source.png')

PLATE = np.array([253.0, 253.0, 253.0])   # the source's off-white background
AMBER = np.array([250.0, 172.0, 12.0])
NAVY = np.array([13.0, 26.0, 48.0])
SUPERSAMPLE = 4
UPSCALE = 3


def cut_out(path: Path) -> Image.Image:
    """The lockup alone, on transparency, cropped to its ink."""
    a = np.array(Image.open(path).convert('RGB')).astype(np.float64)
    h, w, _ = a.shape
    mx, mn = a.max(2), a.min(2)

    # Bound the ink, ignoring a margin so the icon's dark rounded-corner
    # surround is never mistaken for navy lettering.
    m = int(min(h, w) * 0.107)
    inside = np.zeros((h, w), bool)
    inside[m:h - m, m:w - m] = True
    ink = inside & (((mx - mn > 70) & (mx > 130)) | (mx < 110))
    ys, xs = np.nonzero(ink)
    pad = 6
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + 1 + pad, h)
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + 1 + pad, w)
    c = a[y0:y1, x0:x1]

    # Each pixel is plate colour blended with one of two flat inks. Project it
    # onto each plate->ink line: the projection is that ink's coverage, the
    # leftover distance says how well the ink explains the pixel. Keep the
    # better fit's exact brand colour and let the projection be the alpha, so
    # anti-aliasing survives but the colours stay flat.
    def unmix(ink_rgb):
        d = ink_rgb - PLATE
        t = np.clip(((PLATE - c) @ (PLATE - ink_rgb)) / (d @ d), 0.0, 1.0)
        return t, np.linalg.norm(c - (PLATE + t[..., None] * d), axis=-1)

    t_amber, r_amber = unmix(AMBER)
    t_navy, r_navy = unmix(NAVY)
    amber_wins = r_amber <= r_navy

    # Upscale the two coverage maps rather than flat RGB — resampling colour
    # across the amber/navy boundary would fringe it.
    ch, cw = t_amber.shape
    size = (cw * UPSCALE, ch * UPSCALE)

    def up(m):
        img = Image.fromarray((m * 255).astype(np.uint8)).resize(size, Image.LANCZOS)
        return np.clip(np.array(img).astype(np.float64) / 255.0, 0, 1)

    ua = up(np.where(amber_wins, t_amber, 0.0))
    un = up(np.where(amber_wins, 0.0, t_navy))
    alpha = np.clip(ua + un, 0, 1)
    rgb = (ua[..., None] * AMBER + un[..., None] * NAVY) / np.maximum(ua + un, 1e-6)[..., None]
    rgb = np.where(alpha[..., None] > 0, rgb, PLATE)
    stacked = np.dstack([rgb, alpha * 255]).round().clip(0, 255).astype(np.uint8)
    return Image.fromarray(stacked, 'RGBA')


LOGO = cut_out(SOURCE)


def _fit(box_w, box_h):
    s = min(box_w / LOGO.width, box_h / LOGO.height)
    return LOGO.resize((max(1, round(LOGO.width * s)), max(1, round(LOGO.height * s))), Image.LANCZOS)


def _centre(base, mark):
    base.alpha_composite(mark, ((base.width - mark.width) // 2, (base.height - mark.height) // 2))
    return base


def icon(size, inset=0.72, radius=0.225, opaque=False):
    """The mark on a white app-icon plate — rounded, or a flat opaque square."""
    if opaque:
        base = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    else:
        big = Image.new('RGBA', (size * SUPERSAMPLE,) * 2, (255, 255, 255, 0))
        ImageDraw.Draw(big).rounded_rectangle(
            [0, 0, size * SUPERSAMPLE - 1, size * SUPERSAMPLE - 1],
            radius=size * SUPERSAMPLE * radius,
            fill=(255, 255, 255, 255),
        )
        base = big.resize((size, size), Image.LANCZOS)
    return _centre(base, _fit(size * inset, size * inset * 0.90))


def bare(size, inset=0.62):
    """The mark alone, centred on a transparent square canvas."""
    return _centre(Image.new('RGBA', (size, size), (255, 255, 255, 0)), _fit(size * inset, size * inset * 0.90))


def notification_icon(size):
    """Android status-bar icon: a WHITE SILHOUETTE on transparency.

    The system re-tints small icons and throws away their colour, so handing it
    a full-colour launcher icon (what this app used to do) renders as a solid
    blob. Only the bracket frame is used — the script wordmark turns to mush at
    24dp — isolated as the single largest amber component, since "Innovators"
    is the same colour but breaks into separate letter blobs.
    """
    from scipy import ndimage

    a = np.array(LOGO)
    alpha = a[..., 3].astype(np.float64) / 255
    rgb = a[..., :3].astype(int)
    amber = (alpha > 0.3) & (rgb[..., 0] > 150) & (rgb[..., 2] < 120)
    lab, n = ndimage.label(amber)
    frame = lab == (int(np.argmax(ndimage.sum(amber, lab, range(1, n + 1)))) + 1)

    ys, xs = np.nonzero(frame)
    mask = (alpha * frame)[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    art = Image.fromarray((mask * 255).astype(np.uint8))

    # Android expects ~2dp of breathing room inside the 24dp canvas.
    box = round(size * 0.88)
    s = min(box / art.width, box / art.height)
    art = art.resize((max(1, round(art.width * s)), max(1, round(art.height * s))), Image.LANCZOS)

    out = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    white = Image.new('RGBA', art.size, (255, 255, 255, 255))
    white.putalpha(art)
    out.alpha_composite(white, ((size - art.width) // 2, (size - art.height) // 2))
    return out


def save(im, rel, rgb=False):
    path = APP / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    (im.convert('RGB') if rgb else im).save(path, optimize=True)
    print(' ', rel, im.size)


def main():
    save(LOGO, 'assets/images/asan_logo.png')
    # Deliberately NOT under assets/: pubspec declares assets/images/
    # wholesale, so anything left there ships to every device. This is a
    # source for icon generation, referenced by no code.
    save(icon(1024), 'tool/brand/app_icon_1024.png')

    for d, s in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        res = f'android/app/src/main/res/mipmap-{d}'
        save(icon(s), f'{res}/ic_launcher.png')
        save(icon(s), f'{res}/ic_launcher_round.png')
        # Adaptive foreground sits inside the 66/108 safe zone; the white
        # background comes from drawable/ic_launcher_background.xml.
        save(bare(s), f'{res}/ic_launcher_foreground.png')
        # Splash bitmap, drawn over the white launch_background colour.
        save(bare(s * 2, inset=0.86), f'{res}/launch_image.png')

    # iOS icons must be opaque squares — the system applies its own mask.
    for s in [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]:
        save(icon(s, inset=0.80, opaque=True),
             f'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-{s}.png', rgb=True)

    for d, s_ in [('mdpi', 24), ('hdpi', 36), ('xhdpi', 48), ('xxhdpi', 72), ('xxxhdpi', 96)]:
        save(notification_icon(s_),
             f'android/app/src/main/res/drawable-{d}/ic_stat_notification.png')

    save(icon(32), 'web/favicon.png')
    save(icon(192), 'web/icons/Icon-192.png')
    save(icon(512), 'web/icons/Icon-512.png')
    # Maskable icons are cropped to a circle by the launcher, so they are
    # full-bleed with the mark pulled well inside.
    save(icon(192, inset=0.60, opaque=True), 'web/icons/Icon-maskable-192.png')
    save(icon(512, inset=0.60, opaque=True), 'web/icons/Icon-maskable-512.png')


if __name__ == '__main__':
    main()
