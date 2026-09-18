"""Unit tests of the graphics importer (KTF .tex textures, the scripts' graphics references) on synthetic data.

Run: python -m unittest discover -s tools/tests   (tools/run_tests.ps1 runs it too). Needs no reference/ checkout.
"""
from __future__ import annotations

import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
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


class ScriptGraphicsTest(unittest.TestCase):
    """The scripts' own graphics references: bound textures (BindTextureToTeam...) and bare geometry files."""

    def scan(self, text, pattern):
        return [m.groups() for m in pattern.finditer(text)]

    def test_bound_textures_follow_their_mesh_statement(self):
        text = ("TMeshComponent.CreateGrouped(Entity, [2], 'Units\\Neutral\\Nexus\\NexusCrystal.xml')\n"
                "  .CreateNewAnimation(ANIMATION_STAND, 0, 200)\n"
                "  .BindTextureToTeam(mtDiffuse, 'NexusDiffuse.tga', 1)\n"
                "  .BindTextureToTeam(mtGlow, 'NexusGlow2.tga', 2);\n"
                "TMeshComponent.Create(Entity, 'Other.xml');")
        found = self.scan(text, import_graphics.MESH_STATEMENT)
        self.assertEqual(found[0][0], 'Units\\Neutral\\Nexus\\NexusCrystal.xml')
        self.assertEqual(import_graphics.BOUND_TEXTURE.findall(found[0][1]), ['NexusDiffuse.tga', 'NexusGlow2.tga'])
        self.assertEqual(import_graphics.BOUND_TEXTURE.findall(found[1][1]), [])

    def test_bare_geometry_files_are_found(self):
        text = "TMeshComponent.CreateGrouped(Entity, [0], 'Environment\\Stones1\\Stones1.fbx');"
        self.assertEqual([m.group(1) for m in import_graphics.SCRIPT_GEOMETRY.finditer(text)],
                         ['Environment\\Stones1\\Stones1.fbx'])


if __name__ == '__main__':
    unittest.main()
