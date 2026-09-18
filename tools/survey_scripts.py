"""Survey of the DWScript constructs used in reference/.../Scripts (input for docs/scripts.md and the transpiler).

Usage: python tools/survey_scripts.py [--json logs/script_survey.json]
Prints a summary; exits 1 if any script fails to tokenize or preprocess.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dws.lexer import LexError, tokenize  # noqa: E402
from dws.preprocess import Preprocessor, read_source, resolve_hash_defines  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, 'reference', 'rise-of-legions', 'Scripts')
EXTENSIONS = ('.ets', '.dws', '.sps')


def script_files() -> list[str]:
    found = []
    for folder, _, files in os.walk(SCRIPTS):
        for name in files:
            if name.lower().endswith(EXTENSIONS):
                found.append(os.path.join(folder, name))
    return sorted(found)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--json', help='write the full survey as JSON')
    args = ap.parse_args()

    files = script_files()
    errors: list[str] = []
    ext_count = Counter(os.path.splitext(f)[1].lower() for f in files)
    directives, markers, keywords, symbols = Counter(), Counter(), Counter(), Counter()
    ifdef_prev, ifdef_next = Counter(), Counter()
    spellings: dict[str, Counter] = defaultdict(Counter)
    routines, globals_, includes = Counter(), Counter(), Counter()
    classes, members = Counter(), Counter()
    hash_define_files = []

    for path in files:
        rel = os.path.relpath(path, SCRIPTS)
        text = read_source(path)
        if '#define' in text:
            hash_define_files.append(rel)
        try:
            toks = tokenize(resolve_hash_defines(text), rel)
        except LexError as e:
            errors.append(str(e))
            continue
        significant = [t for t in toks if t.kind != 'eof']
        for idx, t in enumerate(significant):
            if t.kind == 'directive':
                word = t.value.split(' ')[0].upper()
                directives[word + ('' if word not in ('IFDEF', 'IFNDEF') else ' ' + t.value.split(' ')[-1].upper())] += 1
                if word in ('IFDEF', 'IFNDEF', 'ELSE', 'ENDIF'):
                    prev = next((p for p in reversed(significant[:idx]) if p.kind != 'directive'), None)
                    nxt = next((p for p in significant[idx + 1:] if p.kind != 'directive'), None)
                    if word in ('IFDEF', 'IFNDEF', 'ELSE'):
                        ifdef_prev[prev.key if prev else '<start>'] += 1
                    if word in ('ENDIF', 'ELSE'):
                        ifdef_next[nxt.key if nxt else '<end>'] += 1
                if word in ('INCLUDE', 'I'):
                    includes[t.value.split(' ', 1)[1].strip().strip("'")] += 1
            elif t.kind == 'marker':
                markers[t.value] += 1
            elif t.kind == 'keyword':
                keywords[t.key] += 1
            elif t.kind == 'sym':
                symbols[t.value] += 1
            elif t.kind == 'ident':
                spellings[t.key][t.value] += 1
                prev = significant[idx - 1] if idx else None
                nxt = significant[idx + 1] if idx + 1 < len(significant) else None
                if prev is not None and prev.is_('sym', '.'):
                    members[t.value] += 1
                elif nxt is not None and nxt.is_('sym', '.') and t.value[:1] == 'T' and t.value[1:2].isupper():
                    classes[t.value] += 1
        # top-level routines and globals (depth 0 = outside begin/end, record, class)
        depth, in_var = 0, False
        for idx, t in enumerate(significant):
            if t.kind == 'keyword' and t.key in ('begin', 'record', 'try', 'case'):
                depth += 1
            elif t.kind == 'keyword' and t.key == 'class' and idx + 1 < len(significant) \
                    and not significant[idx + 1].is_('keyword', 'function') \
                    and not significant[idx + 1].is_('keyword', 'procedure'):
                depth += 1
            elif t.kind == 'keyword' and t.key == 'end':
                depth -= 1
            elif depth == 0 and t.kind == 'keyword' and t.key in ('procedure', 'function'):
                in_var = False
                name = significant[idx + 1]
                if not significant[idx + 2].is_('sym', '.'):
                    routines[name.value] += 1
            elif depth == 0 and t.kind == 'keyword' and t.key == 'var':
                prev = significant[idx - 1] if idx else None
                # a 'var' right after a routine header's ';' is a local section, not a global one
                in_var = prev is None or not any(
                    p.kind == 'keyword' and p.key in ('procedure', 'function')
                    for p in significant[max(0, idx - 40):idx])
            elif depth == 0 and in_var and t.kind == 'ident' and idx + 1 < len(significant) \
                    and significant[idx + 1].kind == 'sym' and significant[idx + 1].value in (':', ','):
                globals_[t.value] += 1
            elif t.kind == 'keyword' and t.key in ('const', 'type'):
                in_var = False

    per_side = {}
    for side in ('CLIENT', 'SERVER'):
        ok = 0
        for path in files:
            pp = Preprocessor(SCRIPTS, {side})
            try:
                pp.load_script(path)
                ok += 1
            except LexError as e:
                errors.append(f'[{side}] {e}')
        per_side[side] = ok

    case_variants = {k: dict(v) for k, v in spellings.items() if len(v) > 1}
    survey = {
        'files': len(files), 'extensions': dict(ext_count), 'preprocessed_ok': per_side,
        'directives': dict(directives), 'includes': dict(includes), 'hash_define_files': hash_define_files,
        'markers': dict(markers), 'keywords': dict(keywords), 'symbols': dict(symbols),
        'ifdef_after_token': dict(ifdef_prev), 'endif_before_token': dict(ifdef_next),
        'top_level_routines': dict(routines), 'globals': dict(globals_),
        'classes': dict(classes), 'members': dict(members), 'case_variants': case_variants,
        'errors': errors,
    }
    if args.json:
        with open(args.json, 'w', encoding='utf-8') as f:
            json.dump(survey, f, indent=1, sort_keys=True)

    def top(c: Counter, n: int = 25) -> str:
        return ', '.join(f'{k} {v}' for k, v in c.most_common(n))

    print(f'files: {len(files)} {dict(ext_count)}; preprocessed ok: {per_side}')
    print(f'directives: {top(directives)}')
    print(f'includes: {top(includes)}')
    print(f'#define files: {hash_define_files}')
    print(f'markers: {top(markers)}')
    print(f'keywords: {top(keywords, 60)}')
    print(f'symbols: {top(symbols, 40)}')
    print(f'$IFDEF/$ELSE after: {top(ifdef_prev)}')
    print(f'$ENDIF/$ELSE before: {top(ifdef_next)}')
    print(f'routines ({len(routines)}): {top(routines, 40)}')
    print(f'globals: {top(globals_, 40)}')
    print(f'classes: {len(classes)}, members: {len(members)}, case-variant identifiers: {len(case_variants)}')
    for e in errors[:30]:
        print('ERROR', e)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
