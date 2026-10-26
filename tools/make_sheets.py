#!/usr/bin/env python3
"""Render placeholder card faces from cards.json into TTS custom-deck sheets.

Usage: python tools/make_sheets.py games/sample

Writes <game>/art/sheet_N.jpg (up to 10 x 7 cards each), <game>/art/back.jpg
and <game>/art.json, which tells the engine which sheet and slot each card
id uses. The art is deliberately plain: a coloured frame, name, cost, effects
and defense, so a template can ship without anyone else's artwork.
Replace the sheets with real art later and keep art.json as the index.
"""
import argparse
import colorsys
import hashlib
import json
import math
import re
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CARD_W, CARD_H = 400, 560
COLS, MAX_ROWS = 10, 7
PER_SHEET = COLS * MAX_ROWS - 1  # keep the last slot free, as TTS reserves it in some modes
FONT_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "C:/Windows/Fonts/arial.ttf",
]
NEUTRAL = (110, 110, 120)


def font(size):
    for path in FONT_PATHS:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def rules_colors(game):
    """Faction colours from rules.lua, e.g. forge = { label = "Forge", color = "#C8502D" }."""
    rules = game / "rules.lua"
    if not rules.exists():
        return {}
    found = re.findall(r'(\w+)\s*=\s*\{[^{}]*color\s*=\s*"#([0-9A-Fa-f]{6})"', rules.read_text(encoding="utf-8"))
    return {name: tuple(int(hexcode[i:i + 2], 16) for i in (0, 2, 4)) for name, hexcode in found}


COLORS = {}


def faction_color(name):
    if name in ("", "none"):
        return NEUTRAL
    if name in COLORS:
        return COLORS[name]
    hue = int(hashlib.md5(name.encode()).hexdigest()[:4], 16) / 0xFFFF
    r, g, b = colorsys.hsv_to_rgb(hue, 0.55, 0.75)
    return int(r * 255), int(g * 255), int(b * 255)


WORDS = {
    "draw": "Draw {n}",
    "opponent_discard": "Opponent discards {n}",
    "scrap_hand": "Scrap up to {n} from hand or discard",
    "scrap_row": "Scrap {n} from the market row",
    "destroy_base": "Destroy {n} base",
    "draw_discard": "Draw {n}, then discard {n}",
}


def one_effect(part):
    if part == "reminder":
        return "See text"
    key, _, value = part.partition(":")
    key, value = key.strip(), value.strip()
    if key == "custom":
        return "Special"
    if key in WORDS:
        return WORDS[key].format(n=value)
    sign = "" if value.startswith("-") else "+"
    return f"{sign}{value} {key.replace('_', ' ').title()}"


def effect_text(effects):
    parts = []
    for part in filter(None, (p.strip() for p in effects.split(";"))):
        faction, sep, rest = part.partition("=")
        prefix = f"({faction.strip().replace('_', ' ').title()}) " if sep else ""
        body = rest if sep else part
        parts.append(prefix + " or ".join(one_effect(o.strip()) for o in body.split("|")))
    return ", ".join(parts)


def draw_card(card):
    factions = card.get("faction", "none").split("/")
    color = faction_color(factions[0])
    img = Image.new("RGB", (CARD_W, CARD_H), (245, 242, 235))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, CARD_W - 1, CARD_H - 1], outline=color, width=14)
    d.rectangle([14, 14, CARD_W - 15, 96], fill=color)

    d.ellipse([24, 24, 88, 88], fill=(250, 214, 92), outline=(60, 50, 20), width=3)
    cost = str(card.get("cost", 0))
    d.text((56, 56), cost, font=font(34), fill=(40, 30, 10), anchor="mm")

    name_font = font(30 if len(card["name"]) <= 14 else 24)
    d.text((CARD_W / 2 + 34, 56), card["name"], font=name_font, fill="white", anchor="mm")

    names = " / ".join(f.replace("_", " ").title() for f in factions)
    subtitle = f"{names} · {card.get('type', 'unit').title()}"
    if card.get("faction") in (None, "", "none"):
        subtitle = card.get("type", "unit").title()
    d.text((CARD_W / 2, 122), subtitle, font=font(20), fill=(80, 80, 80), anchor="mm")

    # Art area placeholder
    d.rectangle([40, 145, CARD_W - 41, 300], fill=tuple(int(c * 0.35 + 255 * 0.65) for c in color))
    d.text((CARD_W / 2, 222), card["id"], font=font(18), fill=(120, 120, 120), anchor="mm")

    lines = []
    if card.get("effects"):
        lines.append(effect_text(card["effects"]))
    if card.get("ally_effects"):
        lines.append("Ally: " + effect_text(card["ally_effects"]))
    if card.get("scrap_effects"):
        lines.append("Scrap: " + effect_text(card["scrap_effects"]))
    if card.get("text"):
        lines.append(card["text"])
    y = 320
    body = font(21)
    for line in lines:
        for wrapped in textwrap.wrap(line, 26):
            d.text((CARD_W / 2, y), wrapped, font=body, fill=(30, 30, 30), anchor="mt")
            y += 28
        y += 8

    if card.get("defense") is not None:
        d.rectangle([CARD_W - 104, CARD_H - 92, CARD_W - 28, CARD_H - 28], fill=(60, 60, 70))
        d.text((CARD_W - 66, CARD_H - 60), str(card["defense"]), font=font(32), fill="white", anchor="mm")
    d.text((34, CARD_H - 40), "placeholder", font=font(14), fill=(160, 160, 160), anchor="lm")
    return img


def draw_back(title):
    img = Image.new("RGB", (CARD_W, CARD_H), (34, 38, 52))
    d = ImageDraw.Draw(img)
    d.rectangle([14, 14, CARD_W - 15, CARD_H - 15], outline=(200, 170, 90), width=6)
    for i, line in enumerate(textwrap.wrap(title, 12)):
        d.text((CARD_W / 2, CARD_H / 2 - 20 + i * 44), line, font=font(38), fill=(220, 200, 140), anchor="mm")
    return img


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("game", type=Path, help="game folder containing cards.json")
    parser.add_argument("--title", default=None, help="text on the card back (default: folder name)")
    args = parser.parse_args()

    COLORS.update(rules_colors(args.game))
    cards = json.loads((args.game / "cards.json").read_text(encoding="utf-8"))
    art_dir = args.game / "art"
    art_dir.mkdir(exist_ok=True)
    for old in art_dir.glob("sheet_*.jpg"):
        old.unlink()

    manifest = {"back": "art/back.jpg", "sheets": [], "cards": {}}
    for sheet_no, start in enumerate(range(0, len(cards), PER_SHEET), start=1):
        chunk = cards[start:start + PER_SHEET]
        rows = max(2, math.ceil(len(chunk) / COLS))
        sheet = Image.new("RGB", (CARD_W * COLS, CARD_H * rows), (0, 0, 0))
        for i, card in enumerate(chunk):
            sheet.paste(draw_card(card), ((i % COLS) * CARD_W, (i // COLS) * CARD_H))
            manifest["cards"][card["id"]] = {"sheet": sheet_no, "index": i}
        name = f"art/sheet_{sheet_no}.jpg"
        sheet.save(args.game / name, quality=88)
        manifest["sheets"].append({"file": name, "numWidth": COLS, "numHeight": rows, "count": len(chunk)})

    title = args.title or args.game.name.replace("_", " ").title()
    draw_back(title).save(art_dir / "back.jpg", quality=88)
    (args.game / "art.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(manifest['sheets'])} sheet(s) for {len(cards)} cards to {art_dir}")


if __name__ == "__main__":
    main()
