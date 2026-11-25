#!/usr/bin/env python3
"""The App Store's screenshots in their frames (docs/app-store.md).

Takes the simulator's pictures (scripts/capture_screenshots.sh: screenshots/raw/<device>/<language>/
NN-screen.png) and lays each on a dark page under a headline in Inter: the device in its bezel on a
glow of its own colour; the first frame a tilted phone with the app's trophy flying around it in
the four metals; on a phone, the card that matters lifted out of the screen (Plati's warning, the
chapter's missable). The owner's choices (2026-11-25): Inter, a dark page, the first frame tilted.

Out: screenshots/store/<device>/<language>/NN-screen.png in the store's sizes (the iPhone 6.9" at
1320×2868, the iPad 13" at 2064×2752), and a contact sheet per device and language.

Usage:
    python3 scripts/store_frames.py --font <DesignKit>/Sources/DesignTokens/Resources/Fonts/Inter-VariableFont_opsz,wght.ttf
    python3 scripts/store_frames.py --raw screenshots/raw --out screenshots/store --font … --only ru
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "ios/Platina/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

WHITE = (255, 255, 255)
PLASMA_ON_DARK = (255, 79, 160)  # the accent in dark mode, #FF4FA0
PAGE_TOP, PAGE_BOTTOM = (22, 8, 24), (6, 3, 10)

# Glows behind the devices: the accent and its neighbours, a warm one for the game's art.
AMBER, PLASMA, VIOLET, ROSE, INDIGO = (214, 90, 40), (214, 0, 111), (150, 40, 190), (226, 40, 80), (70, 60, 200)

# The trophy metals (PlatinaPalette), lighter and deeper for a medal's face.
METALS = {
    "platinum": ((214, 232, 250), (122, 160, 196), (70, 98, 130)),
    "gold": ((255, 226, 140), (214, 163, 36), (130, 92, 10)),
    "silver": ((236, 240, 245), (150, 158, 168), (88, 94, 104)),
    "bronze": ((240, 182, 130), (176, 112, 64), (104, 60, 28)),
}

# The store's order: the screen, its headline in two lines (the second in the accent), its glow,
# and what the frame does beyond the device.
FRAMES = [
    ("game", {"ru": ("Каждый трофей.", "До платины."), "en": ("Every trophy.", "All the way to platinum.")}, AMBER, "tilt"),
    ("plati", {"ru": ("Плати знает,", "что дальше"), "en": ("Plati knows", "what’s next")}, PLASMA, "warning"),
    ("chapter", {"ru": ("Ни одного", "пропущенного"), "en": ("Never miss", "a missable")}, VIOLET, "missable"),
    ("session", {"ru": ("Играйте сессиями", "с целями"), "en": ("Play in sessions", "with goals")}, ROSE, None),
    ("walkthrough", {"ru": ("Вся игра", "по главам"), "en": ("The whole game,", "chapter by chapter")}, PLASMA, None),
    ("guide", {"ru": ("Сложность, часы,", "пропускаемое"), "en": ("Difficulty, hours,", "missables")}, INDIGO, None),
    ("path", {"ru": ("Всё, что вы", "добиваете"), "en": ("Every game", "you’re chasing")}, VIOLET, None),
    ("library", {"ru": ("Вся библиотека", "в одном месте"), "en": ("Your whole library", "in one place")}, AMBER, None),
    ("profile", {"ru": ("Статистика", "и серии"), "en": ("Stats", "and streaks")}, PLASMA, None),
]

# Per device: the page, the headline, the device on it, its bezel and screen corner.
DEVICES = {
    "iphone": dict(size=(1320, 2868), title_y=190, title_size=118, margin=90,
                   device_width=1000, device_y=560, corner=150, bezel=34, tilt_width=1060),
    "ipad": dict(size=(2064, 2752), title_y=170, title_size=150, margin=140,
                 device_width=1580, device_y=560, corner=90, bezel=52, tilt_width=1480),
}


class Fonts:
    def __init__(self, path):
        self.path = path
        self.cache = {}

    def get(self, size, weight=800):
        key = (size, weight)
        if key not in self.cache:
            font = ImageFont.truetype(self.path, size)
            try:
                font.set_variation_by_axes([32, weight])  # Inter: optical size, weight
            except (OSError, ValueError):
                pass  # a static Inter
            self.cache[key] = font
        return self.cache[key]


def page(size, glow, glow_center, glow_radius):
    width, height = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / (height - 1)
        draw.line([(0, y), (width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(PAGE_TOP, PAGE_BOTTOM)))
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    gx, gy = glow_center
    ImageDraw.Draw(halo).ellipse([gx - glow_radius, gy - glow_radius, gx + glow_radius, gy + glow_radius], fill=glow + (150,))
    halo = halo.filter(ImageFilter.GaussianBlur(glow_radius * 0.6))
    img = img.convert("RGBA")
    img.alpha_composite(halo)
    return img


def headline(img, lines, spec, fonts):
    """Two centred lines, the second in the accent, shrunk until the longer fits."""
    draw = ImageDraw.Draw(img)
    width = img.width - 2 * spec["margin"]
    size = spec["title_size"]
    while size > 40 and max(draw.textlength(line, font=fonts.get(size)) for line in lines) > width:
        size -= 2
    font = fonts.get(size)
    for i, line in enumerate(lines):
        x = (img.width - draw.textlength(line, font=font)) / 2
        draw.text((x, spec["title_y"] + i * size * 1.12), line, font=font, fill=PLASMA_ON_DARK if i else WHITE)


def device(shot, width, spec):
    """The screenshot in a black bezel with rounded corners, on a soft shadow."""
    scale = width / shot.width
    screen = shot.resize((width, round(shot.height * scale)), Image.LANCZOS).convert("RGBA")
    radius, bezel = round(spec["corner"] * scale), round(spec["bezel"] * scale)
    w, h = screen.width + 2 * bezel, screen.height + 2 * bezel
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen.width - 1, screen.height - 1], radius, fill=255)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius + bezel, fill=(12, 12, 14, 255))
    draw.rounded_rectangle([3, 3, w - 4, h - 4], radius + bezel - 3, outline=(70, 72, 80, 255), width=4)
    body.paste(screen, (bezel, bezel), mask)
    pad = 100
    out = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(out).rounded_rectangle([pad, pad + 30, w + pad, h + pad + 30], radius + bezel, fill=(0, 0, 0, 150))
    out = out.filter(ImageFilter.GaussianBlur(50))
    out.alpha_composite(body, (pad, pad))
    return out, pad


def lifted(shot, box, width, tilt):
    """A part of the screen lifted out of the device, larger, on a shadow."""
    part = shot.crop(box).convert("RGBA")
    part = part.resize((width, round(part.height * width / part.width)), Image.LANCZOS)
    mask = Image.new("L", part.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, part.width - 1, part.height - 1], 46, fill=255)
    out = Image.new("RGBA", (part.width + 160, part.height + 160), (0, 0, 0, 0))
    ImageDraw.Draw(out).rounded_rectangle([80, 100, part.width + 80, part.height + 100], 46, fill=(0, 0, 0, 170))
    out = out.filter(ImageFilter.GaussianBlur(34))
    out.paste(part, (80, 80), mask)
    return out.rotate(tilt, resample=Image.BICUBIC, expand=True)


# MARK: Finding the cards on a phone's screen

def _run(shot, x, test, start, end):
    """The first run of rows from `start` where the pixel at `x` passes `test`: (top, bottom)."""
    px = shot.load()
    top = None
    for y in range(start, end):
        if test(px[x, y][:3]):
            if top is None:
                top = y
        elif top is not None:
            if y - top > 40:
                return top, y
            top = None
    return None


def _peach(c):
    r, g, b = c
    # Warm, not the accent's pale pink of a chip (whose blue is above its green).
    return r > 236 and 220 <= g <= 246 and 208 <= b <= 238 and r - b > 10 and g - b >= 4


def _card_grey(c):
    r, g, b = c
    return abs(r - 242) <= 5 and abs(g - 242) <= 5 and abs(b - 247) <= 5


def warning_box(shot):
    """Plati's warning card in the chat (its peach fill at the card's left edge)."""
    found = _run(shot, 60, _peach, 300, shot.height - 400)
    return (48, found[0], shot.width - 48, found[1]) if found else None


def missable_box(shot):
    """The chapter's card that opens with "lost for good": its grey card around the peach banner."""
    banner = _run(shot, 150, _peach, 300, shot.height - 400)
    if not banner:
        return None
    px = shot.load()
    top = banner[0]
    while top > 0 and _card_grey(px[60, top - 1][:3]):
        top -= 1
    bottom = banner[1]
    while bottom < shot.height and _card_grey(px[60, bottom][:3]):
        bottom += 1
    return (48, top, shot.width - 48, bottom)


