"""Store icons for One More Floor products and passes (Midnight Deco style, primitives only).

Run: python -I assets/icons/make_icons.py   -> writes 512x512 PNGs next to this script.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))
S = 1024  # drawn at 2x, downsampled to 512

INK_IN = (40, 30, 62)
INK_OUT = (10, 8, 18)
BRASS = (205, 160, 92)
BRASS_DIM = (120, 90, 52)
GOLD = (255, 205, 80)
CYAN = (70, 220, 255)
MAGENTA = (255, 80, 200)
VIOLET = (175, 100, 255)
IVORY = (255, 244, 225)
RED = (255, 70, 90)
GREEN = (90, 235, 140)

FONT = "C:/Windows/Fonts/bahnschrift.ttf"


def background():
    img = Image.new("RGB", (S, S), INK_OUT)
    px = img.load()
    c = S / 2
    for y in range(S):
        for x in range(S):
            d = min(math.hypot(x - c, y - c) / (S * 0.62), 1)
            t = d * d
            px[x, y] = tuple(int(INK_IN[i] * (1 - t) + INK_OUT[i] * t) for i in range(3))
    return img.convert("RGBA")


def sunburst(img, color, count=24, alpha=26):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = S / 2
    for k in range(count):
        a0 = (k / count) * math.tau
        a1 = a0 + math.tau / count * 0.42
        pts = [(c, c), (c + math.cos(a0) * S, c + math.sin(a0) * S), (c + math.cos(a1) * S, c + math.sin(a1) * S)]
        d.polygon(pts, fill=color + (alpha,))
    img.alpha_composite(layer)


def frame(img):
    d = ImageDraw.Draw(img)
    m, cut = 54, 120
    def octagon(inset):
        a, b, k = m + inset, S - m - inset, cut - inset * 0.4
        return [(a + k, a), (b - k, a), (b, a + k), (b, b - k), (b - k, b), (a + k, b), (a, b - k), (a, a + k)]
    d.line(octagon(0) + [octagon(0)[0]], fill=BRASS, width=10, joint="curve")
    d.line(octagon(26) + [octagon(26)[0]], fill=BRASS_DIM, width=4, joint="curve")
    # deco corner studs
    for x, y in [(S / 2, m), (S / 2, S - m), (m, S / 2), (S - m, S / 2)]:
        d.regular_polygon((x, y, 16), 4, rotation=45, fill=BRASS)


def glow_draw(img, draw_fn, color, blur=26, strength=2):
    """Draws a shape with a neon glow: blurred copies underneath, crisp shape on top."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer), color)
    halo = layer.filter(ImageFilter.GaussianBlur(blur))
    for _ in range(strength):
        img.alpha_composite(halo)
    img.alpha_composite(layer)


def text(img, s, size, y, color, glow=True, dx=0):
    font = ImageFont.truetype(FONT, size)
    def fn(d, col):
        try:
            font.set_variation_by_name("Bold")
        except Exception:
            pass
        w = d.textlength(s, font=font)
        d.text(((S - w) / 2 + dx, y), s, font=font, fill=col)
    if glow:
        glow_draw(img, fn, color, blur=18, strength=1)
    else:
        fn(ImageDraw.Draw(img), color)


def heart(d, col, cx=S / 2, cy=S / 2 + 10, r=150):
    d.ellipse((cx - r * 1.9, cy - r * 1.25, cx - r * 0.1 + 6, cy + r * 0.55), fill=col)
    d.ellipse((cx + r * 0.1 - 6, cy - r * 1.25, cx + r * 1.9, cy + r * 0.55), fill=col)
    d.polygon([(cx - r * 1.83, cy - r * 0.15), (cx + r * 1.83, cy - r * 0.15), (cx, cy + r * 1.75)], fill=col)


def coin(d, cx, cy, r, col=GOLD):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    d.ellipse((cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72), outline=(150, 100, 30), width=max(int(r * 0.09), 3))
    d.rectangle((cx - r * 0.1, cy - r * 0.42, cx + r * 0.1, cy + r * 0.42), fill=(150, 100, 30))


