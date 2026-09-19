"""Resolve offsets in RiseOfLegions.exe to function and source line with the Delphi map file (docs/original-build.md).

    python tools/original_build/resolve_map.py build/original/src/RiseOfLegions.map <offset hex> ...

The client log prints "offset XXXXXXXX" for access violations; for other addresses subtract the load base (an
access violation's address minus its offset)."""
import re
import sys
import bisect

try:
    map_path = sys.argv[1]
    offsets = [int(a, 16) for a in sys.argv[2:]]
    text = open(map_path, encoding='latin-1').read()
    # segment 0001 (.text) starts at RVA 0x1000 in Delphi Win32 images
    text_rva = 0x1000
    m = re.search(r'^\s*0001:00000000\s+[0-9A-F]+H\s+\.text', text, re.M)
    publics = []
    sec = text[text.index('Publics by Value'):]
    sec = sec[:sec.index('Line numbers for')] if 'Line numbers for' in sec else sec
    for mm in re.finditer(r'^\s*0001:([0-9A-F]{8})\s+(\S+)', sec, re.M):
        publics.append((int(mm.group(1), 16), mm.group(2)))
    publics.sort()
    lines = []
    for block in re.finditer(r'Line numbers for (\S+)\((\S+)\) segment \.text\s*\n\n(.*?)(?=\n\n)', text, re.S):
        src = block.group(2)
        for mm in re.finditer(r'(\d+)\s+0001:([0-9A-F]{8})', block.group(3)):
            lines.append((int(mm.group(2), 16), src, int(mm.group(1))))
    lines.sort()
    pk = [p[0] for p in publics]
    lk = [l[0] for l in lines]
    for off in offsets:
        seg = off - text_rva
        i = bisect.bisect_right(pk, seg) - 1
        j = bisect.bisect_right(lk, seg) - 1
        fn = publics[i][1] if i >= 0 else '?'
        ln = '%s:%d' % (lines[j][1], lines[j][2]) if j >= 0 else '?'
        print('%08X -> %s  (%s)' % (off, fn, ln))
except Exception as e:
    print('probe failed:', e)