# MARK: The flying trophies

def trophy_mask():
    """The app icon's trophy as a mask (its pale figure on the dark gradient)."""
    icon = Image.open(ICON).convert("RGB")
    mask = icon.getchannel("G").point(lambda g: 255 if g > 150 else 0)
    return mask.crop(mask.getbbox())


def medal(diameter, metal, figure):
    """A round badge in a metal with the trophy on it, drawn twice as large and scaled down."""
    light, mid, deep = METALS[metal]
    d = diameter * 2
    face = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    draw = ImageDraw.Draw(face)
    # The rim, then the face as rings from deep at the edge to light at the upper left.
    draw.ellipse([0, 0, d - 1, d - 1], fill=deep + (255,))
    inset = d * 0.06
    steps = 60
    for i in range(steps):
        t = i / (steps - 1)
        r = (d / 2 - inset) * (1 - t * 0.95)
        cx, cy = d / 2 - t * d * 0.08, d / 2 - t * d * 0.10
        color = tuple(round(m + (l - m) * t) for m, l in zip(mid, light)) if t > 0.4 else tuple(round(dp + (m - dp) * t / 0.4) for dp, m in zip(deep, mid))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
    draw.ellipse([inset, inset, d - 1 - inset, d - 1 - inset], outline=light + (255,), width=max(2, round(d * 0.018)))
    # The trophy, white with a shade under it.
    fw = round(d * 0.46)
    fig = figure.resize((fw, round(figure.height * fw / figure.width)), Image.LANCZOS)
    fx, fy = (d - fig.width) // 2, (d - fig.height) // 2 + round(d * 0.01)
    shade = Image.new("RGBA", fig.size, deep + (150,))
    face.paste(shade, (fx, fy + round(d * 0.012)), fig)
    face.paste(Image.new("RGBA", fig.size, (255, 255, 255, 245)), (fx, fy), fig)
    return face.resize((diameter, diameter), Image.LANCZOS)


