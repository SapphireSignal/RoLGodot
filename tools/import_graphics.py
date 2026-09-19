"""Copies the original's mesh graphics into the Godot project: assets/graphics/ (git-ignored, generated on setup).

Usage: python tools/import_graphics.py [--only SUBSTRING] [--check]

For every mesh descriptor (Graphics/**/*.xml, the XML serialisation of TMesh, Engine.Mesh.pas) it writes
  assets/graphics/<lowercased relative path>.mesh.json   the descriptor: parsed numbers, resolved file names
  assets/graphics/<...>/<geometry>.msh                    the raw mesh release builds load instead of the FBX, copied
  assets/graphics/<...>/<texture>.tga|.png                 each referenced texture, copied, or decoded from the
                                                           engine's own .tex (KTF) when no source image exists
and a Godot .import file for each texture (lossless, mipmaps: the original generates mipmaps, mhGenerate).
Then the maps' graphics (terrain, water, vegetation): tools/import_map_graphics.py (not with --only).
All paths are lowercased: the original ran on case-insensitive Windows and its references differ in case from the
files on disk, so the port resolves every graphics path by lowercasing it (see docs/assets.md).
--check: resolve everything, write nothing; exit 1 if a reference cannot be resolved.
"""
import argparse
import json
import re
import shutil
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import import_map_graphics

ROOT = Path(__file__).resolve().parent.parent
GRAPHICS = ROOT / 'reference' / 'rise-of-legions' / 'Graphics'
OUT = ROOT / 'assets' / 'graphics'

# TRawMesh.SetDefaultMaterialSettings: values a descriptor may leave out.
DEFAULTS = {
    'TextureSemiTransparency': False, 'Cullmode': 'cmCCW', 'Alpha': 1.0, 'AlphaTestTreshold': 0.0,
    'SpecularIntensity': 0.0, 'SpecularPower': 128.0, 'SpecularTint': 1.0, 'ShadingReduction': 0.0,
    'Outline': False, 'OnlyOutline': False, 'OutlineColor': [0.0, 0.0, 0.0, 0.0],
    'FurCullmode': 'cmCCW', 'FurIterations': 10, 'FurThickness': 10.1960, 'FurTrackBone': '',
    'FurResponsivness': 0.0081176, 'FurAcceleration': 1.0, 'FurAccelerationResponsivness': 0.030980,
    'FurAttenuation': 0.00388235, 'FurMovementLength': 1.0, 'FurGravitation': 1.0,
}
TEXTURE_FIELDS = {'DiffuseTetxure': 'DiffuseTexture', 'NormalTexture': 'NormalTexture',
                  'SpecularTexture': 'MaterialTexture', 'GlowTexture': 'GlowTexture', 'FurTexture': 'FurTexture'}
IMAGE_EXTENSIONS = ('.tga', '.png', '.jpg')

TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""

# Release builds load every mesh's geometry from the engine's raw mesh next to it (LOAD_RAW_MESH,
# TMeshAnimatedGeometry.CreateFromFile: ChangeFileExt(geometry, '.msh')); the port does the same (TEngineRawMesh).
RAW_MESH_EXTENSION = '.msh'


def num(text):
    """Original data uses German decimal commas."""
    return float(text.strip().replace(',', '.'))


def boolean(text):
    return text.strip().lower() == 'true'


def decode_ktf(path: Path):
    """Engine.Core.Texture.pas TEngineRawTexture: returns (width, height, BGRA bytes) of the top mip level.

    Packed records: RPreHeader = string[4] x3 (5 bytes each) + UInt32 HeaderLength; RHeader (HeaderLength bytes)
    starts with Width, Height; each mip chunk header = Width, Height, string[4] protector, UInt64 DataSize,
    UInt64 CompressedDataSize, then raw 32-bit pixels or RLE (value, count) Cardinal pairs."""
    data = path.read_bytes()
    if data[1:5] != b'%KTF' or data[11:15] != b'V.01':
        raise ValueError(f'{path}: not a KTF V.01 texture')
    header_length = struct.unpack_from('<I', data, 15)[0]
    pos = 19 + header_length
    width, height = struct.unpack_from('<II', data, pos)
    protector = data[pos + 9:pos + 13]
    if protector != bytes([0x4F, 0xE0, 0x5A, 0x94]):
        raise ValueError(f'{path}: bad chunk protector')
    data_size, compressed_size = struct.unpack_from('<QQ', data, pos + 13)
    pos += 29
    if compressed_size == 0:
        return width, height, data[pos:pos + data_size]
    out = bytearray()
    for i in range(0, compressed_size, 8):
        value, count = struct.unpack_from('<II', data, pos + i)
        out += struct.pack('<I', value) * count
    if len(out) != width * height * 4:
        raise ValueError(f'{path}: RLE size mismatch')
    return width, height, bytes(out)


