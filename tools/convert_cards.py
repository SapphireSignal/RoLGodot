"""Converts the original card list (the initialization section of BaseConflict.Constants.Cards.pas) into
src/content/cards.json.

Usage: python tools/convert_cards.py [--check]

The original registers every card at start-up with CardInfoManager.AddCard(UID, TCardInfo.Create(CardType,
[Colors], Filename, Techlevel)[, SkinID]) and its skins with CardInfoManager.AddSkin(BaseUID, UID, SKIN_GROUP_*).
The JSON keeps those calls in their order (the order fills the manager's dictionary, whose walk order the game uses):
  ["card", UID, CardType, [Colors], Filename, Techlevel, SkinID]   (CardType / Colors as enum ordinals, SkinID '')
  ["skin", BaseUID, UID, SkinID]
TCardInfoManager in src/runtime/classes/t_card_info_manager.gd replays them.
--check: convert but write nothing; exit 1 if the committed file is missing or out of date.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'reference' / 'rise-of-legions' / 'BaseConflict.Constants.Cards.pas'
TARGET = ROOT / 'src' / 'content' / 'cards.json'

RE_ENUM = r'{name}\s*=\s*\(([^)]*)\)'
RE_SKIN_CONST = re.compile(r"^\s*(SKIN_GROUP_\w+)\s*=\s*'([^']*)'\s*;", re.M)
RE_CARD = re.compile(r"^CardInfoManager\.AddCard\('([^']+)',\s*TCardInfo\.Create\((\w+),\s*\[([^\]]*)\],\s*'([^']+)',"
                     r"\s*(\d+)\)(?:,\s*(SKIN_GROUP_\w+))?\);\s*$")
RE_SKIN = re.compile(r"^CardInfoManager\.AddSkin\('([^']+)',\s*'([^']+)',\s*(SKIN_GROUP_\w+)\);\s*$")


def enum_ordinals(text: str, name: str) -> dict:
    m = re.search(RE_ENUM.format(name=name), text)
    if m is None:
        raise SystemExit(f'enum {name} not found in {SOURCE.name}')
    return {item.strip(): i for i, item in enumerate(m.group(1).split(','))}


def convert(text: str) -> list:
    card_types = enum_ordinals(text, 'EnumCardType')
    colors = enum_ordinals(text, 'EnumEntityColor')
    skins = dict(RE_SKIN_CONST.findall(text))
    body = text.split('\ninitialization', 1)[1]
    result = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith('CardInfoManager.Add'):
            continue
        m = RE_CARD.match(line)
        if m:
            uid, card_type, card_colors, filename, techlevel, skin = m.groups()
            color_list = sorted(colors[c.strip()] for c in card_colors.split(',') if c.strip())
            result.append(['card', uid, card_types[card_type], color_list, filename, int(techlevel),
                           skins[skin] if skin else ''])
            continue
        m = RE_SKIN.match(line)
        if m:
            base_uid, uid, skin = m.groups()
            result.append(['skin', base_uid, uid, skins[skin]])
            continue
        raise SystemExit(f'unknown card line: {line}')
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true', help='convert but write nothing')
    args = ap.parse_args()
    entries = convert(SOURCE.read_text(encoding='cp1252'))
    text = '[\n' + ',\n'.join(json.dumps(e) for e in entries) + '\n]\n'
    old = TARGET.read_text(encoding='utf-8') if TARGET.exists() else None
    if old == text:
        return 0
    if args.check:
        print('cards out of date (run python tools/convert_cards.py): ' + TARGET.name)
        return 1
    TARGET.write_text(text, encoding='utf-8', newline='\n')
    print(f'wrote {TARGET.relative_to(ROOT)} ({len(entries)} entries)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