def place_medal(img, diameter, metal, center, tilt, figure, blur=0):
    m = medal(diameter, metal, figure).rotate(tilt, resample=Image.BICUBIC, expand=True)
    glow = Image.new("RGBA", (m.width + diameter, m.height + diameter), (0, 0, 0, 0))
    r = diameter * 0.55
    gx, gy = glow.width / 2, glow.height / 2
    ImageDraw.Draw(glow).ellipse([gx - r, gy - r, gx + r, gy + r], fill=METALS[metal][1] + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(diameter * 0.3))
    img.alpha_composite(glow, (round(center[0] - glow.width / 2), round(center[1] - glow.height / 2)))
    if blur:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(m, (round(center[0] - m.width / 2), round(center[1] - m.height / 2)))


def sparkle(img, center, size, alpha=230):
    """A four-pointed glint."""
    layer = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    c, s, w = size, size, size * 0.16
    draw.polygon([(c, c - s), (c + w, c - w), (c + s, c), (c + w, c + w), (c, c + s), (c - w, c + w), (c - s, c), (c - w, c - w)], fill=(255, 240, 248, alpha))
    halo = layer.filter(ImageFilter.GaussianBlur(size * 0.25))
    img.alpha_composite(halo, (center[0] - size, center[1] - size))
    img.alpha_composite(layer, (center[0] - size, center[1] - size))


# MARK: Frames