def ktf_to_png(src: Path, dst: Path):
    from PIL import Image
    width, height, bgra = decode_ktf(src)
    # A Cardinal pixel is D3D A8R8G8B8: little-endian bytes B, G, R, A.
    Image.frombytes('RGBA', (width, height), bgra, 'raw', 'BGRA').save(dst)


class Folder:
    """Case-insensitive view of one directory of the original."""

    def __init__(self, path: Path):
        self.path = path
        self.files = {p.name.lower(): p for p in path.iterdir() if p.is_file()}

    def find(self, name: str):
        return self.files.get(name.lower())


def resolve_texture(folder: Folder, name: str):
    """TRawMesh.Set*Texture: a relative name is taken from the descriptor's folder; TTexture loads the source image
    or, when only the engine cache exists, the .tex. Returns (source path, output file name) or None."""
    source = folder.find(name)
    if source is not None and source.suffix.lower() in IMAGE_EXTENSIONS:
        return source, name.lower()
    stem = Path(name).stem
    for ext in IMAGE_EXTENSIONS:
        source = folder.find(stem + ext)
        if source is not None:
            return source, (stem + ext).lower()
    source = folder.find(stem + '.tex')
    if source is not None:
        return source, (stem + '.png').lower()
    return None


def parse_descriptor(xml_path: Path, folder: Folder, problems: list):
    root = ET.parse(xml_path).getroot()
    if root.tag != 'TMesh':
        return None
    mesh = dict(DEFAULTS)
    textures = {}
    for element in root:
        tag, text = element.tag, (element.text or '').strip()
        if tag == 'GeometryFile':
            geometry = folder.find(Path(text).stem + RAW_MESH_EXTENSION) if text else None
            if geometry is None:
                problems.append(f'{xml_path}: geometry "{text}" not found (as {RAW_MESH_EXTENSION})')
                return None
            mesh['GeometryFile'] = geometry.name.lower()
            mesh['_geometry_source'] = geometry
        elif tag in TEXTURE_FIELDS:
            key = TEXTURE_FIELDS[tag]
            if not text:
                mesh[key] = ''
                continue
            resolved = resolve_texture(folder, Path(text).name)
            if resolved is None:
                # TRawMesh logs "Can't find texture" and renders without it.
                problems.append(f'{xml_path}: texture "{text}" not found (rendered without it, like the original)')
                mesh[key] = ''
                continue
            mesh[key] = resolved[1]
            textures[resolved[1]] = resolved[0]
        elif tag == 'OutlineColor':
            rgba = element.find('RGBA')
            mesh[tag] = [num(rgba.find(c).text) for c in 'XYZW']
        elif tag in ('TextureSemiTransparency', 'Outline', 'OnlyOutline'):
            mesh[tag] = boolean(text)
        elif tag in ('Cullmode', 'FurCullmode', 'FurTrackBone'):
            mesh[tag] = text
        elif tag == 'FurIterations':
            mesh[tag] = int(num(text))
        elif tag in DEFAULTS:
            mesh[tag] = num(text)
        # Other elements (the old 'Specular' of 10 descriptors) have no published property: the deserializer skips them.
    for key in TEXTURE_FIELDS.values():
        mesh.setdefault(key, '')
    return mesh, textures


