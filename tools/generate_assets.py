#!/usr/bin/env python3
"""Generates FarmSim's sprite pack.

Every image the prototype uses is produced by this script. Nothing is
downloaded, so there is no third-party licence to track and every sprite can be
regenerated and audited (see ASSET_SOURCES.md).

The art is deliberately plain. Readability matters here - a player has to tell
at a glance whether a tile is dry, stressed or infested - and visual polish does
not.

Usage, from the project root:

    python tools/generate_assets.py
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

TILE = 64
ICON = 40
PLAYER_W, PLAYER_H = 40, 52

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")

# ------------------------------------------------------------------ palette --

GRASS_DARK = (58, 96, 48)
GRASS = (74, 118, 60)
GRASS_LIGHT = (90, 138, 72)

SOIL_DARK = (76, 52, 32)
SOIL = (99, 69, 42)
SOIL_LIGHT = (120, 87, 55)

TILLED_DARK = (86, 60, 36)
TILLED = (112, 80, 48)
TILLED_LIGHT = (134, 99, 62)

STONE_DARK = (92, 92, 96)
STONE = (124, 124, 128)
STONE_LIGHT = (152, 152, 156)
WATER = (62, 132, 190)
WATER_LIGHT = (104, 172, 220)

WOOD_DARK = (96, 70, 44)
WOOD = (132, 98, 62)

LEAF_DARK = (46, 108, 44)
LEAF = (72, 148, 62)
LEAF_LIGHT = (108, 182, 86)
COB = (222, 184, 74)
COB_DARK = (188, 148, 52)
POD = (128, 176, 72)
FLOWER = (240, 238, 224)

SKIN = (214, 168, 124)
HAT = (198, 168, 96)
HAT_DARK = (168, 138, 74)
TROUSERS = (68, 74, 96)
BOOT = (58, 44, 36)
P1_SHIRT = (226, 177, 60)
P1_SHIRT_DARK = (188, 142, 40)
P2_SHIRT = (95, 168, 211)
P2_SHIRT_DARK = (66, 132, 176)

WARN = (224, 166, 60)
BAD = (208, 90, 74)
PEST = (122, 78, 156)
PEST_DARK = (92, 56, 122)
DROUGHT = (226, 152, 62)
GOOD = (111, 191, 94)


def new_tile() -> Image.Image:
    return Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))


def save(image: Image.Image, *path_parts: str) -> str:
    path = os.path.join(ASSETS, *path_parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path)
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def speckle(draw: ImageDraw.ImageDraw, colour, points) -> None:
    for x, y in points:
        draw.rectangle([x, y, x + 3, y + 3], fill=colour)


# ------------------------------------------------------------- environment --

def make_grass() -> Image.Image:
    image = new_tile()
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, TILE, TILE], fill=GRASS)
    speckle(draw, GRASS_DARK, [(6, 10), (26, 4), (48, 16), (14, 38), (40, 46), (56, 34), (30, 56)])
    speckle(draw, GRASS_LIGHT, [(18, 20), (38, 12), (8, 50), (52, 52), (44, 28), (24, 32)])
    return image


def make_soil() -> Image.Image:
    image = new_tile()
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, TILE, TILE], fill=SOIL)
    speckle(draw, SOIL_DARK, [(8, 12), (30, 8), (50, 22), (16, 40), (42, 48), (58, 38)])
    speckle(draw, SOIL_LIGHT, [(20, 24), (40, 16), (10, 52), (54, 54)])
    return image


def make_tilled() -> Image.Image:
    image = new_tile()
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, TILE, TILE], fill=TILLED)
    # Furrows: the visual difference between "soil" and "ready to sow".
    # Kept light so the tile still reads as loose earth rather than planking.
    for y in range(9, TILE - 4, 14):
        draw.rectangle([5, y, TILE - 6, y + 1], fill=TILLED_DARK)
        draw.rectangle([5, y + 2, TILE - 6, y + 2], fill=TILLED_LIGHT)
    speckle(draw, SOIL_DARK, [(12, 4), (44, 18), (24, 32), (52, 46), (8, 54)])
    speckle(draw, TILLED_LIGHT, [(34, 6), (18, 22), (48, 34), (28, 50)])
    return image


def make_tile_border() -> Image.Image:
    """A one-pixel grid line so individual tiles are distinguishable."""
    image = new_tile()
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, TILE - 1, TILE - 1], outline=(24, 20, 12, 120))
    return image


def make_well() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    # stone rim
    draw.ellipse([6, 22, 58, 56], fill=STONE_DARK)
    draw.ellipse([9, 24, 55, 52], fill=STONE)
    draw.ellipse([14, 28, 50, 48], fill=WATER)
    draw.ellipse([19, 31, 45, 42], fill=WATER_LIGHT)
    # posts and roof
    draw.rectangle([12, 4, 17, 30], fill=WOOD_DARK)
    draw.rectangle([47, 4, 52, 30], fill=WOOD_DARK)
    draw.polygon([(4, 12), (32, 0), (60, 12), (32, 6)], fill=WOOD)
    draw.polygon([(4, 12), (32, 0), (60, 12)], outline=WOOD_DARK)
    speckle(draw, STONE_LIGHT, [(11, 44), (49, 44), (30, 52)])
    return image


WOOD_LIGHT = (170, 130, 86)
SHADOW = (0, 0, 0, 70)


def make_fence(horizontal: bool) -> Image.Image:
    """One length of rail, no posts. The rails are centred on pixel 32 so a
    horizontal and a vertical length meet exactly at a shared post. Posts are a
    separate sprite (make_fence_post) that the farm places at even spacing, so
    every corner falls on a post instead of wherever the tiling happens to end."""
    image = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    if horizontal:
        draw.rectangle([0, 39, TILE, 40], fill=SHADOW)          # shadow on the grass
        for top in (23, 31):
            draw.rectangle([0, top, TILE, top + 3], fill=WOOD)
            draw.line([0, top, TILE, top], fill=WOOD_LIGHT)      # sunlit edge
            draw.line([0, top + 3, TILE, top + 3], fill=WOOD_DARK)
        for x in (14, 47):                                       # grain marks
            draw.point((x, 25), fill=WOOD_DARK)
            draw.point((x + 9, 33), fill=WOOD_DARK)
    else:
        draw.rectangle([38, 0, 39, TILE], fill=SHADOW)
        for left in (27, 33):
            draw.rectangle([left, 0, left + 3, TILE], fill=WOOD)
            draw.line([left, 0, left, TILE], fill=WOOD_LIGHT)
            draw.line([left + 3, 0, left + 3, TILE], fill=WOOD_DARK)
        for y in (12, 44):
            draw.point((29, y), fill=WOOD_DARK)
            draw.point((35, y + 10), fill=WOOD_DARK)
    return image


def make_fence_post() -> Image.Image:
    """A fence post standing on pixel (32, 41): the same post at every point of
    the fence, corners included."""
    image = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse([28, 38, 42, 44], fill=SHADOW)                  # shadow on the grass
    draw.rectangle([28, 15, 35, 41], fill=WOOD)                  # post
    draw.line([28, 16, 28, 41], fill=WOOD_LIGHT)                 # lit side
    draw.rectangle([34, 16, 35, 41], fill=WOOD_DARK)             # shaded side
    draw.rectangle([29, 13, 34, 15], fill=WOOD_LIGHT)            # rounded top
    draw.point((28, 14), fill=WOOD)
    draw.point((35, 14), fill=WOOD_DARK)
    draw.line([28, 41, 35, 41], fill=WOOD_DARK)                  # foot
    draw.point((31, 22), fill=WOOD_DARK)                         # grain
    draw.point((32, 31), fill=WOOD_DARK)
    return image


# ------------------------------------------------------------------ crops ---

def make_maize(stage: int) -> Image.Image:
    """stage 1..4: sprout, young, tall, ripe."""
    image = new_tile()
    draw = ImageDraw.Draw(image)
    base_y = 56
    if stage == 1:
        draw.rectangle([30, 46, 33, base_y], fill=LEAF_DARK)
        draw.polygon([(30, 48), (20, 42), (30, 44)], fill=LEAF)
        draw.polygon([(33, 48), (43, 42), (33, 44)], fill=LEAF)
    elif stage == 2:
        draw.rectangle([30, 30, 33, base_y], fill=LEAF_DARK)
        draw.polygon([(30, 36), (14, 26), (30, 32)], fill=LEAF)
        draw.polygon([(33, 40), (49, 30), (33, 36)], fill=LEAF_LIGHT)
        draw.polygon([(30, 46), (16, 42), (30, 42)], fill=LEAF)
    elif stage == 3:
        draw.rectangle([30, 14, 33, base_y], fill=LEAF_DARK)
        draw.polygon([(30, 22), (12, 12), (30, 18)], fill=LEAF)
        draw.polygon([(33, 28), (52, 18), (33, 24)], fill=LEAF_LIGHT)
        draw.polygon([(30, 36), (12, 30), (30, 32)], fill=LEAF)
        draw.polygon([(33, 44), (52, 38), (33, 40)], fill=LEAF)
    else:
        draw.rectangle([30, 10, 33, base_y], fill=LEAF_DARK)
        draw.polygon([(30, 18), (10, 8), (30, 14)], fill=LEAF)
        draw.polygon([(33, 24), (54, 14), (33, 20)], fill=LEAF_LIGHT)
        draw.polygon([(30, 34), (10, 28), (30, 30)], fill=LEAF)
        draw.polygon([(33, 42), (54, 36), (33, 38)], fill=LEAF)
        # ripe cob
        draw.rounded_rectangle([34, 26, 44, 46], radius=4, fill=COB)
        draw.rounded_rectangle([34, 26, 39, 46], radius=4, fill=COB_DARK)
        # tassel
        draw.rectangle([29, 4, 34, 12], fill=COB_DARK)
    return image


def make_beans(stage: int) -> Image.Image:
    """stage 1..4: sprout, bush, flowering, podded."""
    image = new_tile()
    draw = ImageDraw.Draw(image)
    if stage == 1:
        draw.rectangle([31, 48, 34, 58], fill=LEAF_DARK)
        draw.ellipse([22, 42, 32, 50], fill=LEAF)
        draw.ellipse([33, 42, 43, 50], fill=LEAF_LIGHT)
    elif stage == 2:
        draw.rectangle([31, 36, 34, 58], fill=LEAF_DARK)
        draw.ellipse([16, 32, 32, 46], fill=LEAF)
        draw.ellipse([33, 30, 49, 44], fill=LEAF_LIGHT)
        draw.ellipse([22, 44, 42, 54], fill=LEAF)
    elif stage == 3:
        draw.rectangle([31, 28, 34, 58], fill=LEAF_DARK)
        draw.ellipse([12, 24, 32, 42], fill=LEAF)
        draw.ellipse([33, 22, 53, 40], fill=LEAF_LIGHT)
        draw.ellipse([18, 40, 46, 54], fill=LEAF)
        speckle(draw, FLOWER, [(20, 28), (40, 26), (30, 44), (46, 34)])
    else:
        draw.rectangle([31, 24, 34, 58], fill=LEAF_DARK)
        draw.ellipse([10, 20, 32, 40], fill=LEAF)
        draw.ellipse([33, 18, 55, 38], fill=LEAF_LIGHT)
        draw.ellipse([16, 38, 48, 54], fill=LEAF)
        for x, y in ((18, 34), (38, 30), (28, 46)):
            draw.rounded_rectangle([x, y, x + 14, y + 6], radius=3, fill=POD)
            draw.rounded_rectangle([x + 1, y + 1, x + 13, y + 3], radius=2, fill=LEAF_LIGHT)
    return image


def make_stubble() -> Image.Image:
    """What is left on a tile after it has been harvested."""
    image = new_tile()
    draw = ImageDraw.Draw(image)
    for x in (20, 30, 40):
        draw.rectangle([x, 48, x + 3, 58], fill=(150, 132, 84))
    return image


# ------------------------------------------------------------- indicators ---

def make_pest_marker() -> Image.Image:
    image = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse([8, 10, 32, 30], fill=PEST)
    draw.ellipse([8, 10, 32, 20], fill=PEST_DARK)
    for x in (12, 20, 28):
        draw.rectangle([x, 6, x + 2, 12], fill=PEST_DARK)
        draw.rectangle([x, 28, x + 2, 34], fill=PEST_DARK)
    draw.rectangle([15, 16, 17, 18], fill=(255, 255, 255))
    draw.rectangle([23, 16, 25, 18], fill=(255, 255, 255))
    return image


def make_warning_marker(colour) -> Image.Image:
    image = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.polygon([(20, 4), (36, 32), (4, 32)], fill=colour)
    draw.polygon([(20, 9), (31, 29), (9, 29)], outline=(40, 30, 12))
    draw.rectangle([18, 14, 22, 23], fill=(40, 30, 12))
    draw.rectangle([18, 25, 22, 28], fill=(40, 30, 12))
    return image


def make_drop() -> Image.Image:
    image = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.polygon([(20, 4), (32, 24), (8, 24)], fill=WATER)
    draw.ellipse([8, 16, 32, 36], fill=WATER)
    draw.ellipse([14, 22, 22, 30], fill=WATER_LIGHT)
    return image


def make_sun() -> Image.Image:
    image = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse([11, 11, 29, 29], fill=DROUGHT)
    for x, y in ((19, 2), (19, 32), (2, 19), (32, 19)):
        draw.rectangle([x, y, x + 3, y + 6] if x == 19 else [x, y, x + 6, y + 3], fill=DROUGHT)
    return image


# ---------------------------------------------------------------- players ---

def make_player(shirt, shirt_dark) -> Image.Image:
    image = Image.new("RGBA", (PLAYER_W, PLAYER_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    # hat
    draw.ellipse([4, 4, 36, 18], fill=HAT)
    draw.ellipse([11, 0, 29, 13], fill=HAT_DARK)
    # head
    draw.rounded_rectangle([13, 12, 27, 24], radius=4, fill=SKIN)
    draw.rectangle([16, 17, 18, 19], fill=(48, 38, 30))
    draw.rectangle([22, 17, 24, 19], fill=(48, 38, 30))
    # body
    draw.rounded_rectangle([10, 24, 30, 40], radius=4, fill=shirt)
    draw.rectangle([10, 34, 30, 40], fill=shirt_dark)
    # arms
    draw.rounded_rectangle([4, 26, 11, 36], radius=3, fill=shirt)
    draw.rounded_rectangle([29, 26, 36, 36], radius=3, fill=shirt)
    draw.rectangle([4, 34, 10, 38], fill=SKIN)
    draw.rectangle([30, 34, 36, 38], fill=SKIN)
    # legs
    draw.rectangle([13, 40, 19, 48], fill=TROUSERS)
    draw.rectangle([21, 40, 27, 48], fill=TROUSERS)
    draw.rectangle([12, 48, 20, 52], fill=BOOT)
    draw.rectangle([20, 48, 28, 52], fill=BOOT)
    return image


# ------------------------------------------------------------------ tools ---

def _icon() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def make_hoe_icon() -> Image.Image:
    image, draw = _icon()
    draw.line([(9, 33), (28, 8)], fill=WOOD, width=4)
    draw.rectangle([24, 4, 36, 9], fill=STONE)
    draw.rectangle([31, 4, 36, 15], fill=STONE_DARK)
    return image


def make_seed_icon() -> Image.Image:
    image, draw = _icon()
    draw.rounded_rectangle([10, 14, 30, 34], radius=4, fill=WOOD)
    draw.rectangle([10, 14, 30, 19], fill=WOOD_DARK)
    for x, y in ((14, 22), (20, 26), (25, 21), (18, 30)):
        draw.ellipse([x, y, x + 5, y + 5], fill=COB)
    return image


def make_water_icon() -> Image.Image:
    image, draw = _icon()
    draw.rounded_rectangle([8, 16, 27, 33], radius=3, fill=STONE)
    draw.rectangle([8, 16, 27, 21], fill=STONE_DARK)
    draw.polygon([(27, 20), (36, 12), (37, 16), (28, 25)], fill=STONE_DARK)
    draw.rectangle([13, 10, 22, 14], fill=STONE_DARK)
    draw.ellipse([31, 26, 37, 33], fill=WATER)
    return image


def make_inspect_icon() -> Image.Image:
    image, draw = _icon()
    draw.ellipse([6, 6, 26, 26], outline=STONE_LIGHT, width=4)
    draw.ellipse([10, 10, 22, 22], fill=(150, 200, 225, 140))
    draw.line([(24, 24), (34, 34)], fill=WOOD, width=5)
    return image


def make_treat_icon() -> Image.Image:
    image, draw = _icon()
    draw.rounded_rectangle([12, 16, 26, 35], radius=3, fill=GOOD)
    draw.rectangle([16, 10, 22, 17], fill=STONE)
    draw.polygon([(22, 12), (33, 6), (34, 10), (23, 16)], fill=STONE_DARK)
    speckle(draw, WATER_LIGHT, [(30, 14), (34, 18)])
    return image


def make_harvest_icon() -> Image.Image:
    image, draw = _icon()
    draw.line([(10, 34), (20, 22)], fill=WOOD, width=5)
    draw.arc([12, 4, 36, 28], start=100, end=340, fill=STONE_LIGHT, width=5)
    draw.arc([14, 6, 34, 26], start=100, end=340, fill=STONE, width=2)
    return image


# ------------------------------------------------------------------- main ---

# ------------------------------------------------------------------- decor ---
# Trees, bushes, flowers, rocks, the garden toolbox and ground detail. None of
# these do anything in the game: they are placed by hand in scenes/farm/farm.tscn
# under the Decor* layers (see LEVEL_DESIGN.md), so the level can be designed in
# the editor.

import math
import random
from PIL import ImageFilter

LEAF_DEEP = (32, 76, 36)
LEAF_SUN = (150, 206, 104)
TRUNK = (92, 64, 40)
TRUNK_DARK = (66, 46, 30)
CHAR = (54, 57, 62)
CHAR_DARK = (36, 38, 42)
CHAR_LIGHT = (78, 82, 88)
SLAT = (150, 120, 92)
SLAT_LIGHT = (176, 146, 114)
SLAT_DARK = (112, 86, 64)
PATH = (139, 112, 76)
PATH_LIGHT = (160, 132, 92)
PATH_DARK = (118, 92, 60)

def blob(d, cx, cy, r, fill):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

def canopy(img, cx, cy, rad, seed):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img)
    lumps = [(cx + rnd.randint(-rad // 2, rad // 2), cy + rnd.randint(-rad // 2, rad // 3), rnd.randint(rad // 2, rad * 3 // 4)) for _ in range(7)]
    lumps.append((cx, cy, rad * 3 // 4))
    for x, y, r in lumps: blob(d, x, y + 2, r + 2, LEAF_DEEP)           # outline / underside
    for x, y, r in lumps: blob(d, x, y, r, LEAF_DARK)
    for x, y, r in lumps: blob(d, x - r // 4, y - r // 4, r * 2 // 3, LEAF)
    for x, y, r in lumps: blob(d, x - r // 3, y - r // 3, r // 3, LEAF_LIGHT)
    for _ in range(rad):                                                 # leaf speckle
        a = rnd.random() * math.tau; rr = rnd.random() * rad * 0.8
        px, py = int(cx + math.cos(a) * rr), int(cy + math.sin(a) * rr * 0.8)
        if img.getpixel((px, py))[3]:
            d.point((px, py), fill=rnd.choice([LEAF_SUN, LEAF_DARK, LEAF_LIGHT]))

def tree(seed, w=96, h=112, rad=36, fruit=None):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    cx = w // 2
    d.ellipse([cx - 30, h - 16, cx + 34, h - 2], fill=SHADOW)
    d.rectangle([cx - 5, h - 46, cx + 5, h - 8], fill=TRUNK)
    d.rectangle([cx + 2, h - 46, cx + 5, h - 8], fill=TRUNK_DARK)
    d.line([cx - 5, h - 46, cx - 5, h - 8], fill=WOOD_LIGHT)
    d.polygon([(cx - 5, h - 9), (cx - 10, h - 5), (cx + 10, h - 5), (cx + 5, h - 9)], fill=TRUNK)  # roots
    canopy(img, cx, rad + 6, rad, seed)
    if fruit:
        rnd = random.Random(seed + 1)
        for _ in range(9):
            x, y = cx + rnd.randint(-rad + 8, rad - 8), 6 + rad + rnd.randint(-rad + 10, rad - 12)
            if img.getpixel((x, y))[3]:
                d.rectangle([x, y, x + 2, y + 2], fill=fruit); d.point((x, y), fill=(255, 240, 200))
    return img

def pine(seed):
    img = Image.new("RGBA", (72, 112), (0, 0, 0, 0)); d = ImageDraw.Draw(img); cx = 36
    d.ellipse([cx - 24, 98, cx + 26, 110], fill=SHADOW)
    d.rectangle([cx - 4, 84, cx + 4, 104], fill=TRUNK); d.rectangle([cx + 1, 84, cx + 4, 104], fill=TRUNK_DARK)
    for i, (top, half, bottom) in enumerate([(8, 14, 38), (24, 22, 62), (42, 30, 90)]):
        d.polygon([(cx, top), (cx - half, bottom), (cx + half, bottom)], fill=LEAF_DEEP)
        d.polygon([(cx, top + 2), (cx - half + 3, bottom - 2), (cx + half - 3, bottom - 2)], fill=LEAF_DARK)
        d.polygon([(cx, top + 2), (cx - half + 3, bottom - 2), (cx, bottom - 2)], fill=(58, 126, 54))
        d.line([(cx - half + 6, bottom - 4), (cx + half - 6, bottom - 4)], fill=LEAF_DEEP)
    return img

def bush(seed, w=52, h=38, berries=None):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.ellipse([4, h - 12, w - 2, h - 2], fill=SHADOW)
    canopy(img, w // 2, h // 2 + 1, min(w, h) // 2 - 4, seed)
    if berries:
        rnd = random.Random(seed)
        for _ in range(6):
            x, y = rnd.randint(10, w - 12), rnd.randint(8, h - 12)
            if img.getpixel((x, y))[3]: d.rectangle([x, y, x + 1, y + 1], fill=berries)
    return img

FLOWERS = [((236, 120, 160), (255, 190, 210)), ((246, 206, 72), (255, 236, 150)), ((240, 238, 224), (255, 255, 255)),
           ((168, 120, 214), (210, 176, 240)), ((232, 112, 72), (255, 170, 120))]

def flowers(seed, w=44, h=30, palette=None, n=9):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for _ in range(14):                                                  # leafy base
        x, y = rnd.randint(4, w - 6), rnd.randint(h // 3, h - 5)
        blob(d, x, y, rnd.randint(3, 5), rnd.choice([LEAF_DARK, LEAF, (58, 126, 54)]))
    for _ in range(n):
        petal, light = palette or rnd.choice(FLOWERS)
        x, y = rnd.randint(4, w - 5), rnd.randint(3, h - 9)
        d.line([x, y + 2, x, y + 6], fill=LEAF_DARK)
        d.point([(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], fill=petal)
        d.point((x - 1, y - 1), fill=light)
        d.point((x, y), fill=(250, 214, 90) if petal != FLOWERS[1][0] else (190, 110, 40))
    return img

def tuft(seed, w=18, h=16):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for i in range(6):
        x = 3 + i * 2 + rnd.randint(0, 1); top = rnd.randint(1, 7)
        d.line([x, h - 2, x + rnd.choice([-2, -1, 1, 2]), top], fill=rnd.choice([LEAF, LEAF_DARK, LEAF_LIGHT]))
    return img

def rock(seed):
    img = Image.new("RGBA", (22, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.ellipse([2, 9, 21, 15], fill=SHADOW)
    d.polygon([(3, 12), (5, 5), (11, 2), (17, 4), (19, 11)], fill=STONE)
    d.polygon([(5, 6), (11, 3), (15, 4), (9, 7)], fill=STONE_LIGHT)
    d.line([(4, 12), (19, 11)], fill=STONE_DARK)
    return img

def toolbox():
    """The reference deck box in the game's 3/4 view: charcoal frame, wood-look
    slats, lid propped open behind, garden supplies inside."""
    W, H = 96, 76
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x0, x1 = 6, 89
    d.ellipse([2, H - 12, W - 2, H - 1], fill=SHADOW)
    # open lid, leaning back: ribbed underside
    d.polygon([(x0 + 2, 30), (x0 + 6, 4), (x1 - 6, 4), (x1 - 2, 30)], fill=CHAR_DARK)
    d.polygon([(x0 + 4, 28), (x0 + 8, 7), (x1 - 8, 7), (x1 - 4, 28)], fill=CHAR)
    for i in range(1, 9):
        x = x0 + 8 + i * (x1 - x0 - 16) // 9
        d.line([(x - 2, 27), (x, 8)], fill=CHAR_DARK)
    d.line([(x0 + 8, 17), (x1 - 8, 17)], fill=CHAR_LIGHT)
    d.line([(x0 + 6, 5), (x1 - 6, 5)], fill=CHAR_LIGHT)
    # inside of the box (seen from above)
    d.rectangle([x0, 28, x1, 38], fill=CHAR_DARK)
    d.rectangle([x0 + 3, 29, x1 - 3, 37], fill=(30, 26, 22))
    # contents: compost bags, twine, watering can, hose, crate
    d.rectangle([x0 + 4, 30, x0 + 22, 37], fill=(58, 140, 60)); d.line([(x0 + 4, 30), (x0 + 22, 30)], fill=(120, 196, 104))
    d.rectangle([x0 + 9, 32, x0 + 15, 35], fill=(232, 228, 210))
    for cx in (x0 + 28, x0 + 35):
        blob(d, cx, 33, 3, (198, 168, 112)); d.point((cx - 1, 32), fill=(232, 204, 150)); d.line([(cx - 2, 34), (cx + 2, 32)], fill=(150, 120, 76))
    d.rectangle([x0 + 41, 30, x0 + 50, 37], fill=(168, 176, 182)); d.rectangle([x0 + 41, 30, x0 + 50, 31], fill=(214, 222, 228))
    d.line([(x0 + 50, 33), (x0 + 55, 29)], fill=(168, 176, 182)); d.arc([x0 + 42, 26, x0 + 49, 33], 180, 360, fill=(140, 148, 154))
    d.ellipse([x0 + 58, 29, x0 + 76, 38], fill=(222, 178, 40)); d.ellipse([x0 + 62, 31, x0 + 72, 36], fill=(30, 26, 22))
    d.arc([x0 + 58, 29, x0 + 76, 38], 200, 330, fill=(250, 214, 90))
    d.line([(x1 - 9, 29), (x1 - 4, 34)], fill=(72, 160, 70)); d.line([(x1 - 8, 29), (x1 - 3, 34)], fill=(72, 160, 70))
    # front face: charcoal frame + wood slats
    d.rectangle([x0, 38, x1, 66], fill=CHAR)
    d.line([(x0, 38), (x1, 38)], fill=CHAR_LIGHT)
    sx0, sx1 = x0 + 4, x1 - 4
    n = 12; sw = (sx1 - sx0) / n
    for i in range(n):
        a = int(sx0 + i * sw) + 1; b = int(sx0 + (i + 1) * sw) - 1
        d.rectangle([a, 41, b, 63], fill=SLAT)
        d.line([(a, 41), (a, 63)], fill=SLAT_LIGHT)
        if (i * 7) % 3 == 0: d.point((a + 2, 47 + i % 4 * 3), fill=SLAT_DARK)
        d.point((a + 1, 56 - i % 3 * 4), fill=SLAT_DARK)
    d.rectangle([x0 + 36, 40, x0 + 47, 42], fill=CHAR_DARK)        # handle / latch
    d.rectangle([x1 - 3, 38, x1, 66], fill=CHAR_DARK)               # shaded side edge
    # plinth
    d.rectangle([x0 - 1, 66, x1 + 1, 71], fill=CHAR_DARK)
    for x in range(x0 + 6, x1 - 2, 14): d.rectangle([x, 67, x + 7, 70], fill=(28, 30, 34))
    return img

def ground_variation() -> Image.Image:
    """Soft light and dark patches over the tiled grass, so the field of grass
    does not read as one repeated tile. One 1280x720 overlay, drawn under
    everything else on the farm."""
    W, H = 1280, 720
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    rnd = random.Random(3)
    for _ in range(70):
        x, y = rnd.randint(-40, W), rnd.randint(150, H)
        rx, ry = rnd.randint(30, 90), rnd.randint(14, 34)
        c = (36, 70, 30, 34) if rnd.random() < 0.6 else (140, 190, 100, 26)
        d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=c)
    return img.filter(ImageFilter.GaussianBlur(10))


def dirt_path() -> Image.Image:
    """A short worn footpath, 112x36, that fades out at both ends. Rotate,
    flip, stretch or chain several in the editor."""
    W, H = 112, 36
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    rnd = random.Random(12)
    for x in range(8, W - 8, 2):
        fade = min(1.0, min(x - 8, W - 8 - x) / 18.0)
        w = int((9 + rnd.randint(-1, 1)) * (0.55 + 0.45 * fade))
        cy = H // 2 + int(2 * math.sin(x / 17.0))
        d.ellipse([x - w, cy - w * 0.55, x + w, cy + w * 0.55], fill=PATH)
    for _ in range(40):
        x, y = rnd.randint(14, W - 14), rnd.randint(H // 2 - 4, H // 2 + 4)
        if img.getpixel((x, y))[3]:
            d.point((x, y), fill=rnd.choice([PATH_LIGHT, PATH_DARK]))
    return img


def write_decor() -> list[str]:
    written = []
    written.append(save(tree(11), "decor", "tree_round.png"))
    written.append(save(tree(37), "decor", "tree_round_2.png"))
    written.append(save(tree(23, fruit=(226, 92, 64)), "decor", "tree_fruit.png"))
    written.append(save(pine(5), "decor", "tree_pine.png"))
    written.append(save(bush(3), "decor", "bush.png"))
    written.append(save(bush(8, berries=(214, 70, 90)), "decor", "bush_berries.png"))
    written.append(save(bush(19, 40, 30), "decor", "bush_small.png"))
    for name, pal in zip(["pink", "yellow", "white", "purple", "orange"], FLOWERS):
        written.append(save(flowers(40 + FLOWERS.index(pal), palette=pal), "decor", f"flowers_{name}.png"))
    written.append(save(flowers(99, 64, 32, None, 16), "decor", "flowers_mixed.png"))
    for i in range(3):
        written.append(save(tuft(60 + i), "decor", f"grass_tuft_{i + 1}.png"))
    written.append(save(rock(1), "decor", "rock.png"))
    written.append(save(dirt_path(), "decor", "dirt_path.png"))
    written.append(save(toolbox(), "decor", "garden_toolbox.png"))
    written.append(save(ground_variation(), "decor", "ground_variation.png"))
    return written


# -------------------------------------------------------------- app icon ---
# The launcher icon, drawn at 48x48 in the same pixel-art style and scaled up
# with hard pixel edges. Android "adaptive" icons come as two layers: a
# background (crop rows under a sky) and a foreground (the Player 1 farmer with
# a ripe maize plant), which the phone masks to a circle, squircle or square.
# The foreground stays inside the middle 2/3, the part every mask keeps.

ICON_PX = 48


def _icon_background() -> Image.Image:
    img = Image.new("RGBA", (ICON_PX, ICON_PX), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    for y in range(ICON_PX):                                     # warm evening sky
        t = y / 22.0
        top, bottom = (246, 196, 92), (250, 226, 150)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * min(t, 1.0)) for i in range(3))
        d.line([(0, y), (ICON_PX, y)], fill=c + (255,))
    d.ellipse([30, 6, 42, 18], fill=(255, 238, 180, 255))       # low sun
    d.polygon([(0, 22), (14, 17), (28, 20), (40, 16), (48, 19), (48, 26), (0, 26)], fill=(96, 150, 72, 255))
    d.rectangle([0, 24, ICON_PX, ICON_PX], fill=GRASS + (255,))
    for i, y in enumerate(range(27, ICON_PX, 5)):               # tilled crop rows
        d.rectangle([0, y, ICON_PX, y + 2], fill=TILLED + (255,))
        d.line([(0, y), (ICON_PX, y)], fill=TILLED_LIGHT + (255,))
        for x in range(2 + (i % 2) * 3, ICON_PX, 6):
            d.point((x, y - 1), fill=LEAF + (255,))
            d.point((x + 1, y - 2), fill=LEAF_LIGHT + (255,))
    return img


def _icon_foreground() -> Image.Image:
    img = Image.new("RGBA", (ICON_PX, ICON_PX), (0, 0, 0, 0))
    farmer = Image.open(os.path.join(ASSETS, "characters", "player_1.png")).convert("RGBA")
    bbox = farmer.getbbox()
    farmer = farmer.crop(bbox)
    scale = 24.0 / farmer.height
    farmer = farmer.resize((max(1, round(farmer.width * scale)), 24), Image.NEAREST)
    d = ImageDraw.Draw(img)
    d.ellipse([12, 37, 30, 41], fill=(0, 0, 0, 70))             # shadow
    img.alpha_composite(farmer, (21 - farmer.width // 2, 15))
    # ripe maize plant on the right
    d.rectangle([33, 16, 34, 39], fill=LEAF_DARK)
    d.polygon([(33, 22), (27, 18), (33, 20)], fill=LEAF)
    d.polygon([(34, 27), (40, 22), (34, 25)], fill=LEAF_LIGHT)
    d.polygon([(33, 32), (27, 29), (33, 30)], fill=LEAF)
    d.rounded_rectangle([35, 24, 38, 33], radius=1, fill=COB)
    d.rectangle([35, 24, 36, 33], fill=COB_DARK)
    d.line([(33, 15), (35, 12)], fill=(222, 196, 120))         # tassel
    d.line([(34, 15), (32, 12)], fill=(222, 196, 120))
    return img


def _upscale(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.NEAREST)


def write_app_icon() -> list[str]:
    written = []
    background = _icon_background()
    foreground = _icon_foreground()
    # Adaptive layers: content is shrunk to the middle 2/3 so no mask cuts it.
    fg = Image.new("RGBA", (ICON_PX * 3 // 2, ICON_PX * 3 // 2), (0, 0, 0, 0))
    fg.alpha_composite(foreground, (ICON_PX // 4, ICON_PX // 4))
    written.append(save(_upscale(fg, 432), "icons", "adaptive_foreground.png"))
    bg = background.resize((ICON_PX * 3 // 2, ICON_PX * 3 // 2), Image.NEAREST)
    written.append(save(_upscale(bg, 432), "icons", "adaptive_background.png"))
    mono = Image.new("RGBA", fg.size, (0, 0, 0, 0))
    mono.paste((255, 255, 255, 255), (0, 0), fg.split()[3].point(lambda a: 255 if a > 100 else 0))
    written.append(save(_upscale(mono, 432), "icons", "adaptive_monochrome.png"))
    # Flat icon: both layers in a rounded square, for older phones and the PC.
    flat = background.copy()
    flat.alpha_composite(foreground)
    mask = Image.new("L", (ICON_PX * 8, ICON_PX * 8), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, ICON_PX * 8 - 1, ICON_PX * 8 - 1], radius=ICON_PX * 2, fill=255)
    big = _upscale(flat, ICON_PX * 8)
    big.putalpha(mask)
    written.append(save(big.resize((512, 512), Image.NEAREST), "icons", "app_icon.png"))
    written.append(save(big.resize((192, 192), Image.LANCZOS), "icons", "app_icon_192.png"))
    return written


def main() -> int:
    written: list[str] = []

    written.append(save(make_grass(), "environment", "grass.png"))
    written.append(save(make_soil(), "environment", "soil.png"))
    written.append(save(make_tilled(), "environment", "tilled.png"))
    written.append(save(make_tile_border(), "environment", "tile_border.png"))
    written.append(save(make_well(), "environment", "well.png"))
    written.append(save(make_fence(True), "environment", "fence_horizontal.png"))
    written.append(save(make_fence(False), "environment", "fence_vertical.png"))
    written.append(save(make_fence_post(), "environment", "fence_post.png"))

    for stage in range(1, 5):
        written.append(save(make_maize(stage), "crops", f"maize_{stage}.png"))
        written.append(save(make_beans(stage), "crops", f"beans_{stage}.png"))
    written.append(save(make_stubble(), "crops", "stubble.png"))

    written.append(save(make_player(P1_SHIRT, P1_SHIRT_DARK), "characters", "player_1.png"))
    written.append(save(make_player(P2_SHIRT, P2_SHIRT_DARK), "characters", "player_2.png"))

    written.append(save(make_hoe_icon(), "tools", "hoe.png"))
    written.append(save(make_seed_icon(), "tools", "seed.png"))
    written.append(save(make_water_icon(), "tools", "water.png"))
    written.append(save(make_inspect_icon(), "tools", "inspect.png"))
    written.append(save(make_treat_icon(), "tools", "treat.png"))
    written.append(save(make_harvest_icon(), "tools", "harvest.png"))

    written.append(save(make_pest_marker(), "effects", "pest.png"))
    written.append(save(make_warning_marker(WARN), "effects", "warning.png"))
    written.append(save(make_warning_marker(BAD), "effects", "alert.png"))
    written.append(save(make_drop(), "effects", "drop.png"))
    written.append(save(make_sun(), "effects", "drought.png"))

    written.extend(write_decor())
    written.extend(write_app_icon())

    for path in written:
        print("wrote", path)
    print(f"{len(written)} sprites generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
