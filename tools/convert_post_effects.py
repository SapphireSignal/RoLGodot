"""Converts the original post effect stack (PostEffects.fxs, the XML TPostEffectManager.LoadFromFile reads at start-up)
into src/content/post_effects.json.

Usage: python tools/convert_post_effects.py [--check]

The file serializes TPostEffectManager.FPostEffects, a TObjectDictionary<string, TPostEffect>: one <Item> per effect
with its <Key> (the UID) and a <Value type="Engine.PostEffects.TPostEffect..."> holding the published fields.
The JSON keeps the items in file order (the order fills the dictionary, whose walk order feeds ToArray's sort):
  [{"Key": UID, "Class": "TPostEffectGlow", "Fields": {name: value}}, ...]
Values: True / False -> bool, integers -> int, German decimal commas -> float, <X><Y><Z> -> [x, y, z], else the text
(enum names such as ToonType ttBorder). TPostEffectManager in src/runtime/graphics/t_post_effect_manager.gd reads it.
--check: convert but write nothing; exit 1 if the committed file is missing or out of date.
"""
import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'reference' / 'rise-of-legions' / 'PostEffects.fxs'
TARGET = ROOT / 'src' / 'content' / 'post_effects.json'

RE_INT = re.compile(r'^-?\d+$')
RE_FLOAT = re.compile(r'^-?\d+,\d+(E-?\d+)?$')


def value_of(element: ET.Element):
    children = list(element)
    if children:
        if [c.tag for c in children] != ['X', 'Y', 'Z']:
            raise SystemExit(f'unknown compound field {element.tag}: {[c.tag for c in children]}')
        return [value_of(c) for c in children]
    text = (element.text or '').strip()
    if text in ('True', 'False'):
        return text == 'True'
    if RE_INT.match(text):
        return int(text)
    if RE_FLOAT.match(text):
        return float(text.replace(',', '.'))
    return text


def convert(text: str) -> list:
    root = ET.fromstring(text)
    effects = root.find('FPostEffects')
    if effects is None:
        raise SystemExit('FPostEffects not found in ' + SOURCE.name)
    result = []
    for item in effects.findall('Item'):
        key = item.findtext('Key')
        value = item.find('Value')
        fields = {child.tag: value_of(child) for child in value}
        result.append({'Key': key, 'Class': value.get('type').rsplit('.', 1)[1], 'Fields': fields})
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true', help='convert but write nothing')
    args = ap.parse_args()
    entries = convert(SOURCE.read_text(encoding='utf-8'))
    text = '[\n' + ',\n'.join(json.dumps(e) for e in entries) + '\n]\n'
    old = TARGET.read_text(encoding='utf-8') if TARGET.exists() else None
    if old == text:
        return 0
    if args.check:
        print('post effects out of date (run python tools/convert_post_effects.py): ' + TARGET.name)
        return 1
    TARGET.write_text(text, encoding='utf-8', newline='\n')
    print(f'wrote {TARGET.relative_to(ROOT)} ({len(entries)} effects)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