SCRIPTS = ROOT / 'reference' / 'rise-of-legions' / 'Scripts'
MESH_STATEMENT = re.compile(r"TMeshComponent\.Create(?:Grouped)?\([^;]*?'([^']+\.xml)'([^;]*)", re.IGNORECASE | re.DOTALL)
BOUND_TEXTURE = re.compile(r"BindTextureTo(?:Team|UnitProperty|Resource)\(\s*mt\w+\s*,\s*'([^']+)'", re.IGNORECASE)


def script_textures():
    """Textures the client scripts swap in (TMeshComponent.BindTextureToTeam / UnitProperty / Resource): a name is
    taken from the mesh descriptor's folder (TRawMesh.Set*Texture). Returns {descriptor path relative to Graphics
    (lower case, forward slashes): set of texture names}."""
    found = {}
    for path in SCRIPTS.rglob('*'):
        if path.suffix.lower() not in ('.ets', '.dws'):
            continue
        text = path.read_text(encoding='utf-8', errors='replace')
        for match in MESH_STATEMENT.finditer(text):
            names = BOUND_TEXTURE.findall(match.group(2))
            if names:
                key = match.group(1).replace('\\', '/').lower().lstrip('/')
                found.setdefault(key, set()).update(names)
    return found


GEOMETRY_EXTENSIONS = ('.x', '.fbx', '.binaryfbx', '.morphfbx', '.basefbx', '.obj', '.blend', '.3ds', '.dae', '.msh')
SCRIPT_GEOMETRY = re.compile(r"TMeshComponent\.Create(?:Grouped)?\([^;]*?'([^']+\.(?:%s))'"
                             % '|'.join(e[1:] for e in GEOMETRY_EXTENSIONS), re.IGNORECASE | re.DOTALL)
CONVENTION_EXTENSIONS = ('.tga', '.png', '.jpg', '.psd')


def script_geometry():
    """Geometry files the client scripts load directly instead of a descriptor (Environment\\Stones1\\Stones1.fbx),
    relative to Graphics, as written."""
    found = set()
    for path in SCRIPTS.rglob('*'):
        if path.suffix.lower() in ('.ets', '.dws'):
            for match in SCRIPT_GEOMETRY.finditer(path.read_text(encoding='utf-8', errors='replace')):
                found.add(match.group(1).replace('\\', '/').lstrip('/'))
    return found


def parse_geometry(folder: Folder, name: str):
    """TRawMesh.CreateFromFile with a geometry file: default material settings (Init), the geometry, and textures by
    name convention: ChangeFileExt(file, 'Diffuse' + ext), then the lowercased file with '_diffuse' + ext, per
    extension .tga, .png, .jpg, .psd (same for Normal, Material, Glow). Returns (mesh, textures) or None."""
    raw = folder.find(Path(name).stem + RAW_MESH_EXTENSION)
    if folder.find(name) is None or raw is None:
        return None
    mesh = dict(DEFAULTS)
    mesh['GeometryFile'] = raw.name.lower()
    mesh['_geometry_source'] = raw
    for key in TEXTURE_FIELDS.values():
        mesh[key] = ''
    textures = {}
    stem = Path(name).stem
    for ext in CONVENTION_EXTENSIONS:
        for key, suffix in (('DiffuseTexture', 'Diffuse'), ('NormalTexture', 'Normal'), ('MaterialTexture', 'Material'),
                            ('GlowTexture', 'Glow')):
            if mesh[key]:
                continue
            source = folder.find(stem + suffix + ext) or folder.find(stem.lower() + '_' + suffix.lower() + ext)
            if source is not None:
                mesh[key] = source.name.lower()
                textures[mesh[key]] = source
    return mesh, textures


def copy_if_changed(src: Path, dst: Path):
    if dst.exists() and dst.stat().st_size == src.stat().st_size and dst.stat().st_mtime >= src.stat().st_mtime:
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return True


def write_texture(src: Path, dst: Path) -> int:
    """Copies a source image (or decodes a .tex) and gives it the texture .import. Returns files written."""
    written = 0
    if src.suffix.lower() == '.tex':
        if not dst.exists():
            ktf_to_png(src, dst)
            written += 1
    else:
        written += copy_if_changed(src, dst)
    import_file = dst.with_name(dst.name + '.import')
    if not import_file.exists():
        import_file.write_text(TEXTURE_IMPORT, encoding='utf-8', newline='\n')
        written += 1
    return written


