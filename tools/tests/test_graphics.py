"""Unit tests of the graphics importer's decoders (KTF .tex textures, the minimal FBX reader) on synthetic files.

Run: python -m unittest discover -s tools/tests   (tools/run_tests.ps1 runs it too). Needs no reference/ checkout.
"""
from __future__ import annotations

import os
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import fbx_info  # noqa: E402
import import_graphics  # noqa: E402


def short(s: bytes) -> bytes:
    """Delphi string[4]: length byte + 4 chars."""
    return bytes([len(s)]) + s


def ktf(width, height, pixels, compress):
    header = struct.pack('<II', width, height) + b'\x00' + struct.pack('<I', 1) + short(b'x' * 32)
    out = short(b'%KTF') + short(b'\x0d\xa0\x1a\x0a') + short(b'V.01') + struct.pack('<I', len(header)) + header
    raw = b''.join(struct.pack('<I', p) for p in pixels)
    if compress:
        pairs, last, count = [], pixels[0], 0
        for p in pixels:
            if p == last:
                count += 1
            else:
                pairs += [last, count]
                last, count = p, 1
        pairs += [last, count]
        body = b''.join(struct.pack('<I', v) for v in pairs)
    else:
        body = b''
    chunk = struct.pack('<II', width, height) + short(bytes([0x4F, 0xE0, 0x5A, 0x94]))
    chunk += struct.pack('<QQ', len(raw), len(body))
    return out + chunk + (body if compress else raw)


class KtfTest(unittest.TestCase):
    def decode(self, data):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'a.tex'
            path.write_bytes(data)
            return import_graphics.decode_ktf(path)

    def test_raw_and_rle_decode_the_same(self):
        pixels = [0xFF112233, 0xFF112233, 0xFF112233, 0x80445566]
        for compress in (False, True):
            w, h, bgra = self.decode(ktf(2, 2, pixels, compress))
            self.assertEqual((w, h), (2, 2))
            self.assertEqual(bgra, b''.join(struct.pack('<I', p) for p in pixels))

    def test_pixel_is_bgra(self):
        # A8R8G8B8 0xAARRGGBB is stored little-endian: B, G, R, A.
        _, _, bgra = self.decode(ktf(1, 1, [0x80112233], False))
        self.assertEqual(bgra, bytes([0x33, 0x22, 0x11, 0x80]))

    def test_rejects_other_files(self):
        with self.assertRaises(ValueError):
            self.decode(b'\x04%KTX' + b'\x00' * 40)


class FbxReaderTest(unittest.TestCase):
    def node(self, name, props, children=b'', start=27):
        body = b''.join(props) + children
        end = start + 13 + len(name) + len(body) + (13 if children else 0)
        header = struct.pack('<IIIB', end, len(props), len(b''.join(props)), len(name)) + name.encode()
        return header + body + (b'\x00' * 13 if children else b'')

    def test_reads_properties_and_compressed_arrays(self):
        values = [1.5, -2.0, 3.25, 0.0, 4.0, -1.0]
        raw = struct.pack('<6d', *values)
        comp = zlib.compress(raw)
        array = b'd' + struct.pack('<III', 6, 1, len(comp)) + comp
        name = b'Vertices'
        data = b'Kaydara FBX Binary  \x00\x1a\x00' + struct.pack('<I', 7400)
        data += self.node('Vertices', [array], start=len(data))
        data += b'\x00' * 13
        version, root = fbx_info.read_binary(data)
        self.assertEqual(version, 7400)
        self.assertEqual(root.children[0].name, name.decode())
        self.assertEqual(root.children[0].props[0], values)


if __name__ == '__main__':
    unittest.main()
