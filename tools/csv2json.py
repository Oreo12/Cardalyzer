#!/usr/bin/env python3
"""Convert a game's cards.csv (one row per card) into cards.json for the engine.

Usage: python tools/csv2json.py games/sample/cards.csv [-o games/sample/cards.json]

Checks the things a spreadsheet gets wrong most often: missing or duplicate
ids, non-numeric costs, unknown deck values and malformed effect lists.
Whether an effect keyword exists is checked by the engine at load time,
because the keywords come from the game's rules module.
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

COLUMNS = ["id", "name", "deck", "faction", "type", "cost", "copies",
           "effects", "ally_effects", "scrap_effects", "defense", "text"]
# Optional columns: double_ally_effects (need two other cards of the faction)
# and set (which expansion a card is from, toggled in the New Game menu).
OPTIONAL = ["double_ally_effects", "set", "condition", "points"]
REQUIRED = ["id", "name", "cost", "copies", "effects"]
DECKS = {"starter", "market", "fixed", "dealt", "objective"}
# One effect: keyword:amount, custom:name or a bare keyword like reminder,
# optionally prefixed by a faction (blob=combat:2, ally effects only).
SINGLE = re.compile(r"^(?:[\w]+\s*:\s*-?\d+|custom\s*:\s*[\w-]+|reminder)$")
FACTION_PREFIX = re.compile(r"^[\w]+\s*=\s*")
ID = re.compile(r"^[a-z0-9_]+$")


def parse_int(value, field, card_id, errors, allow_blank=False):
    value = (value or "").strip()
    if value == "" and allow_blank:
        return None
    try:
        return int(value)
    except ValueError:
        errors.append(f"card '{card_id}': {field} must be a whole number, got '{value}'")
        return None


def check_effects(value, field, card_id, errors):
    value = (value or "").strip()
    for part in filter(None, (p.strip() for p in value.split(";"))):
        body = FACTION_PREFIX.sub("", part)
        for option in (o.strip() for o in body.split("|")):
            if not SINGLE.match(option):
                errors.append(f"card '{card_id}': {field} entry '{part}' should look like keyword:amount")
                break
    return value


def convert(rows):
    cards, errors, seen = [], [], set()
    for line, row in enumerate(rows, start=2):
        row = {k.strip(): (v or "").strip() for k, v in row.items() if k}
        card_id = row.get("id", "")
        if not card_id:
            if any(row.values()):
                errors.append(f"line {line}: missing id")
            continue
        if not ID.match(card_id):
            errors.append(f"line {line}: id '{card_id}' should be lowercase letters, digits and _")
        if card_id in seen:
            errors.append(f"line {line}: duplicate id '{card_id}'")
        seen.add(card_id)

        deck = row.get("deck") or "market"
        # "market:<key>" puts a card in an extra market (rules.markets)
        if deck not in DECKS and not re.fullmatch(r"market:\w+", deck):
            errors.append(f"card '{card_id}': deck must be one of {sorted(DECKS)} or market:<key>, got '{deck}'")

        card = {
            "id": card_id,
            "name": row.get("name") or card_id,
            "deck": deck,
            "faction": row.get("faction") or "none",
            "type": row.get("type") or "unit",
            "cost": parse_int(row.get("cost"), "cost", card_id, errors),
            "copies": parse_int(row.get("copies"), "copies", card_id, errors),
            "effects": check_effects(row.get("effects"), "effects", card_id, errors),
            "ally_effects": check_effects(row.get("ally_effects"), "ally_effects", card_id, errors),
            "scrap_effects": check_effects(row.get("scrap_effects"), "scrap_effects", card_id, errors),
            "double_ally_effects": check_effects(row.get("double_ally_effects"), "double_ally_effects", card_id, errors) or None,
            "set": row.get("set") or None,
            "condition": row.get("condition") or None,
            "defense": parse_int(row.get("defense"), "defense", card_id, errors, allow_blank=True),
            "points": parse_int(row.get("points"), "points", card_id, errors, allow_blank=True),
            "text": row.get("text", ""),
        }
        cards.append({k: v for k, v in card.items() if v is not None})
    return cards, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("csv", type=Path)
    parser.add_argument("-o", "--output", type=Path, help="defaults to cards.json next to the CSV")
    args = parser.parse_args()

    with args.csv.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            sys.exit(f"{args.csv}: missing columns {missing}; expected {COLUMNS}")
        cards, errors = convert(reader)

    if errors:
        sys.exit(f"{args.csv}: {len(errors)} problem(s)\n  " + "\n  ".join(errors))

    out = args.output or args.csv.with_name("cards.json")
    out.write_text(json.dumps(cards, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {len(cards)} cards to {out}")


if __name__ == "__main__":
    main()
