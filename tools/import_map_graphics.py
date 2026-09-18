"""Map graphics import (called by tools/import_graphics.py): terrain, water and vegetation of every map.

For each Maps/<Name>/ it writes into assets/graphics/maps/<name>/ (git-ignored, generated on setup):
  <name>.terrain.json    TTerrain's settings (Engine.Terrain.pas, the XML of <Name>.ter without the grid)
  <name>.terrain.bin     the height grid GridData: Size x Size float32 little-endian, x-major (GridData[x][y])
  <name><i>{diffuse,normal,material}.png   the chunk textures TChunkTexture.CustomAfterXMLCreate loads
  <name>.water.json      TWaterManager's surfaces (Engine.Water.pas, <Name>.wat)
  <name>.vegetation.json TVegetationManager's objects (Engine.Vegetation.pas, <Name>.veg) and its wind
Referenced files (water wave / caustics textures, vegetation diffuse textures, vegetation raw meshes .msh) are
copied to their lowercased game-root path under assets/graphics/ ("Graphics\\X" -> assets/graphics/x,
"\\Maps\\X" -> assets/graphics/maps/x), the same rule the runtime uses (TClientMap.ResolveGamePath).
"""
import json
import re
import struct
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent / 'reference' / 'rise-of-legions'
MAPS = GAME / 'Maps'

# Engine.Helferlein.Windows.pas Base64Codes: digits first, not the RFC alphabet.
BASE64_CODES = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/'
CHUNK_MAPS = ('Diffuse', 'Normal', 'Material')


def num(text):
    return float(text.strip().replace(',', '.'))


def boolean(text):
    return text.strip().lower() == 'true'


def vector(element, keys='XYZ'):
    return [num(element.find(k).text) for k in keys]


def decode_base64(text: str) -> bytes:
    """DecodeBase64: 6 bits per known character, stops at the first character outside the alphabet."""
    out = bytearray()
    bits = value = 0
    for char in text:
        index = BASE64_CODES.find(char)
        if index < 0:
            break
        value = value * 64 + index
        bits += 6
        if bits >= 8:
            bits -= 8
            out.append((value >> bits) & 255)
            value &= (1 << bits) - 1
    return bytes(out)


def decode_grid(ter_text: str):
    """TXMLSerializer raw array data (WriteArrayData): per array level a Boolean 'has array children' and an Int32
    length, then the children or the raw elements. GridData is array of array of RSaveRawNode (one single)."""
    match = re.search(r'<GridData[^>]*rawData="true"[^>]*>\s*<!\[CDATA\[(.*?)\]\]>', ter_text, re.S)
    if match is None:
        raise ValueError('terrain has no raw GridData')
    header = re.search(r'<GridData([^>]*)>', ter_text).group(1)
    raw = decode_base64(match.group(1))
    data = zlib.decompress(raw) if 'compressed="true"' in header else raw
    has_children, size = struct.unpack_from('<?i', data, 0)
    pos = 5
    columns = []
    for _ in range(size):
        _, length = struct.unpack_from('<?i', data, pos)
        pos += 5
        if length != size:
            raise ValueError('terrain grid is not square')
        columns.append(data[pos:pos + 4 * length])
        pos += 4 * length
    if pos != len(data):
        raise ValueError('terrain grid has trailing data')
    return size, b''.join(columns)


def game_output(rel: str, out_root: Path) -> Path:
    """A game-root relative path ("Graphics\\A\\B.tga", "\\Maps\\C\\D.tga") -> its lowercased place in the output."""
    parts = [p for p in rel.replace('\\', '/').split('/') if p]
    if parts and parts[0].lower() == 'graphics':
        parts = parts[1:]
    return out_root.joinpath(*[p.lower() for p in parts])


def game_source(rel: str) -> Path | None:
    """Case-insensitive lookup of a game-root relative path in the reference."""
    current = GAME
    for part in [p for p in rel.replace('\\', '/').split('/') if p]:
        if not current.is_dir():
            return None
        found = next((c for c in current.iterdir() if c.name.lower() == part.lower()), None)
        if found is None:
            return None
        current = found
    return current


def convert_terrain(ter: Path):
    text = ter.read_text(encoding='latin-1')
    root = ET.fromstring(re.sub(r'<GridData.*?</GridData>', '', text, flags=re.S))
    size, grid = decode_grid(text)
    settings = root.find('TerrainSettings')
    terrain = {
        'Scale': vector(root.find('FScale')),
        'Position': vector(root.find('FPosition')),
        'TextureSplits': int(root.find('FTextureSplits').text),
        'ChunkIDs': [int(item.find('ChunkID').text) for item in root.find('FChunkTextures').findall('Item')],
        'Geomipmapdistanceerror': num(settings.find('Geomipmapdistanceerror').text),
        'Geomipmapnormalerror': num(settings.find('Geomipmapnormalerror').text),
        'ShadingReduction': num(root.find('ShadingReduction').text),
        'GridSize': size,
    }
    return terrain, grid