# Textures the ported mesh effects load by game path (TMeshEffect*: matcaps, metal, spawn mask, glow overrides),
# relative to Graphics/. Glob patterns; a name matching nothing is a problem.
EFFECT_TEXTURES = ['Effects/Textures/Matcap*', 'Effects/Textures/SpawnMask*', 'Effects/Textures/*Glow*',
                   'Effects/Metal/Metal_*']


SCRIPT_EFFECT = re.compile(r"TMeshEffect\w*\.Create\(([^;]*)", re.IGNORECASE)
IMAGE_LITERAL = re.compile(r"'([^']*\.(?:tga|png))'", re.IGNORECASE)


def script_effect_textures():
    """Texture file names the client scripts give mesh effects (TMeshEffectHideAndGlow / Warp / Wobble .Create:
    'PATH_GRAPHICS + ''Units\\White\\PatronSaint'' + Entity.SkinFileSuffix + ''\\PatronSaintSpawnMask.tga'''): the
    file names, lower case, found in any folder (a skinned path fits every skin folder)."""
    found = set()
    for path in SCRIPTS.rglob('*'):
        if path.suffix.lower() in ('.ets', '.dws'):
            for match in SCRIPT_EFFECT.finditer(path.read_text(encoding='utf-8', errors='replace')):
                for literal in IMAGE_LITERAL.findall(match.group(1)):
                    # a %d name is formatted with the team when drawn (the matcaps, imported by EFFECT_TEXTURES)
                    if '%' not in literal:
                        found.add(Path(literal.replace('\\', '/')).name.lower())
    return found


def import_effect_textures(check: bool, problems: list) -> int:
    """Copies the effect textures to assets/graphics/<lowercased path> (the source image, else the decoded .tex):
    the effects' own (EFFECT_TEXTURES) and the ones scripts name, from every folder that has them."""
    written = 0
    wanted = script_effect_textures()
    by_name = {}
    for path in sorted(GRAPHICS.rglob('*')):
        if path.suffix.lower() in IMAGE_EXTENSIONS and path.name.lower() in wanted:
            by_name.setdefault(path.name.lower(), []).append(path)
    for name in sorted(wanted):
        if name not in by_name:
            problems.append(f'script effect texture "{name}" not found (rendered without it, like the original)')
            continue
        for source in by_name[name]:
            if not check:
                rel = source.relative_to(GRAPHICS).parent.as_posix().lower()
                written += write_texture(source, OUT / rel / name)
    for pattern in EFFECT_TEXTURES:
        sources = {}
        for path in sorted(GRAPHICS.glob(pattern)):
            if path.suffix.lower() in IMAGE_EXTENSIONS:
                sources[path.stem.lower()] = path
        for path in sorted(GRAPHICS.glob(pattern)):
            if path.suffix.lower() == '.tex' and path.stem.lower() not in sources:
                sources[path.stem.lower()] = path
        if not sources:
            problems.append(f'effect textures "{pattern}" not found')
        for stem, source in sorted(sources.items()):
            if check:
                continue
            rel = source.relative_to(GRAPHICS).parent.as_posix().lower()
            suffix = '.png' if source.suffix.lower() == '.tex' else source.suffix.lower()
            written += write_texture(source, OUT / rel / (stem + suffix))
    return written


def import_fonts(check: bool, problems: list) -> int:
    """Copies the GUI fonts (Graphics/Fonts: Proza Libre in its weights, fontawesome) to assets/graphics/fonts/."""
    fonts = sorted((GRAPHICS / 'Fonts').glob('*.ttf'))
    if not fonts:
        problems.append('Graphics/Fonts/*.ttf not found')
    written = 0
    for source in fonts:
        if not check:
            (OUT / 'fonts').mkdir(parents=True, exist_ok=True)
            written += copy_if_changed(source, OUT / 'fonts' / source.name.lower())
    # GUI images the ported HUD parts use (the GUI converter of phase 7 will take over)
    for pattern in GUI_IMAGES:
        sources = sorted(GRAPHICS.glob(pattern))
        if not sources:
            problems.append(f'GUI images "{pattern}" not found')
        for source in sources:
            if not check:
                rel = source.relative_to(GRAPHICS).parent.as_posix().lower()
                written += write_texture(source, OUT / rel / source.name.lower())
    return written