def render(device_kind, shot, lines, glow, extra, spec, fonts, figure):
    width, height = spec["size"]
    img = page(spec["size"], glow, (width // 2, round(height * 0.45)), round(width * 0.58))
    headline(img, lines, spec, fonts)

    if extra == "tilt":
        # The medals' layout is drawn for the phone's page: places follow the page, sizes grow
        # less on the iPad's, so they fly around the device rather than over it.
        ux, uy, u = width / 1320, height / 2868, min(width / 1320, 1.1)
        body, pad = device(shot, spec["tilt_width"], spec)
        tilted = body.rotate(-8, resample=Image.BICUBIC, expand=True)
        x = (width - tilted.width) // 2 + round(60 * ux)
        y = spec["device_y"] - round(40 * uy)
        # A far one behind the device, the rest flying in front of it around its edges.
        place_medal(img, round(120 * u), "gold", (round(1180 * ux), round(620 * uy)), -10, figure, blur=3)
        img.alpha_composite(tilted, (x, y))
        place_medal(img, round(330 * u), "platinum", (round(210 * ux), round(1000 * uy)), -14, figure)
        place_medal(img, round(240 * u), "gold", (round(1190 * ux), round(1330 * uy)), 12, figure)
        place_medal(img, round(210 * u), "silver", (round(1150 * ux), round(2120 * uy)), 16, figure)
        place_medal(img, round(180 * u), "bronze", (round(150 * ux), round(2380 * uy)), -18, figure, blur=1)
        for cx, cy, size in [(410, 760, 36), (1010, 1520, 28), (180, 1520, 22), (1240, 1760, 30), (560, 2500, 26)]:
            sparkle(img, (round(cx * ux), round(cy * uy)), round(size * u))
    else:
        body, pad = device(shot, spec["device_width"], spec)
        img.alpha_composite(body, ((width - body.width) // 2, spec["device_y"] - pad))
        if extra and device_kind == "iphone":
            box = warning_box(shot) if extra == "warning" else missable_box(shot)
            if box:
                tilt = -3 if extra == "warning" else 2.5
                card_width = 1160 if extra == "warning" else 1100
                card = lifted(shot, box, card_width, tilt)
                img.alpha_composite(card, ((width - card.width) // 2 + (-10 if extra == "warning" else 30), 1780))
            else:
                print(f"  (no card to lift for {extra})")
    return img.convert("RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", default=os.path.join(ROOT, "screenshots/raw"))
    parser.add_argument("--out", default=os.path.join(ROOT, "screenshots/store"))
    parser.add_argument("--font", required=True, help="Inter: DesignKit's variable font or a static ExtraBold")
    parser.add_argument("--only", nargs="*", default=[], help="devices or languages to keep (iphone, ipad, ru, en)")
    args = parser.parse_args()

    fonts = Fonts(args.font)
    figure = trophy_mask()
    only_devices = [o for o in args.only if o in DEVICES]
    only_languages = [o for o in args.only if o in ("ru", "en")]
    made = 0
    for kind in DEVICES:
        for language in ("ru", "en"):
            if (only_devices and kind not in only_devices) or (only_languages and language not in only_languages):
                continue
            source = os.path.join(args.raw, kind, language)
            if not os.path.isdir(source):
                continue
            shots = {name.split("-", 1)[1].rsplit(".", 1)[0]: os.path.join(source, name)
                     for name in os.listdir(source) if name.endswith(".png") and "-" in name}
            target = os.path.join(args.out, kind, language)
            os.makedirs(target, exist_ok=True)
            done = []
            for number, (screen, titles, glow, extra) in enumerate(FRAMES, start=1):
                if screen not in shots:
                    continue
                shot = Image.open(shots[screen]).convert("RGB")
                if shot.size != DEVICES[kind]["size"]:
                    print(f"  {kind}/{language}/{screen}: {shot.size[0]}×{shot.size[1]}, not the store's size")
                frame = render(kind, shot, titles[language], glow, extra, DEVICES[kind], fonts, figure)
                path = os.path.join(target, f"{number:02d}-{screen}.png")
                frame.save(path)
                done.append(frame)
                made += 1
                print(f"✓ {os.path.relpath(path, args.out)}")
            if done:
                contact_sheet(done, os.path.join(args.out, f"sheet-{kind}-{language}.jpg"))
    if not made:
        sys.exit(f"No screenshots under {args.raw}/<device>/<language>/")


def contact_sheet(frames, path, per_row=5, height=900):
    thumbs = [f.resize((round(f.width * height / f.height), height), Image.LANCZOS) for f in frames]
    rows = math.ceil(len(thumbs) / per_row)
    width = max(sum(t.width for t in thumbs[r * per_row:(r + 1) * per_row]) for r in range(rows)) + 20 * (per_row + 1)
    sheet = Image.new("RGB", (width, rows * (height + 20) + 20), (30, 30, 30))
    for i, thumb in enumerate(thumbs):
        row, col = divmod(i, per_row)
        x = 20 + sum(t.width + 20 for t in thumbs[row * per_row:row * per_row + col])
        sheet.paste(thumb, (x, 20 + row * (height + 20)))
    sheet.save(path, quality=85)


if __name__ == "__main__":
    main()
