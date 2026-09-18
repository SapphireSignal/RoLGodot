"""Converts the original maps' gameplay data (Maps/<Name>/<Name>.bcm) into src/content/maps/<Name>.json.

Usage: python tools/convert_maps.py [--check]

A .bcm file is the XML serialisation of TMap (BaseConflict.Map.pas:211): TeamCount, PlayerCount, MapBoundaries
and the named zones (TMultipolygon of TPolygon). The JSON keeps exactly those fields; TMap.CreateFromFile in
src/runtime/map/t_map.gd reads it. It also carries the map's lights (<Name>.lig, the XML of TLightManager in
BaseConflict.Map.Client.pas: FAmbient and FDirectionalLights), read by src/runtime/map/t_light_manager.gd. The other
graphics files next to the .bcm (terrain, vegetation, water) are not converted here.
--check: convert everything but write nothing; exit 1 if a committed file is missing or out of date.
"""
import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPS = ROOT / 'reference' / 'rise-of-legions' / 'Maps'
OUT = ROOT / 'src' / 'content' / 'maps'


def num(text: str):
    """Original data uses German decimal commas."""
    text = text.strip().replace(',', '.')
    value = float(text)
    return int(value) if value.is_integer() and '.' not in text else value


def boolean(text: str) -> bool:
    return text.strip().lower() == 'true'


def vector(element, keys='XYZW'):
    return [num(element.find(k).text) for k in keys]


def convert_lights(lig: Path) -> dict:
    root = ET.parse(lig).getroot()
    lights = []
    for item in root.find('FDirectionalLights').findall('Item'):
        lights.append({
            'Direction': vector(item.find('Direction'), 'XYZ'),
            'Color': vector(item.find('Color')),
            'Enabled': boolean(item.find('Enabled').text),
        })
    return {'Ambient': vector(root.find('FAmbient')), 'DirectionalLights': lights}


def convert(bcm: Path) -> dict:
    root = ET.parse(bcm).getroot()
    bounds = root.find('MapBoundaries')
    zones = {}
    for item in root.find('Zones').findall('Item'):
        polygons = []
        for poly_item in item.find('Value').find('FPolygons').findall('Item'):
            poly = poly_item.find('Polygon')
            polygons.append({
                'Subtractive': boolean(poly_item.find('Subtractive').text),
                'Closed': boolean(poly.find('FClosed').text),
                'Nodes': [[num(n.find('X').text), num(n.find('Y').text)]
                          for n in poly.find('FNodes').findall('Item')],
            })
        zones[item.find('Key').text] = polygons
    return {
        'Source': f'Maps/{bcm.parent.name}/{bcm.name}',
        'TeamCount': int(root.find('TeamCount').text),
        'PlayerCount': int(root.find('PlayerCount').text),
        'MapBoundaries': {k: num(bounds.find(k).text) for k in ('Left', 'Top', 'Right', 'Bottom')},
        'Zones': zones,
        'Lights': convert_lights(bcm.with_suffix('.lig')),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true', help='convert but write nothing')
    args = ap.parse_args()
    stale = []
    for bcm in sorted(MAPS.glob('*/*.bcm')):
        text = json.dumps(convert(bcm), indent=1) + '\n'
        target = OUT / (bcm.stem + '.json')
        old = target.read_text(encoding='utf-8') if target.exists() else None
        if old == text:
            continue
        if args.check:
            stale.append(target.name)
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding='utf-8', newline='\n')
            print(f'wrote {target.relative_to(ROOT)}')
    if stale:
        print('maps out of date (run python tools/convert_maps.py): ' + ', '.join(stale))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
