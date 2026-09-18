"""Symbol table of what the original exposes to scripts, scanned from its Delphi sources.

The game registers script-visible things with `ScriptManager.ExposeClass(TFoo)`, `ExposeType(TypeInfo(EnumFoo))`,
`ExposeConstant('NAME', NAME)` and `ExposeFunction('Game', ...)`. DWScript's ExposeRTTI then makes the public and
published members of each class (with its ancestors) visible. This module finds those registrations and scans
the type declarations they refer to, so the transpiler can
- spell every name like its Delphi declaration (scripts rely on case-insensitivity),
- tell a parameterless method call (`.FireAtGround`) from a property read (`.Blackboard`),
- validate every member a script uses, and
- emit the enum values and constants, and the phase 2 work list.

Declarations in the game folders win over the engine folder (the engine has an older copy of `TEntity`).
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field

from .lexer import LexError, Token, tokenize
from .preprocess import read_source

VISIBILITY = {'private', 'protected', 'public', 'published', 'automated'}
ROUTINE_KEYWORDS = {'procedure', 'function', 'constructor', 'destructor', 'operator'}
ROUTINE_DIRECTIVES = {
    'override', 'virtual', 'dynamic', 'abstract', 'overload', 'reintroduce', 'static', 'inline', 'stdcall',
    'cdecl', 'register', 'safecall', 'final', 'message', 'deprecated', 'platform', 'experimental', 'default',
    'external', 'assembler', 'dispid', 'varargs', 'unsafe',
}
# folders scanned for declarations, in priority order (first declaration of a name wins)
SCAN_FOLDERS = ['', 'GameServer', 'Engine']
_SERVER_ONLY_BLOCK = re.compile(r'\{\$IF Defined\(SERVER\)[^}]*\}.*?\{\$ENDIF\}', re.S)
_EXPOSE = re.compile(r"ScriptManager\.Expose(Class|Type|Constant|Function)\s*\(\s*([^;]*?)\)\s*;", re.I)


@dataclass
class Param:
    name: str
    type: str
    default: str | None = None
    modifier: str = ''          # 'var', 'const', 'out' or ''


@dataclass
class Member:
    name: str
    kind: str                   # 'method', 'property', 'field', 'const'
    visibility: str
    type: str = ''              # property/field type, method result type ('' for procedures)
    routine: str = ''           # 'procedure', 'function', 'constructor', 'destructor', 'operator'
    is_class: bool = False      # class function / class var / const: callable on the type
    params: list[Param] = field(default_factory=list)
    line: int = 0
    owner: str = ''             # the type that declares it (set when the type is registered)


@dataclass
class TypeDecl:
    name: str
    kind: str                   # 'class', 'record', 'interface', 'helper'
    parent: str = ''
    file: str = ''
    line: int = 0
    members: list[Member] = field(default_factory=list)


@dataclass
class EnumDecl:
    name: str
    values: list[tuple[str, int]]
    file: str = ''


class _Scanner:
    def __init__(self, toks: list[Token], table: 'SymbolTable'):
        self.t = toks
        self.i = 0
        self.table = table

    def peek(self, k: int = 0) -> Token:
        return self.t[min(self.i + k, len(self.t) - 1)]

    def at(self, kind: str, key: str | None = None, k: int = 0) -> bool:
        return self.peek(k).is_(kind, key)

    def next(self) -> Token:
        tok = self.peek()
        self.i += 1
        return tok

    def skip_to_semicolon(self) -> list[Token]:
        """Skips to the ';' that ends the current declaration (outside parens/brackets) and returns the skipped."""
        depth, out = 0, []
        while not self.at('eof'):
            tok = self.next()
            if tok.kind == 'sym' and tok.value in '([':
                depth += 1
            elif tok.kind == 'sym' and tok.value in ')]':
                depth -= 1
            elif tok.is_('sym', ';') and depth <= 0:
                return out
            out.append(tok)
        return out

    def type_text(self, stop: set[str]) -> str:
        """Reads a type up to one of the stop symbols (outside <>, () and [])."""
        depth, parts = 0, []
        while not self.at('eof'):
            tok = self.peek()
            if tok.kind == 'sym' and tok.value in '([<':
                depth += 1
            elif tok.kind == 'sym' and tok.value in ')]>':
                if depth == 0:
                    break
                depth -= 1
            elif depth == 0 and tok.kind == 'sym' and tok.value in stop:
                break
            elif depth == 0 and tok.is_('keyword', 'record'):
                self.next()
                self.body('', 'record', tok)   # anonymous nested record
                parts.append('record')
                continue
            parts.append(tok.value)
            self.next()
        return ' '.join(parts).replace(' < ', '<').replace(' >', '>').replace(' ,', ',')

    # ---- top level -------------------------------------------------------------------------------------------
    def run(self) -> None:
        section = ''
        while not self.at('eof'):
            tok = self.peek()
            if tok.is_('keyword', 'type'):
                section = 'type'
                self.next()
            elif tok.kind == 'keyword' and tok.key in ('const', 'var') or tok.is_('ident', 'resourcestring') \
                    or tok.is_('ident', 'threadvar'):
                section = 'const' if tok.key in ('const', 'resourcestring') else 'var'
                self.next()
            elif tok.is_('ident', 'implementation'):
                return   # the interface section holds every declaration the scripts can see
            elif tok.kind == 'keyword' and tok.key in ROUTINE_KEYWORDS | {'begin', 'uses'}:
                section = ''
                self.skip_to_semicolon()
            elif section == 'type' and tok.kind == 'ident' and self.type_decl_start():
                self.type_decl()
            elif section == 'const' and tok.kind == 'ident' and (self.at('sym', '=', 1) or self.at('sym', ':', 1)):
                self.const_decl()
            else:
                self.next()

    def type_decl_start(self) -> bool:
        if self.at('sym', '=', 1):
            return True
        if self.at('sym', '<', 1):   # generic: Name<T, U> =
            k = 2
            while not self.at('eof', None, k) and not self.at('sym', '>', k):
                k += 1
            return self.at('sym', '=', k + 1)
        return False

    def type_decl(self) -> None:
        name_tok = self.next()
        if self.at('sym', '<'):
            while not self.at('sym', '>'):
                self.next()
            self.next()
        self.next()   # '='
        if self.at('ident', 'packed'):
            self.next()
        tok = self.peek()
        if tok.is_('keyword', 'class') or tok.is_('ident', 'interface') or tok.is_('keyword', 'record'):
            kind = 'interface' if tok.key == 'interface' else tok.key
            self.next()
            if self.at('ident', 'abstract') or self.at('ident', 'sealed'):
                self.next()
            if self.at('sym', ';'):
                self.next()   # forward declaration
                return
            if self.at('keyword', 'of'):
                self.skip_to_semicolon()   # class reference type
                return
            parent = ''
            if self.at('keyword', 'helper'):
                self.next()
                self.next()   # 'for'
                parent = self.next().value
                kind = 'helper'
            elif self.at('sym', '('):
                self.next()
                parent = self.type_text({',', ')'})
                while not self.at('sym', ')'):
                    self.next()
                self.next()
                if self.at('sym', ';'):
                    self.next()   # TFoo = class(TBar);  (no body)
                    self.table.add_type(TypeDecl(name_tok.value, kind, parent, name_tok.file, name_tok.line))
                    return
            if kind == 'interface' and self.at('sym', '['):
                while not self.at('sym', ']'):
                    self.next()
                self.next()
            self.body(name_tok.value, kind, name_tok, parent)
            if self.at('sym', ';'):
                self.next()
        elif tok.is_('sym', '('):
            self.enum_decl(name_tok)
        else:
            self.skip_to_semicolon()

    def enum_decl(self, name_tok: Token) -> None:
        self.next()   # '('
        values, ordinal = [], 0
        while not self.at('sym', ')'):
            val = self.next()
            if val.kind != 'ident':
                self.skip_to_semicolon()
                return
            if self.at('sym', '='):
                self.next()
                text = self.type_text({',', ')'})
                try:
                    ordinal = int(text.replace(' ', ''))
                except ValueError:
                    self.table.errors.append(f'{val.file}:{val.line}: enum value {val.value} = {text} not evaluated')
            values.append((val.value, ordinal))
            ordinal += 1
            if self.at('sym', ','):
                self.next()
        self.next()   # ')'
        self.skip_to_semicolon()
        self.table.add_enum(EnumDecl(name_tok.value, values, name_tok.file))

    def const_decl(self) -> None:
        name = self.next()
        typ = ''
        if self.at('sym', ':'):
            self.next()
            typ = self.type_text({'='})
        self.next()   # '='
        expr = self.skip_to_semicolon()
        self.table.add_const(name.value, typ, expr)

    # ---- class and record bodies -----------------------------------------------------------------------------
    def body(self, name: str, kind: str, at: Token, parent: str = '') -> None:
        decl = TypeDecl(name, kind, parent, at.file, at.line)
        vis = 'public' if kind in ('record', 'helper') else 'published'
        mode = 'field'   # 'field', 'const' or 'type' section inside the body
        while not self.at('eof'):
            tok = self.peek()
            if tok.is_('keyword', 'end'):
                self.next()
                break
            if tok.is_('ident', 'strict'):
                self.next()
                continue
            if tok.kind in ('ident', 'keyword') and tok.key in VISIBILITY:
                vis = tok.key
                mode = 'field'
                self.next()
                continue
            if tok.is_('sym', '['):   # attribute
                while not self.at('sym', ']'):
                    self.next()
                self.next()
                continue
            is_class = False
            if tok.is_('keyword', 'class') and (self.peek(1).key in ROUTINE_KEYWORDS | {'var', 'property'}
                                               or self.peek(1).is_('ident', 'threadvar')):
                is_class = True
                self.next()
                tok = self.peek()
            if tok.kind == 'keyword' and tok.key in ROUTINE_KEYWORDS:
                mode = 'field'
                decl.members.append(self.routine_header(vis, is_class))
            elif tok.is_('keyword', 'property'):
                mode = 'field'
                decl.members.append(self.property_decl(vis, is_class))
            elif tok.is_('keyword', 'const'):
                mode = 'const'
                self.next()
            elif tok.is_('keyword', 'var') or tok.is_('ident', 'threadvar'):
                mode = 'field'
                self.next()
            elif tok.is_('keyword', 'type'):
                mode = 'type'
                self.next()
            elif tok.is_('keyword', 'case'):   # variant record part: fields until the record's end
                self.next()
                self.skip_to_keyword_of()
            elif mode == 'type' and tok.kind == 'ident' and self.type_decl_start():
                self.type_decl()
            elif mode == 'const' and tok.kind == 'ident' and (self.at('sym', '=', 1) or self.at('sym', ':', 1)):
                cname = self.next()
                ctype = ''
                if self.at('sym', ':'):
                    self.next()
                    ctype = self.type_text({'='})
                self.next()
                self.skip_to_semicolon()
                decl.members.append(Member(cname.value, 'const', vis, ctype, is_class=True, line=cname.line))
            elif tok.kind == 'ident' and (self.at('sym', ',', 1) or self.at('sym', ':', 1)):
                names = [self.next()]
                while self.at('sym', ','):
                    self.next()
                    names.append(self.next())
                self.next()   # ':'
                ftype = self.type_text({';', '='})
                self.skip_to_semicolon()
                for n in names:
                    decl.members.append(Member(n.value, 'field', vis, ftype, is_class=is_class, line=n.line))
            elif self.at('sym', '(') or (tok.kind == 'int' and (self.at('sym', ',', 1) or self.at('sym', ':', 1))):
                # variant record case labels: '0: (fields);' - read the fields inside the parens
                while not self.at('sym', '('):
                    self.next()
                self.next()
                while not self.at('sym', ')') and not self.at('eof'):
                    if self.peek().kind == 'ident' and (self.at('sym', ',', 1) or self.at('sym', ':', 1)):
                        names = [self.next()]
                        while self.at('sym', ','):
                            self.next()
                            names.append(self.next())
                        self.next()
                        ftype = self.type_text({';', ')'})
                        for n in names:
                            decl.members.append(Member(n.value, 'field', vis, ftype, line=n.line))
                        if self.at('sym', ';'):
                            self.next()
                    else:
                        self.next()
                self.next()
                if self.at('sym', ';'):
                    self.next()
            else:
                self.next()
        if name:
            self.table.add_type(decl)

    def skip_to_keyword_of(self) -> None:
        while not self.at('eof') and not self.at('keyword', 'of'):
            self.next()
        self.next()

    def routine_header(self, vis: str, is_class: bool) -> Member:
        routine = self.next().key
        name_tok = self.next()
        name = name_tok.value
        if routine == 'operator' and name_tok.kind == 'ident':
            pass
        while self.at('sym', '.'):   # method resolution clause / qualified name
            self.next()
            name = self.next().value
        if self.at('sym', '<'):
            while not self.at('sym', '>'):
                self.next()
            self.next()
        params: list[Param] = []
        if self.at('sym', '('):
            self.next()
            while not self.at('sym', ')'):
                modifier = ''
                if self.peek().key in ('var', 'const', 'out') and self.peek(1).kind == 'ident':
                    modifier = self.next().key
                names = [self.next().value]
                while self.at('sym', ','):
                    self.next()
                    names.append(self.next().value)
                ptype, default = '', None
                if self.at('sym', ':'):
                    self.next()
                    ptype = self.type_text({';', '=', ')'})
                if self.at('sym', '='):
                    self.next()
                    default = self.type_text({';', ')'})
                for n in names:
                    params.append(Param(n, ptype, default, modifier))
                if self.at('sym', ';'):
                    self.next()
            self.next()   # ')'
        result = ''
        if self.at('sym', ':'):
            self.next()
            result = self.type_text({';'})
        self.skip_to_semicolon()
        # directives: 'override;', 'overload;', 'message WM_X;', 'deprecated 'text';'
        while self.peek().kind in ('ident', 'keyword') and self.peek().key in ROUTINE_DIRECTIVES:
            self.skip_to_semicolon()
        return Member(name, 'method', vis, result, routine, is_class, params, name_tok.line)

    def property_decl(self, vis: str, is_class: bool) -> Member:
        self.next()   # 'property'
        name_tok = self.next()
        if self.at('sym', '['):
            while not self.at('sym', ']'):
                self.next()
            self.next()
        ptype = ''
        if self.at('sym', ':'):
            self.next()
            ptype = self.type_text({';'})
            ptype = ptype.split(' read ')[0].split(' write ')[0].split(' index ')[0]
        self.skip_to_semicolon()
        if self.peek().is_('ident', 'default') and self.at('sym', ';', 1):
            self.skip_to_semicolon()
        return Member(name_tok.value, 'property', vis, ptype, is_class=is_class, line=name_tok.line)


class SymbolTable:
    """Everything declared in the scanned Delphi files, plus what the game exposes to scripts."""

    def __init__(self) -> None:
        self.types: dict[str, TypeDecl] = {}
        self.enums: dict[str, EnumDecl] = {}
        self.enum_values: dict[str, tuple[str, int, str]] = {}   # lower -> (spelling, ordinal, enum name)
        self.consts: dict[str, tuple[str, str, list[Token]]] = {}  # lower -> (spelling, type, expr tokens)
        self.exposed_classes: list[str] = []
        self.exposed_types: list[str] = []
        self.exposed_consts: list[str] = []
        self.exposed_functions: list[str] = []
        self.custom_classes: list[str] = []
        self.errors: list[str] = []

    # ---- building ----------------------------------------------------------------------------------------------
    def add_type(self, decl: TypeDecl) -> None:
        key = decl.name.lower()
        old = self.types.get(key)
        if old is None or (not old.members and decl.members and old.file == decl.file):
            for m in decl.members:
                m.owner = decl.name
            self.types[key] = decl

    def add_enum(self, decl: EnumDecl) -> None:
        if decl.name.lower() in self.enums:
            return
        self.enums[decl.name.lower()] = decl
        for value, ordinal in decl.values:
            self.enum_values.setdefault(value.lower(), (value, ordinal, decl.name))

    def add_const(self, name: str, typ: str, expr: list[Token]) -> None:
        self.consts.setdefault(name.lower(), (name, typ, expr))

    @classmethod
    def scan(cls, source_root: str) -> 'SymbolTable':
        table = cls()
        # System.TObject is not in the sources; these are the members of it that scripts use
        table.add_type(TypeDecl('TObject', 'class', '', 'System.pas', 0, [
            Member('Create', 'method', 'public', '', 'constructor'),
            Member('Free', 'method', 'public', '', 'procedure'),
            Member('ClassName', 'method', 'public', 'string', 'function', is_class=True)]))
        for folder in SCAN_FOLDERS:
            base = os.path.join(source_root, folder)
            for name in sorted(os.listdir(base)):
                path = os.path.join(base, name)
                if not name.lower().endswith('.pas') or not os.path.isfile(path):
                    continue
                text = _SERVER_ONLY_BLOCK.sub('', read_source(path))
                for kind, args in _EXPOSE.findall(text):
                    table._add_exposure(kind.lower(), args)
                if 'CustomExpose.Classes.Add' in text:
                    table._add_custom_classes(text, os.path.relpath(path, source_root))
                try:
                    toks = tokenize(text, os.path.relpath(path, source_root))
                except LexError as e:
                    table.errors.append(str(e))
                    continue
                toks = [t for t in toks if t.kind not in ('directive', 'marker')]
                _Scanner(toks, table).run()
        return table

    def _add_custom_classes(self, text: str, file: str) -> None:
        """Classes built by hand with `ScriptManager.CustomExpose.Classes.Add` (TBlackboard, TEventbus, RParam).
        They replace the Delphi class of the same name on the script side: scripts see only these methods."""
        for chunk in text.split('CustomExpose.Classes.Add')[1:]:
            chunk = re.split(r'\n\s*end;', chunk)[0]
            m = re.search(r"AClass\.Name\s*:=\s*(?:'(\w+)'|(\w+)\.ClassName)", chunk)
            if m is None:
                continue
            name = m.group(1) or m.group(2)
            line = text[:text.find(chunk)].count('\n') + 1
            decl = TypeDecl(name, 'custom', '', file, line)
            method = None
            for mm in re.finditer(r"Methods\.Add\('(\w+)'(?:\s*,\s*'([\w<>.]+)')?\)|"
                                  r"Parameters\.Add\('(\w+)'\s*,\s*'([\w<>.]+)'\)", chunk):
                if mm.group(1):
                    method = Member(mm.group(1), 'method', 'public', mm.group(2) or '', 'function' if mm.group(2)
                                    else 'procedure', line=line)
                    decl.members.append(method)
                elif method is not None:
                    method.params.append(Param(mm.group(3), mm.group(4)))
            for m in decl.members:
                m.owner = name
            self.custom_classes.append(name)
            self.types[name.lower()] = decl

    def _add_exposure(self, kind: str, args: str) -> None:
        if ':' in args:
            return   # the declaration of ExposeClass itself, not a registration
        if kind == 'class':
            self.exposed_classes.append(args.strip())
        elif kind == 'type':
            m = re.match(r'TypeInfo\((.*)\)$', args.strip(), re.I)
            self.exposed_types.append(m.group(1).strip() if m else args.strip())
        elif kind == 'constant':
            self.exposed_consts.append(args.split(',')[0].strip().strip("'"))
        elif kind == 'function':
            self.exposed_functions.append(args.split(',')[0].strip().strip("'"))

    # ---- queries -----------------------------------------------------------------------------------------------
    def ancestors(self, name: str) -> list[TypeDecl]:
        """The type and its ancestors, nearest first (only those that were scanned)."""
        out, seen = [], set()
        decl = self.types.get(name.lower())
        while decl is not None and decl.name.lower() not in seen:
            seen.add(decl.name.lower())
            out.append(decl)
            if decl.parent:   # a nested parent 'TOuter.TInner' is registered under 'TInner'
                decl = self.types.get(decl.parent.replace(' ', '').split('.')[-1].lower())
            elif decl.kind == 'class' and decl.name.lower() != 'tobject':
                decl = self.types.get('tobject')
            else:
                decl = None
        return out

    def script_members(self, type_name: str) -> dict[str, list[Member]]:
        """Members visible to scripts on a type: public/published members of it and its ancestors, helpers too."""
        found: dict[str, list[Member]] = {}
        for decl in self.ancestors(type_name):
            for m in decl.members:
                if m.visibility in ('public', 'published'):
                    found.setdefault(m.name.lower(), []).append(m)
        return found

    def exposed_type_names(self) -> list[str]:
        return self.exposed_classes + self.custom_classes + \
            [t for t in self.exposed_types if not t.lower().startswith('tarray')]