GUI_IMAGES = ['GUI/HUD/TechnicalPanel/*.png']


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='only descriptors whose path contains this (case-insensitive)')
    ap.add_argument('--check', action='store_true', help='resolve but write nothing')
    args = ap.parse_args()
    if not GRAPHICS.exists():
        print('reference/ is missing: run tools/fetch_reference.ps1 first')
        return 1

    problems, count, written = [], 0, 0
    folders = {}
    meshes = []
    bound_textures = script_textures()
    for xml_path in sorted(GRAPHICS.rglob('*')):
        if xml_path.suffix.lower() != '.xml':
            continue
        rel = xml_path.relative_to(GRAPHICS)
        if args.only and args.only.lower() not in str(rel).lower():
            continue
        folder = folders.setdefault(xml_path.parent, Folder(xml_path.parent))
        parsed = parse_descriptor(xml_path, folder, problems)
        if parsed is None:
            continue
        mesh, textures = parsed
        # a skinned unit's path is concatenated ('Units\Black\VoidBowman' + SkinFileSuffix + '\VoidBowman.xml'):
        # its key is the bare file name, which fits every skin folder
        names = bound_textures.get(rel.as_posix().lower(), set()) | bound_textures.get(rel.name.lower(), set())
        for name in sorted(names):
            resolved = resolve_texture(folder, Path(name.replace('\\', '/')).name)
            if resolved is None:
                problems.append(f'{xml_path}: script texture "{name}" not found (rendered without it, like the original)')
            else:
                textures[resolved[1]] = resolved[0]
        meshes.append((rel, mesh, textures))
    for rel_text in sorted(script_geometry()):
        geometry = GRAPHICS / rel_text
        if args.only and args.only.lower() not in rel_text.lower():
            continue
        folder = folders.setdefault(geometry.parent, Folder(geometry.parent)) if geometry.parent.exists() else None
        parsed = parse_geometry(folder, Path(rel_text).name) if folder else None
        if parsed is None:
            problems.append(f'script mesh "{rel_text}" not found')
            continue
        meshes.append((Path(rel_text), parsed[0], parsed[1]))

    for rel, mesh, textures in meshes:
        count += 1
        if args.check:
            continue
        out_dir = OUT / Path(str(rel.parent).lower())
        out_dir.mkdir(parents=True, exist_ok=True)
        geometry = mesh.pop('_geometry_source')
        written += copy_if_changed(geometry, out_dir / mesh['GeometryFile'])
        for name, source in textures.items():
            written += write_texture(source, out_dir / name)
        mesh['Source'] = 'Graphics/' + rel.as_posix()
        descriptor = out_dir / (Path(rel.name).stem.lower() + '.mesh.json')
        text = json.dumps(mesh, indent=1, sort_keys=True) + '\n'
        if not descriptor.exists() or descriptor.read_text(encoding='utf-8') != text:
            descriptor.write_text(text, encoding='utf-8', newline='\n')
            written += 1

    if not args.check and not args.only:
        # earlier versions copied the FBX files for Godot to import; the raw meshes replaced them
        for stale in list(OUT.rglob('*.fbx')) + list(OUT.rglob('*.fbx.import')):
            stale.unlink()
            written += 1
    if not args.only:
        written += import_effect_textures(args.check, problems)
        written += import_fonts(args.check, problems)
    map_problems = []
    if not args.only:
        written += import_map_graphics.import_maps(OUT, args.check, copy_if_changed, write_texture, map_problems)
    for problem in problems + map_problems:
        print(problem)
    print(f'{count} mesh descriptors, maps, {written} files written, {len(problems) + len(map_problems)} problems')
    mesh_failed = any('not found' in p and 'texture' not in p for p in problems)
    return 1 if args.check and (mesh_failed or map_problems) else 0


if __name__ == '__main__':
    sys.exit(main())