def convert_water(wat: Path):
    root = ET.parse(wat).getroot()
    surfaces = []
    for item in root.find('FWaterSurfaces').findall('Item'):
        surface = {}
        for element in item:
            tag = element.tag
            if tag in ('WaterColor', 'SkyColor', 'FallbackWaterColor'):
                surface[tag] = vector(element.find('RGBA'), 'XYZW')
            elif tag == 'Position':
                surface[tag] = vector(element)
            elif tag == 'GeometrySize':
                surface[tag] = vector(element, 'XY')
            elif tag in ('Reflections', 'Refraction'):
                surface[tag] = boolean(element.text)
            elif tag in ('WaveTexture', 'SkyTexture', 'CausticsTexture'):
                surface[tag] = (element.text or '').strip()
            elif tag == 'GeometryResolution':
                surface[tag] = int(element.text)
            else:
                surface[tag] = num(element.text)
        surfaces.append(surface)
    return surfaces


def varied(element):
    """RVariedSingle / RVariedVector2 / RVariedVector3 as {Mean, Variance[, RadialVaried]}."""
    mean, variance = element.find('Mean'), element.find('Variance')
    result = {}
    if mean.find('X') is None:
        result['Mean'], result['Variance'] = num(mean.text), num(variance.text)
    else:
        keys = 'XYZ' if mean.find('Z') is not None else 'XY'
        result['Mean'], result['Variance'] = vector(mean, keys), vector(variance, keys)
    radial = element.find('FRadialVaried')
    if radial is not None:
        result['RadialVaried'] = boolean(radial.text)
    return result


def convert_vegetation(veg: Path):
    root = ET.parse(veg).getroot()
    objects = []
    for item in root.find('FVegetationObjects').findall('Item'):
        kind = item.get('type').rsplit('.', 1)[-1]
        obj = {'Type': kind}
        for element in item:
            tag = element.tag
            if tag == 'FRandSeed':
                obj[tag] = int(element.text)
            elif tag in ('FPosition', 'FGroundNormal'):
                obj[tag] = vector(element)
            elif tag == 'FCastsNoShadows':
                obj[tag] = boolean(element.text)
            elif tag in ('Size', 'Rotation', 'Trapezial', 'Angle'):
                obj[tag] = varied(element)
            elif tag in ('Meshes', 'Diffuse'):
                obj[tag] = element.text or ''
            else:
                obj[tag] = num(element.text)
        objects.append(obj)
    wind = root.find('FWindDirection')
    return {'WindDirection': vector(wind) if wind is not None else None, 'Objects': objects}


def import_maps(out_root: Path, check: bool, copy_if_changed, write_texture, problems: list) -> int:
    """Returns the number of files written."""
    written = 0

    def write(path: Path, content: bytes):
        nonlocal written
        if check or (path.exists() and path.read_bytes() == content):
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        written += 1

    def json_bytes(value) -> bytes:
        return (json.dumps(value, indent=1) + '\n').encode('utf-8')

    def referenced(rel: str, what: str):
        nonlocal written
        if not rel:
            return
        source = game_source(rel)
        if source is None:
            problems.append(f'{what}: "{rel}" not found')
            return
        if not check:
            target = game_output(rel, out_root)
            if target.suffix in ('.tga', '.png'):
                written += write_texture(source, target)
            else:
                written += copy_if_changed(source, target)

    for folder in sorted(p for p in MAPS.iterdir() if p.is_dir()):
        name = folder.name
        out = out_root / 'maps' / name.lower()
        ter = folder / (name + '.ter')
        if ter.exists():
            terrain, grid = convert_terrain(ter)
            write(out / (name.lower() + '.terrain.json'), json_bytes(terrain))
            write(out / (name.lower() + '.terrain.bin'), grid)
            for chunk in terrain['ChunkIDs']:
                for kind in CHUNK_MAPS:
                    referenced('\\Maps\\%s\\%s%d%s.png' % (name, name, chunk, kind), f'{ter.name} chunk {chunk}')
        wat = folder / (name + '.wat')
        if wat.exists():
            surfaces = convert_water(wat)
            write(out / (name.lower() + '.water.json'), json_bytes(surfaces))
            for surface in surfaces:
                for key in ('WaveTexture', 'SkyTexture', 'CausticsTexture'):
                    referenced(surface.get(key, ''), wat.name)
        veg = folder / (name + '.veg')
        if veg.exists():
            vegetation = convert_vegetation(veg)
            # compact: thousands of objects, shipped with the export
            write(out / (name.lower() + '.vegetation.json'),
                  (json.dumps(vegetation, separators=(',', ':')) + '\n').encode('utf-8'))
            files = set()
            for obj in vegetation['Objects']:
                files.add(obj.get('Diffuse', ''))
                for mesh in re.split(r'\r\n|\n', obj.get('Meshes', '')):
                    if mesh:
                        # LOAD_RAW_MESH (release builds): the engine's raw mesh next to the FBX is loaded.
                        files.add(str(Path(mesh).with_suffix('.msh')))
            for rel in sorted(files):
                referenced(rel, veg.name)
    return written