def coin_stack(d, cx, base_y, n, r=120, col=GOLD):
    for k in range(n):
        y = base_y - k * r * 0.32
        d.ellipse((cx - r, y - r * 0.38, cx + r, y + r * 0.38), fill=(170, 115, 35), outline=(110, 70, 20), width=4)
        d.ellipse((cx - r, y - r * 0.38 - 18, cx + r, y + r * 0.38 - 18), fill=col, outline=(150, 100, 30), width=4)


def save(img, name):
    img.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def base(ray_color):
    img = background()
    sunburst(img, ray_color)
    frame(img)
    return img


def extra_life(tier):
    img = base(CYAN)
    glow_draw(img, lambda d, c: heart(d, c), CYAN)
    # inner highlight
    d = ImageDraw.Draw(img)
    d.ellipse((S / 2 - 210, S / 2 - 150, S / 2 - 120, S / 2 - 60), fill=(200, 250, 255, 200))
    # tier pips
    for k in range(3):
        x = S / 2 + (k - 1) * 70
        col = IVORY if k < tier else BRASS_DIM
        d.regular_polygon((x, S - 175, 20), 4, rotation=45, fill=col)
    save(img, f"ExtraLife{'' if tier == 1 else tier}")


def curse():
    img = base(VIOLET)
    def eye(d, c):
        cx, cy = S / 2, S / 2
        d.chord((cx - 300, cy - 230, cx + 300, cy + 230), 200, 340, fill=c)
        d.chord((cx - 300, cy - 230, cx + 300, cy + 230), 20, 160, fill=c)
        d.ellipse((cx - 130, cy - 130, cx + 130, cy + 130), fill=(30, 10, 50))
        d.ellipse((cx - 70, cy - 70, cx + 70, cy + 70), fill=c)
        for k in range(7):
            a = math.pi + (k + 1) / 8 * math.pi
            x0, y0 = cx + math.cos(a) * 250, cy + math.sin(a) * 150
            d.line((x0, y0, x0 + math.cos(a) * 80, y0 + math.sin(a) * 80), fill=c, width=16)
    glow_draw(img, eye, VIOLET)
    save(img, "CurseElevator")


def bless():
    img = base(CYAN)
    def shield(d, c):
        cx, cy = S / 2, S / 2 + 60
        d.polygon([(cx - 190, cy - 170), (cx + 190, cy - 170), (cx + 175, cy + 40), (cx, cy + 230), (cx - 175, cy + 40)], fill=c)
        d.polygon([(cx - 120, cy - 115), (cx + 120, cy - 115), (cx + 110, cy + 25), (cx, cy + 150), (cx - 110, cy + 25)], fill=(20, 40, 70))
        d.ellipse((cx - 170, cy - 330, cx + 170, cy - 240), outline=IVORY, width=22)
    glow_draw(img, shield, CYAN)
    save(img, "BlessElevator")


def golden():
    img = base(GOLD)
    def doors(d, c):
        cx, cy = S / 2, S / 2 + 40
        d.rectangle((cx - 230, cy - 250, cx + 230, cy + 250), outline=c, width=20)
        d.rectangle((cx - 205, cy - 225, cx - 8, cy + 225), fill=(120, 80, 20))
        d.rectangle((cx + 8, cy - 225, cx + 205, cy + 225), fill=(120, 80, 20))
        d.pieslice((cx - 230, cy - 400, cx + 230, cy - 100), 180, 360, fill=c)
    glow_draw(img, doors, GOLD)
    text(img, "x2", 220, S / 2 - 70, IVORY)
    save(img, "GoldenElevator")


