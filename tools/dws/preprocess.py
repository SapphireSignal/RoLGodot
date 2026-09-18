"""Preprocessing exactly as the original does it (Engine/Engine.Script.pas + HPreProcessor.ResolveDefines).

Order for a script file:
1. `SCRIPTFILE_FILEPATH` / `SCRIPTFILE_NAME` are replaced by quoted strings (plain text replace).
2. Every active define is prepended as `{$DEFINE X}` (client build: CLIENT, server build: SERVER, +DEBUG).
3. `#define NAME replacement` lines are cut out and every occurrence of NAME is replaced by plain text replace,
   longest name first, case-sensitive and WITHOUT word boundaries (a quirk we must keep).
4. DWScript compiles: `{$IFDEF}`/`{$IFNDEF}`/`{$ELSE}`/`{$ENDIF}`/`{$DEFINE}` and `{$INCLUDE 'x'}`. An included
   file is read from `Scripts/HelperScripts/` and gets step 3 on its own text only: a `#define` of the main
   file never reaches an included file and vice versa.
"""
from __future__ import annotations

import os
import re

from .lexer import LexError, Token, tokenize

_HASH_DEFINE = re.compile(r'#define ([\w\d_]+) (.+)')  # '.' does not match '\n', but does match '\r'


def resolve_hash_defines(text: str) -> str:
    defines = _HASH_DEFINE.findall(text)
    result = _HASH_DEFINE.sub('', text)
    # stable sort, longest name first, like the original's TComparer (ties keep source order)
    for name, replacement in sorted(defines, key=lambda d: -len(d[0])):
        result = result.replace(name, replacement)
    return result


def find_case_insensitive(folder: str, name: str) -> str | None:
    """Windows resolves paths case-insensitively and the original data relies on it."""
    path = folder
    for part in re.split(r'[\\/]', name):
        if not part:
            continue
        try:
            entries = os.listdir(path)
        except OSError:
            return None
        match = next((e for e in entries if e.lower() == part.lower()), None)
        if match is None:
            return None
        path = os.path.join(path, match)
    return path


def read_source(path: str) -> str:
    with open(path, 'rb') as f:
        raw = f.read()
    for enc in ('utf-8-sig', 'cp1252'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    raise LexError(f'{path}: cannot decode')


class Preprocessor:
    def __init__(self, scripts_root: str, defines: set[str]):
        self.scripts_root = scripts_root
        self.unit_path = os.path.join(scripts_root, 'HelperScripts')
        self.base_defines = {d.upper() for d in defines}
        self.includes_used: list[str] = []

    def load_script(self, path: str) -> list[Token]:
        """Tokens of a script after defines, conditionals and includes, directives removed."""
        text = read_source(path)
        text = text.replace('SCRIPTFILE_FILEPATH', "'" + path + "'")
        text = text.replace('SCRIPTFILE_NAME', "'" + os.path.basename(path) + "'")
        text = resolve_hash_defines(text)
        self.includes_used = []
        defines = set(self.base_defines)
        out = self._expand(tokenize(text, os.path.relpath(path, self.scripts_root)), defines, depth=0)
        out.append(Token('eof', '', out[-1].line if out else 1, path))
        return out

    def _include(self, name: str, defines: set[str], depth: int, at: Token) -> list[Token]:
        if depth > 16:
            raise LexError(f'{at.file}:{at.line}: include nesting too deep')
        path = find_case_insensitive(self.unit_path, name)
        if path is None:
            raise LexError(f'{at.file}:{at.line}: include {name!r} not found in HelperScripts')
        self.includes_used.append(os.path.relpath(path, self.scripts_root))
        text = resolve_hash_defines(read_source(path))
        return self._expand(tokenize(text, os.path.relpath(path, self.scripts_root)), defines, depth + 1)

    def _expand(self, tokens: list[Token], defines: set[str], depth: int) -> list[Token]:
        out: list[Token] = []
        # stack of (active_before, branch_taken): active_before = were we emitting when the IF started
        stack: list[list[bool]] = []
        active = True
        for tok in tokens:
            if tok.kind == 'eof':
                break
            if tok.kind != 'directive':
                if active:
                    out.append(tok)
                continue
            word, _, arg = tok.value.partition(' ')
            word, arg = word.upper(), arg.strip()
            if word in ('IFDEF', 'IFNDEF'):
                cond = arg.upper() in defines
                if word == 'IFNDEF':
                    cond = not cond
                stack.append([active, cond])
                active = active and cond
            elif word == 'ELSE':
                if not stack:
                    raise LexError(f'{tok.file}:{tok.line}: $ELSE without $IFDEF')
                before, taken = stack[-1]
                active = before and not taken
            elif word == 'ENDIF':
                if not stack:
                    raise LexError(f'{tok.file}:{tok.line}: $ENDIF without $IFDEF')
                active = stack.pop()[0]
            elif not active:
                continue
            elif word == 'DEFINE':
                defines.add(arg.upper())
            elif word == 'UNDEF':
                defines.discard(arg.upper())
            elif word in ('INCLUDE', 'I'):
                name = arg.strip().strip("'")
                out.extend(self._include(name, defines, depth, tok))
            else:
                raise LexError(f'{tok.file}:{tok.line}: unsupported directive {{${tok.value}}}')
        if stack:
            raise LexError(f'{tokens[0].file}: unterminated $IFDEF')
        return out
