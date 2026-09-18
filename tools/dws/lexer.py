"""Tokenizer for the DWScript (Object Pascal) subset used by the original game's Scripts/ folder.

Comments are dropped. Compiler directives ({$...}) and balance markers ({@UBL_...}) are kept as tokens so the
preprocessor and the transpiler can see them. Pascal is case-insensitive: `key` holds the lower-case form used
for comparisons, `value` keeps the original spelling.
"""
from __future__ import annotations

from dataclasses import dataclass

KEYWORDS = {
    'and', 'array', 'as', 'begin', 'case', 'class', 'const', 'constructor', 'destructor', 'div', 'do',
    'downto', 'else', 'end', 'except', 'exit', 'finally', 'for', 'forward', 'function', 'helper', 'if', 'in',
    'inherited', 'is', 'mod', 'nil', 'not', 'of', 'operator', 'or', 'overload', 'private', 'procedure',
    'property', 'public', 'raise', 'read', 'record', 'repeat', 'shl', 'shr', 'then', 'to', 'try', 'type',
    'until', 'uses', 'var', 'while', 'write', 'xor',
}

SYMBOLS = [':=', '<=', '>=', '<>', '..', '+=', '-=', '*=', '/=',
           '+', '-', '*', '/', '=', '<', '>', '(', ')', '[', ']', ',', ';', ':', '.', '^', '@']


class LexError(Exception):
    pass


@dataclass
class Token:
    kind: str    # 'ident', 'keyword', 'int', 'float', 'string', 'sym', 'directive', 'marker', 'eof'
    value: str   # original text (strings: decoded content; directives: text between '{$' and '}')
    line: int
    file: str

    @property
    def key(self) -> str:
        return self.value.lower()

    def is_(self, kind: str, key: str | None = None) -> bool:
        return self.kind == kind and (key is None or self.key == key)

    def __repr__(self) -> str:
        return f'{self.kind}:{self.value!r}@{self.file}:{self.line}'


def tokenize(text: str, file: str = '<string>') -> list[Token]:
    tokens: list[Token] = []
    i, line, n = 0, 1, len(text)
    if text.startswith('﻿'):
        i = 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
        elif c in ' \t\r\f\x1a':
            i += 1
        elif text.startswith('//', i):
            while i < n and text[i] != '\n':
                i += 1
        elif c == '{':
            end = text.find('}', i)
            if end < 0:
                raise LexError(f'{file}:{line}: unterminated {{ comment')
            body = text[i + 1:end]
            if body.startswith('$'):
                tokens.append(Token('directive', body[1:].strip(), line, file))
            elif body.startswith('@'):
                tokens.append(Token('marker', body[1:].strip(), line, file))
            line += body.count('\n')
            i = end + 1
        elif text.startswith('(*', i):
            end = text.find('*)', i + 2)
            if end < 0:
                raise LexError(f'{file}:{line}: unterminated (* comment')
            line += text.count('\n', i, end)
            i = end + 2
        elif c == "'" or c == '#':
            # Pascal string: 'it''s' and #13#10 char codes, concatenated without operators
            start_line, parts = line, []
            while i < n and text[i] in "'#":
                if text[i] == "'":
                    j = i + 1
                    while True:
                        if j >= n or text[j] == '\n':
                            raise LexError(f'{file}:{start_line}: unterminated string')
                        if text[j] == "'":
                            if j + 1 < n and text[j + 1] == "'":
                                parts.append("'")
                                j += 2
                                continue
                            break
                        parts.append(text[j])
                        j += 1
                    i = j + 1
                elif text.startswith('#$', i):   # #$0D: hex char code (Delphi sources)
                    j = i + 2
                    while j < n and text[j] in '0123456789abcdefABCDEF':
                        j += 1
                    if j == i + 2:
                        raise LexError(f'{file}:{line}: stray #$')
                    parts.append(chr(int(text[i + 2:j], 16)))
                    i = j
                else:
                    j = i + 1
                    while j < n and text[j].isdigit():
                        j += 1
                    if j == i + 1:
                        raise LexError(f'{file}:{line}: stray #')
                    parts.append(chr(int(text[i + 1:j])))
                    i = j
            tokens.append(Token('string', ''.join(parts), start_line, file))
        elif c.isdigit() or (c == '$' and i + 1 < n and text[i + 1] in '0123456789abcdefABCDEF'):
            j = i + 1
            if c == '$':
                while j < n and text[j] in '0123456789abcdefABCDEF':
                    j += 1
                tokens.append(Token('int', str(int(text[i + 1:j], 16)), line, file))
                i = j
                continue
            while j < n and text[j].isdigit():
                j += 1
            kind = 'int'
            # a '.' followed by a digit is a fraction; '..' is a range and '.x' a member access
            if j + 1 < n and text[j] == '.' and text[j + 1].isdigit():
                kind = 'float'
                j += 1
                while j < n and text[j].isdigit():
                    j += 1
            if j < n and text[j] in 'eE' and j + 1 < n and (text[j + 1].isdigit() or text[j + 1] in '+-'):
                kind = 'float'
                j += 2
                while j < n and text[j].isdigit():
                    j += 1
            tokens.append(Token(kind, text[i:j], line, file))
            i = j
        elif c.isalpha() or c == '_' or c == '&':
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == '_'):
                j += 1
            word = text[i:j]
            if word.startswith('&'):   # &keyword escapes a reserved word into an identifier
                tokens.append(Token('ident', word[1:], line, file))
            else:
                tokens.append(Token('keyword' if word.lower() in KEYWORDS else 'ident', word, line, file))
            i = j
        else:
            for sym in SYMBOLS:
                if text.startswith(sym, i):
                    tokens.append(Token('sym', sym, line, file))
                    i += len(sym)
                    break
            else:
                raise LexError(f'{file}:{line}: unexpected character {c!r}')
    tokens.append(Token('eof', '', line, file))
    return tokens