def cash(name, n):
    img = base(GOLD)
    def stacks(d, c):
        if n == 1:
            coin_stack(d, S / 2, S / 2 + 160, 4, 150)
        elif n == 2:
            coin_stack(d, S / 2 - 140, S / 2 + 190, 4, 130)
            coin_stack(d, S / 2 + 140, S / 2 + 190, 6, 130)
        else:
            coin_stack(d, S / 2 - 210, S / 2 + 220, 4, 115)
            coin_stack(d, S / 2 + 210, S / 2 + 220, 5, 115)
            coin_stack(d, S / 2, S / 2 + 240, 8, 125)
    glow_draw(img, stacks, GOLD, blur=30, strength=1)
    save(img, name)


def vip():
    img = base(GOLD)
    def crown(d, c):
        cx, cy = S / 2, S / 2 + 40
        d.polygon([(cx - 270, cy + 150), (cx - 290, cy - 170), (cx - 130, cy - 20), (cx, cy - 230), (cx + 130, cy - 20), (cx + 290, cy - 170), (cx + 270, cy + 150)], fill=c)
        d.rectangle((cx - 270, cy + 170, cx + 270, cy + 230), fill=c)
        for x, y in [(cx - 290, cy - 190), (cx, cy - 250), (cx + 290, cy - 190)]:
            d.ellipse((x - 34, y - 34, x + 34, y + 34), fill=IVORY)
        d.regular_polygon((cx, cy + 60, 52), 4, rotation=45, fill=MAGENTA)
    glow_draw(img, crown, GOLD)
    save(img, "VIP")


def double_cash():
    img = base(GOLD)
    glow_draw(img, lambda d, c: coin(d, S / 2 - 150, S / 2 + 10, 190), GOLD, strength=1)
    text(img, "x2", 260, S / 2 - 150, IVORY, dx=170)
    save(img, "DoubleCash")


def lucky():
    img = base(GREEN)
    def bell(d, c):
        cx, cy = S / 2, S / 2 + 30
        d.pieslice((cx - 190, cy - 270, cx + 190, cy + 110), 180, 360, fill=c)
        d.polygon([(cx - 190, cy - 80), (cx + 190, cy - 80), (cx + 260, cy + 170), (cx - 260, cy + 170)], fill=c)
        d.rounded_rectangle((cx - 290, cy + 150, cx + 290, cy + 200), radius=24, fill=c)
        d.ellipse((cx - 55, cy + 190, cx + 55, cy + 300), fill=IVORY)
        d.ellipse((cx - 30, cy - 330, cx + 30, cy - 270), fill=c)
    glow_draw(img, bell, GOLD)
    def clover(d, c):
        cx, cy = S / 2 + 230, S / 2 - 210
        for a in range(4):
            ang = a * math.pi / 2 + math.pi / 4
            x, y = cx + math.cos(ang) * 48, cy + math.sin(ang) * 48
            d.ellipse((x - 50, y - 50, x + 50, y + 50), fill=c)
    glow_draw(img, clover, GREEN, blur=16)
    save(img, "LuckyBellhop")


def starter():
    img = base(MAGENTA)
    def box(d, c):
        cx, cy = S / 2, S / 2 + 70
        d.rounded_rectangle((cx - 260, cy - 170, cx + 260, cy + 230), radius=30, fill=(90, 30, 80))
        d.rounded_rectangle((cx - 290, cy - 250, cx + 290, cy - 150), radius=24, fill=c)
        d.rectangle((cx - 40, cy - 250, cx + 40, cy + 230), fill=GOLD)
        d.ellipse((cx - 170, cy - 380, cx - 10, cy - 250), outline=GOLD, width=34)
        d.ellipse((cx + 10, cy - 380, cx + 170, cy - 250), outline=GOLD, width=34)
    glow_draw(img, box, MAGENTA)
    save(img, "StarterPack")


if __name__ == "__main__":
    for tier in (1, 2, 3):
        extra_life(tier)
    curse()
    bless()
    golden()
    cash("CashSmall", 1)
    cash("CashMedium", 2)
    cash("CashLarge", 3)
    vip()
    double_cash()
    lucky()
    starter()
