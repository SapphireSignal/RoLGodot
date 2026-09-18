"""Minimal FBX reader for checking what the original's loader saw (not used at runtime).

Usage: python tools/fbx_info.py FILE.fbx [...]   prints GlobalSettings and raw vertex bounds per geometry
       python tools/fbx_info.py --all            one line per FBX under assets/graphics

The original loads FBX through an old assimp without unit or axis conversion (Engine.AssetLoader.AssimpLoader.pas:
only Triangulate | FlipUVs), so the raw numbers in the file are what it used. Binary FBX 7.x (< 7500: 32-bit record
offsets) and ASCII FBX are both read.
"""
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Node:
    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def find(self, name):
        return next((c for c in self.children if c.name == name), None)

    def find_all(self, name):
        return [c for c in self.children if c.name == name]


def _read_prop(data, pos):
    code = chr(data[pos])
    pos += 1
    scalar = {'Y': '<h', 'C': '<?', 'I': '<i', 'F': '<f', 'D': '<d', 'L': '<q'}
    if code in scalar:
        fmt = scalar[code]
        return struct.unpack_from(fmt, data, pos)[0], pos + struct.calcsize(fmt)
    if code in 'fdlib':
        length, encoding, clen = struct.unpack_from('<III', data, pos)
        pos += 12
        raw = data[pos:pos + clen]
        pos += clen
        if encoding == 1:
            raw = zlib.decompress(raw)
        fmt = {'f': 'f', 'd': 'd', 'l': 'q', 'i': 'i', 'b': '?'}[code]
        return list(struct.unpack('<%d%s' % (length, fmt), raw)), pos
    if code in 'SR':
        length = struct.unpack_from('<I', data, pos)[0]
        pos += 4
        raw = data[pos:pos + length]
        return (raw.decode('utf-8', 'replace') if code == 'S' else raw), pos + length
    raise ValueError(f'unknown property type {code!r}')


def _read_node(data, pos, wide):
    if wide:
        end, count, _, name_len = struct.unpack_from('<QQQB', data, pos)
        pos += 25
    else:
        end, count, _, name_len = struct.unpack_from('<IIIB', data, pos)
        pos += 13
    if end == 0:
        return None, pos
    name = data[pos:pos + name_len].decode('ascii', 'replace')
    pos += name_len
    props = []
    for _ in range(count):
        value, pos = _read_prop(data, pos)
        props.append(value)
    children = []
    while pos < end:
        child, pos = _read_node(data, pos, wide)
        if child is None:
            break
        children.append(child)
    return Node(name, props, children), end


def read_binary(data):
    version = struct.unpack_from('<I', data, 23)[0]
    wide = version >= 7500
    pos, top = 27, []
    while pos < len(data):
        node, pos = _read_node(data, pos, wide)
        if node is None:
            break
        top.append(node)
    return version, Node('', [], top)


def global_settings(root):
    props = {}
    gs = root.find('GlobalSettings')
    p70 = gs.find('Properties70') if gs else None
    for p in (p70.children if p70 else []):
        props[p.props[0]] = p.props[4:] if len(p.props) > 4 else []
    return props


def geometry_bounds(root):
    out = []
    objects = root.find('Objects')
    for geo in (objects.find_all('Geometry') if objects else []):
        verts = geo.find('Vertices')
        if verts is None or not verts.props:
            continue
        v = verts.props[0]
        xs, ys, zs = v[0::3], v[1::3], v[2::3]
        out.append((geo.props[1].split('\x00')[0], (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))))
    return out


def info(path: Path):
    data = path.read_bytes()
    if data.startswith(b'Kaydara FBX Binary'):
        version, root = read_binary(data)
        return version, global_settings(root), geometry_bounds(root)
    text = data.decode('latin-1')
    settings = {}
    for key in ('UpAxis', 'UpAxisSign', 'FrontAxis', 'FrontAxisSign', 'CoordAxis', 'CoordAxisSign',
                'UnitScaleFactor', 'OriginalUnitScaleFactor'):
        m = re.search(r'P: "%s",[^\n]*,([-\d.e]+)\s*$' % key, text, re.M)
        if m:
            settings[key] = [float(m.group(1))]
    return 'ascii', settings, []


def summary(path: Path):
    version, settings, bounds = info(path)
    keys = ('UpAxis', 'UpAxisSign', 'FrontAxis', 'FrontAxisSign', 'CoordAxis', 'CoordAxisSign', 'UnitScaleFactor')
    axes = ' '.join('%s=%s' % (k.replace('Axis', ''), settings.get(k, ['?'])[0]) for k in keys)
    if bounds:
        lo = [min(b[1][i] for b in bounds) for i in range(3)]
        hi = [max(b[2][i] for b in bounds) for i in range(3)]
        size = 'raw %.1f x %.1f x %.1f' % tuple(hi[i] - lo[i] for i in range(3))
    else:
        size = 'raw ?'
    return f'{version} {axes} {size}'


def main():
    if sys.argv[1:] == ['--all']:
        for path in sorted((ROOT / 'assets' / 'graphics').rglob('*.fbx')):
            print(path.relative_to(ROOT / 'assets' / 'graphics').as_posix(), '|', summary(path))
        return 0
    for arg in sys.argv[1:]:
        version, settings, bounds = info(Path(arg))
        print(arg, 'version', version)
        for k, v in settings.items():
            print('  ', k, v)
        for name, lo, hi in bounds:
            print('   geometry', name, 'min', lo, 'max', hi)
    return 0


if __name__ == '__main__':
    sys.exit(main())
