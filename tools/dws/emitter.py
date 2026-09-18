"""GDScript emitter for parsed DWScript programs (see docs/scripts.md, "Transpiler decisions").

One call emits one script for one side. Every identifier is resolved: locals and parameters, then the script's
own globals and routines, then Math.dws (hand-ported: `L.`), then the enum values and constants the original
exposes (`C.`), then exposed classes and records, then DWScript built-ins. Members are checked against the
Delphi declarations (SymbolTable) and spelled like them. Anything unknown raises EmitError with file:line.

Static types are tracked as far as declarations tell them (lower-case Delphi type names). They decide
- `/` (always a float division in Pascal) versus `div`,
- `and`/`or`/`not` as boolean or bitwise operators,
- the spelling and kind (method or property) of a member,
- `X`/`Y`/`Z` on the vector records, which map to Godot's Vector2/Vector3.
"""
from __future__ import annotations

import json

from . import parser as ast
from .symbols import Member as SymMember
from .symbols import SymbolTable

LIB = 'L'        # preload alias of src/runtime/dws/dws_lib.gd (Math.dws port + DWScript built-ins)
CONST = 'C'      # preload alias of src/runtime/dws/dws_const.gd (generated enum values and constants)
LIB_PATH = 'res://src/runtime/dws/dws_lib.gd'
CONST_PATH = 'res://src/runtime/dws/dws_const.gd'

INT_TYPES = {'integer', 'byte', 'cardinal', 'int64', 'word', 'shortint', 'smallint', 'longint', 'uint64', 'nativeint'}
FLOAT_TYPES = {'single', 'float', 'double', 'real', 'extended'}
VECTOR_TYPES = {'rvector2': 'Vector2', 'rvector3': 'Vector3', 'rvector4': 'Vector4', 'rintvector2': 'Vector2i'}
VECTOR_FIELDS = {'x', 'y', 'z', 'w'}

# Math.dws, hand-ported in dws_lib.gd: script name (lower) -> (GDScript expression, result type)
MATH_FUNCS = {'s': ('s', 'string'), 'i': ('i', 'integer'), 'ii': ('ii', 'integer'), 'f': ('f', 'single'),
              'ff': ('ff', 'single'), 'rvector3add': ('RVector3Add', 'rvector3')}
MATH_CONSTS = {'allgroup': ('ALLGROUP', 'array'), 'rvector3zero': ('RVector3ZERO', 'rvector3')}
# record helpers of Math.dws: (type, method) -> (GDScript callee, result type)
RECORD_STATICS = {
    ('rvector2', 'create'): ('Vector2', 'rvector2'),
    ('rvector3', 'create'): ('Vector3', 'rvector3'),
    ('rintvector2', 'create'): ('Vector2i', 'rintvector2'),
    ('rvector3', 'getrandompointinsphere'): (LIB + '.RVector3_getRandomPointInSphere', 'rvector3'),
    ('rvariedsingle', 'create'): (LIB + '.RVariedSingle_Create', 'rvariedsingle'),
    ('rvariedvector3', 'create'): (LIB + '.RVariedVector3_Create', 'rvariedvector3'),
    ('rvariedvector3', 'createradialvaried'): (LIB + '.RVariedVector3_CreateRadialVaried', 'rvariedvector3'),
}
RECORD_METHODS = {   # Math.dws record helper methods on values
    ('rvector3', 'setx'): 'RVector3_SetX', ('rvector3', 'sety'): 'RVector3_SetY',
    ('rvector3', 'setz'): 'RVector3_SetZ', ('rvector3', 'iszerovector'): 'RVector3_isZeroVector',
    ('rvariedvector3', 'getrandomvector'): 'RVariedVector3_getRandomVector',
}

# DWScript built-in functions: lower name -> (GDScript callee, result type or None = type of first argument)
BUILTINS = {
    'random': (LIB + '.Random', 'float'),
    'round': (LIB + '.Round', 'integer'),
    'trunc': (LIB + '.Trunc', 'integer'),
    'inttostr': ('str', 'string'),
    'floattostr': (LIB + '.FloatToStr', 'string'),
    'sin': ('sin', 'float'), 'cos': ('cos', 'float'), 'tan': ('tan', 'float'),
    'sqrt': ('sqrt', 'float'), 'power': ('pow', 'float'), 'exp': ('exp', 'float'),
    'abs': ('abs', None), 'min': ('min', None), 'max': ('max', None), 'clamp': ('clamp', None),
    'assigned': (LIB + '.Assigned', 'boolean'),
    'assert': (LIB + '.Assert', 'void'),
    'length': (LIB + '.Length', 'integer'),
}
BUILTIN_CONSTS = {'pi': ('PI', 'float'), 'true': ('true', 'boolean'), 'false': ('false', 'boolean')}

# names a script identifier must not take in GDScript (exact, case-sensitive): keywords, built-in types, aliases
GD_RESERVED = {
    'if', 'elif', 'else', 'for', 'while', 'match', 'when', 'break', 'continue', 'pass', 'return', 'class',
    'class_name', 'extends', 'is', 'in', 'as', 'self', 'super', 'signal', 'func', 'static', 'const', 'enum', 'var',
    'breakpoint', 'preload', 'await', 'yield', 'assert', 'void', 'PI', 'TAU', 'INF', 'NAN', 'not', 'and', 'or',
    'true', 'false', 'null', 'bool', 'int', 'float', 'String', 'StringName', 'NodePath', 'Vector2', 'Vector2i',
    'Vector3', 'Vector3i', 'Vector4', 'Vector4i', 'Rect2', 'Rect2i', 'Transform2D', 'Transform3D', 'Plane',
    'Quaternion', 'AABB', 'Basis', 'Projection', 'Color', 'RID', 'Object', 'Callable', 'Signal', 'Dictionary',
    'Array', 'Variant', LIB, CONST, 'free', 'get', 'set', 'call', 'notification', 'get_class', 'is_class',
}

PASCAL_TO_GD_OP = {'=': '==', '<>': '!=', '<': '<', '>': '>', '<=': '<=', '>=': '>=', '+': '+', '-': '-',
                   '*': '*', 'mod': '%', 'shl': '<<', 'shr': '>>', 'in': 'in', 'is': 'is'}


class EmitError(Exception):
    pass


def gd_name(name: str) -> str:
    return name + '_' if name in GD_RESERVED else name


def gd_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


class _Var:
    def __init__(self, name: str, typ: str | None, kind: str = 'var'):
        self.name = name      # declared spelling
        self.type = typ       # lower-case Delphi type ('array of integer' for arrays) or None
        self.kind = kind      # 'var', 'const', 'param', 'result'


class Emitter:
    def __init__(self, symbols: SymbolTable, script_path: str, side: str):
        self.sym = symbols
        self.script_path = script_path   # relative to Scripts/, as in the original ('Units\\Black\\X.ets')
        self.side = side
        self.lines: list[str] = []
        self.globals: dict[str, _Var] = {}
        self.routines: dict[str, ast.Routine] = {}
        self.locals: dict[str, _Var] = {}
        self.routine: ast.Routine | None = None
        self.includes_math = False
        self.markers: list[str] = []
        self.for_depth = 0
        self.exposed_classes = {c.lower() for c in symbols.exposed_classes + symbols.custom_classes}
        self.exposed_types = {t.lower() for t in symbols.exposed_types}
        self.exposed_consts = {c.lower() for c in symbols.exposed_consts}
        self.used_classes: set[str] = set()   # canonical names of Delphi types the output references
        # (declaring type, member, 'call'/'read'/'write'); declaring type '? A/B' when the receiver's type is unknown
        self.used_members: set[tuple[str, str, str]] = set()

    # ---- helpers -----------------------------------------------------------------------------------------------
    def error(self, msg: str, tok) -> EmitError:
        return EmitError(f'{tok.file}:{tok.line}: {msg}')

    def type_of_ref(self, ref: ast.TypeRef | None) -> str | None:
        if ref is None:
            return None
        if ref.name == 'array':
            return 'array of ' + (self.type_of_ref(ref.of) or '?')
        return ref.name.lower()

    @staticmethod
    def norm_type(delphi: str) -> str | None:
        """A type as written in a Delphi declaration -> the emitter's notation ('TArray<Byte>' -> 'array of byte')."""
        t = delphi.replace(' ', '').lower().replace('system.', '')
        if not t:
            return None
        if t.startswith('tarray<') and t.endswith('>'):
            return 'array of ' + (Emitter.norm_type(t[7:-1]) or '?')
        if t.startswith('arrayof'):
            return 'array of ' + (Emitter.norm_type(t[7:]) or '?')
        return t

    def gd_type(self, typ: str | None) -> str:
        """Type hint for a declared variable; only value types get one (they need Pascal's conversions)."""
        if typ is None:
            return ''
        if typ in INT_TYPES or typ in self.sym.enums:
            return 'int'
        if typ in FLOAT_TYPES:
            return 'float'
        if typ == 'boolean':
            return 'bool'
        if typ == 'string':
            return 'String'
        if typ in VECTOR_TYPES:
            return VECTOR_TYPES[typ]
        if typ.startswith('array of') or typ.startswith('set'):
            return 'Array'
        return ''

    def default_value(self, typ: str | None) -> str:
        hint = self.gd_type(typ)
        return {'int': '0', 'float': '0.0', 'bool': 'false', 'String': '""', 'Array': '[]', 'Vector2': 'Vector2()',
                'Vector3': 'Vector3()', 'Vector4': 'Vector4()', 'Vector2i': 'Vector2i()'}.get(hint, 'null')

    def is_int(self, typ: str | None) -> bool:
        return typ is not None and (typ in INT_TYPES or typ in self.sym.enums)

    def is_float(self, typ: str | None) -> bool:
        return typ is not None and typ in FLOAT_TYPES

    def is_numeric(self, typ: str | None) -> bool:
        return self.is_int(typ) or self.is_float(typ)

    def class_name(self, key: str, tok) -> str:
        decl = self.sym.types.get(key)
        if decl is None:
            raise self.error(f'unknown type {key}', tok)
        if key not in self.exposed_classes and key not in self.exposed_types:
            raise self.error(f'type {decl.name} is not exposed to scripts', tok)
        self.used_classes.add(decl.name)
        return decl.name

    # ---- program -----------------------------------------------------------------------------------------------
    def emit(self, program: ast.Program) -> str:
        self.includes_math = program.includes_math
        for decl in program.decls:
            if isinstance(decl, ast.Routine):
                key = decl.name.lower()
                if key in self.routines or key in self.globals:
                    raise self.error(f'{decl.name} declared twice', decl.tok)
                self.routines[key] = decl
            else:
                for name in decl.names:
                    if name.lower() in self.globals or name.lower() in self.routines:
                        raise self.error(f'{name} declared twice', decl.tok)
                    typ = self.type_of_ref(decl.type)
                    if typ is None and decl.value is not None:
                        typ = self.type_of(decl.value)
                    self.globals[name.lower()] = _Var(name, typ, 'const' if decl.is_const else 'var')
        out = [f'# Generated by tools/transpile_scripts.py from Scripts\\{self.script_path} ({self.side}).',
               '# Do not edit: change the transpiler and regenerate.', 'extends RefCounted', '',
               f'const {CONST} = preload("{CONST_PATH}")', f'const {LIB} = preload("{LIB_PATH}")', '']
        for decl in program.decls:
            if isinstance(decl, ast.VarDecl):
                out.extend(self.global_decl(decl))
        for decl in program.decls:
            if isinstance(decl, ast.Routine):
                out.append('')
                out.extend(self.routine_decl(decl))
        return '\n'.join(out) + '\n'

    def global_decl(self, decl: ast.VarDecl) -> list[str]:
        lines = []
        for name in decl.names:
            var = self.globals[name.lower()]
            value = self.coerce(decl.value, var.type) if decl.value is not None else self.default_value(var.type)
            hint = self.gd_type(var.type)
            lines.append(f'var {gd_name(name)}{": " + hint if hint else ""} = {value}{self.trail(decl.tok)}')
        return lines

    def trail(self, tok, with_file: bool = True) -> str:
        where = f'{tok.file}:{tok.line}' if with_file else str(tok.line)
        markers = ''.join(f' {{@{m}}}' for m in self.markers)
        self.markers = []
        return f'  # {where}{markers}'

    def routine_decl(self, r: ast.Routine) -> list[str]:
        self.routine = r
        self.locals = {}
        params = []
        for p in r.params:
            if p.modifier in ('var', 'out'):
                raise self.error(f'{p.modifier} parameters are not supported ({p.name})', r.tok)
            typ = self.type_of_ref(p.type)
            self.declare_local(p.name, typ, 'param', r.tok)
            hint = self.gd_type(typ)
            text = gd_name(p.name) + (': ' + hint if hint else '')
            if p.default is not None:
                text += ' = ' + self.coerce(p.default, typ)
            params.append(text)
        self.markers = []
        head = f'func {gd_name(r.name)}({", ".join(params)})'
        lines = [f'# {r.tok.file}:{r.tok.line}', head + (' -> void:' if r.result is None else ':')]
        body: list[str] = []
        if r.result is not None:
            rtype = self.type_of_ref(r.result)
            self.declare_local('Result', rtype, 'result', r.tok)
            hint = self.gd_type(rtype)
            body.append(f'var Result{": " + hint if hint else ""} = {self.default_value(rtype)}')
        for decl in r.locals:
            typ = self.type_of_ref(decl.type)
            if typ is None and decl.value is not None:
                typ = self.type_of(decl.value)
            for name in decl.names:
                self.declare_local(name, typ, 'const' if decl.is_const else 'var', decl.tok)
                value = self.coerce(decl.value, typ) if decl.value is not None else self.default_value(typ)
                hint = self.gd_type(typ)
                body.append(f'var {gd_name(name)}{": " + hint if hint else ""} = {value}'
                            + self.trail(decl.tok, False))
        for stmt in r.body.body:
            body.extend(self.stmt(stmt))
        if r.result is not None:
            body.append('return Result')
        if not body:
            body.append('pass')
        lines.extend('\t' + line for line in body)
        self.routine = None
        return lines

    def declare_local(self, name: str, typ: str | None, kind: str, tok) -> None:
        if name.lower() in self.locals:
            raise self.error(f'{name} declared twice', tok)
        self.locals[name.lower()] = _Var(name, typ, kind)

    # ---- statements ------------------------------------------------------------------------------------------
    def block(self, stmt: ast.Stmt | None) -> list[str]:
        lines = self.stmt(stmt) if stmt is not None else []
        return ['\t' + line for line in (lines or ['pass'])]

    def stmt(self, s: ast.Stmt | None) -> list[str]:
        if s is None:
            return []
        if isinstance(s, ast.Block):
            out = []
            for inner in s.body:
                out.extend(self.stmt(inner))
            return out
        if isinstance(s, ast.Assign):
            return [self.assign(s)]
        if isinstance(s, ast.CallStmt):
            code = self.call_statement(s.expr)
            return [code + self.trail(s.tok, False)]
        if isinstance(s, ast.If):
            cond = self.condition(s.cond)
            out = [f'if {cond}:{self.trail(s.tok, False)}'] + self.block(s.then)
            else_ = s.else_
            while isinstance(else_, ast.If):
                cond = self.condition(else_.cond)
                out += [f'elif {cond}:{self.trail(else_.tok, False)}'] + self.block(else_.then)
                else_ = else_.else_
            if else_ is not None:
                out += ['else:'] + self.block(else_)
            return out
        if isinstance(s, ast.While):
            cond = self.condition(s.cond)
            return [f'while {cond}:{self.trail(s.tok, False)}'] + self.block(s.body)
        if isinstance(s, ast.For):
            var = self.locals.get(s.var.lower())
            if var is None or var.kind not in ('var',):
                raise self.error(f'for loop variable {s.var} must be a local variable', s.tok)
            start = self.expr(s.start)[0]
            stop = self.expr(s.stop)[0]
            loop = f'_for_{var.name}'
            rng = f'range({start}, ({stop}) - 1, -1)' if s.downto else f'range({start}, ({stop}) + 1)'
            head = f'for {loop} in {rng}:{self.trail(s.tok, False)}'
            return [head, f'\t{gd_name(var.name)} = {loop}'] + self.block(s.body)
        raise self.error(f'unsupported statement {type(s).__name__}', s.tok)

    def condition(self, e: ast.Expr) -> str:
        code, typ = self.expr(e)
        return code

    def assign(self, s: ast.Assign) -> str:
        target = s.target
        # 'FunctionName := x' inside that function is the old spelling of 'Result := x'
        if isinstance(target, ast.Name) and self.routine is not None and self.routine.result is not None \
                and target.name.lower() == self.routine.name.lower() and target.name.lower() not in self.locals:
            target = ast.Name(target.tok, 'Result')
        code, ttype = self.expr(target, as_target=True)
        value = self.coerce(s.value, ttype)
        op = '=' if s.op == ':=' else s.op
        if op == '/=' and not self.is_float(ttype):
            raise self.error('/= on a non-float target', s.tok)
        return f'{code} {op} {value}{self.trail(s.tok, False)}'

    def call_statement(self, e: ast.Expr) -> str:
        if isinstance(e, ast.Call):
            return self.expr(e)[0]
        code, typ = self.expr(e, want_call=True)
        return code

    # ---- expressions -----------------------------------------------------------------------------------------
    def type_of(self, e: ast.Expr) -> str | None:
        saved = self.markers
        try:
            return self.expr(e)[1]
        finally:
            self.markers = saved

    def expr(self, e: ast.Expr, as_target: bool = False, want_call: bool = False) -> tuple[str, str | None]:
        """Returns (GDScript code, lower-case Delphi type or None). Meta types (a class used as a value) are
        returned as 'meta:<name>'."""
        if isinstance(e, ast.Marked):
            self.markers.append(e.marker)
            return self.expr(e.expr, as_target, want_call)
        if isinstance(e, ast.Literal):
            if e.kind == 'string':
                return gd_string(e.value), 'string'
            return e.value, ('integer' if e.kind == 'int' else 'float')
        if isinstance(e, ast.Nil):
            return 'null', 'nil'
        if isinstance(e, ast.Name):
            return self.name(e, as_target, want_call)
        if isinstance(e, ast.Member):
            return self.member(e, [], False, want_call, as_target)
        if isinstance(e, ast.Call):
            return self.call(e)
        if isinstance(e, ast.Index):
            obj, otype = self.expr(e.obj)
            code = obj + ''.join(f'[{self.expr(i)[0]}]' for i in e.indices)
            etype = None
            if otype and otype.startswith('array of '):
                etype = otype[len('array of '):]
                for _ in e.indices[1:]:
                    etype = etype[len('array of '):] if etype.startswith('array of ') else None
            elif otype == 'string':
                etype = 'string'
            return code, etype
        if isinstance(e, ast.SetLiteral):
            items = []
            item_types = set()
            for item in e.items:
                if isinstance(item, ast.Range):
                    raise self.error('ranges in set literals are not supported', item.tok)
                code, typ = self.expr(item)
                items.append(code)
                item_types.add(typ)
            elem = item_types.pop() if len(item_types) == 1 else None
            return '[' + ', '.join(items) + ']', 'array of ' + (elem or '?')
        if isinstance(e, ast.Unary):
            code, typ = self.expr(e.operand)
            code = self.paren(e.operand, code)
            if e.op == 'not':
                return (f'~{code}', typ) if self.is_int(typ) else (f'not {code}', 'boolean')
            return (f'-{code}' if e.op == '-' else code), typ
        if isinstance(e, ast.Binary):
            return self.binary(e)
        if isinstance(e, ast.Cast):
            code, _ = self.expr(e.expr)
            name = self.class_name(e.type.lower(), e.tok)
            return f'({self.paren(e.expr, code)} as {name})', e.type.lower()
        raise self.error(f'unsupported expression {type(e).__name__}', e.tok)

    def coerce(self, e: ast.Expr, target: str | None) -> str:
        """Code for e as a value of the declared type target: integer literals become floats where Pascal would
        convert them (GDScript keeps an int in an untyped array or parameter)."""
        inner = e.expr if isinstance(e, ast.Marked) else e
        if isinstance(e, ast.Marked):
            self.markers.append(e.marker)
        if self.is_float(target):
            if isinstance(inner, ast.Literal) and inner.kind == 'int':
                return inner.value + '.0'
            if isinstance(inner, ast.Unary) and inner.op == '-' and isinstance(inner.operand, ast.Literal) \
                    and inner.operand.kind == 'int':
                return '-' + inner.operand.value + '.0'
        if target and target.startswith('array of ') and isinstance(inner, ast.SetLiteral) \
                and not any(isinstance(i, ast.Range) for i in inner.items):
            elem = target[len('array of '):]
            return '[' + ', '.join(self.coerce(i, elem) for i in inner.items) + ']'
        return self.expr(inner)[0]

    def paren(self, e: ast.Expr, code: str) -> str:
        inner = e.expr if isinstance(e, ast.Marked) else e
        return f'({code})' if isinstance(inner, (ast.Binary, ast.Unary)) else code

    def binary(self, e: ast.Binary) -> tuple[str, str | None]:
        left, ltype = self.expr(e.left)
        right, rtype = self.expr(e.right)
        left, right = self.paren(e.left, left), self.paren(e.right, right)
        op = e.op
        if op == '/':
            if not (self.is_float(ltype) or self.is_float(rtype)):
                left = f'float({left})'
            return f'{left} / {right}', 'float'
        if op == 'div':
            return f'{LIB}.Div({left}, {right})', 'integer'
        if op in ('and', 'or', 'xor'):
            if self.is_int(ltype) and self.is_int(rtype):
                return f'{left} {dict(and_="&", or_="|", xor_="^")[op + "_"]} {right}', 'integer'
            if op == 'xor':
                return f'{left} != {right}', 'boolean'
            return f'{left} {op} {right}', 'boolean'
        if op in ('=', '<>', '<', '>', '<=', '>=', 'in', 'is'):
            if op == 'is':
                name = self.class_name(e.right.name.lower(), e.tok) if isinstance(e.right, ast.Name) else None
                if name is None:
                    raise self.error('is needs a class name', e.tok)
                return f'{left} is {name}', 'boolean'
            return f'{left} {PASCAL_TO_GD_OP[op]} {right}', 'boolean'
        if op in ('+', '-', '*', 'mod', 'shl', 'shr'):
            if (ltype or '').startswith('array of') or (rtype or '').startswith('array of'):
                if op == '+' and isinstance(e.right, ast.SetLiteral) and (ltype or '').startswith('array of') \
                        and not isinstance(e.left, ast.SetLiteral):
                    return f'{left} + {self.coerce(e.right, ltype)}', ltype   # dynamic array concatenation
                raise self.error(f'set operator {op} is not supported', e.tok)
            if ltype == 'string' or rtype == 'string':
                typ = 'string'
            elif self.is_float(ltype) or self.is_float(rtype):
                typ = 'float'
            elif self.is_int(ltype) and self.is_int(rtype):
                typ = 'integer'
            elif ltype in VECTOR_TYPES and ltype == rtype:
                typ = ltype
            else:
                typ = None
            return f'{left} {PASCAL_TO_GD_OP[op]} {right}', typ
        raise self.error(f'unsupported operator {op}', e.tok)

    # ---- names -----------------------------------------------------------------------------------------------
    def name(self, e: ast.Name, as_target: bool = False, want_call: bool = False, args: list | None = None,
             has_parens: bool = False) -> tuple[str, str | None]:
        key = e.name.lower()
        var = self.locals.get(key)
        if var is not None:
            return gd_name(var.name), var.type
        var = self.globals.get(key)
        if var is not None:
            if as_target and var.kind == 'const':
                raise self.error(f'assignment to constant {var.name}', e.tok)
            return gd_name(var.name), var.type
        if as_target:
            raise self.error(f'unknown variable {e.name}', e.tok)
        routine = self.routines.get(key)
        if routine is not None:
            code = gd_name(routine.name) + '(' + ', '.join(self.args(args or [], routine, e.tok)) + ')'
            return code, self.type_of_ref(routine.result)
        if self.includes_math and key in MATH_FUNCS:
            fname, rtype = MATH_FUNCS[key]
            first = {'f': 'array of single', 'ff': 'array of array of single'}.get(key)
            codes = [self.coerce(a, first if n == 0 else None) for n, a in enumerate(args or [])]
            return f'{LIB}.{fname}(' + ', '.join(codes) + ')', rtype
        if self.includes_math and key in MATH_CONSTS and not has_parens:
            cname, ctype = MATH_CONSTS[key]
            return f'{LIB}.{cname}', ctype
        if key in self.sym.enum_values and not has_parens:
            spelling, _, enum = self.sym.enum_values[key]
            if enum.lower() not in self.exposed_types:
                raise self.error(f'enum value {spelling} of {enum}, which is not exposed', e.tok)
            return f'{CONST}.{spelling}', enum.lower()
        if key in self.exposed_consts and not has_parens:
            spelling, typ, _ = self.sym.consts[key]
            return f'{CONST}.{spelling}', self.const_type(key)
        if key in BUILTIN_CONSTS and not has_parens:
            return BUILTIN_CONSTS[key]
        if key in BUILTINS:
            callee, rtype = BUILTINS[key]
            codes = [self.expr(a) for a in args or []]
            if rtype is None:
                rtype = codes[0][1] if codes else None
                if key in ('min', 'max') and any(self.is_float(t) for _, t in codes):
                    rtype = 'float'
            return f'{callee}(' + ', '.join(c for c, _ in codes) + ')', rtype
        if key == 'game' and 'game' in {f.lower() for f in self.sym.exposed_functions}:
            if args:
                raise self.error('Game takes no arguments', e.tok)
            return f'{LIB}.Game()', 'tgame'
        if key in self.sym.types:
            return self.class_name(key, e.tok), 'meta:' + key
        raise self.error(f'unknown identifier {e.name}', e.tok)

    def const_type(self, key: str) -> str | None:
        _, typ, expr = self.sym.consts[key]
        if typ:
            return typ.lower()
        if len(expr) == 1:
            return {'int': 'integer', 'float': 'float', 'string': 'string'}.get(expr[0].kind)
        if len(expr) == 2 and expr[0].is_('sym', '-'):
            return {'int': 'integer', 'float': 'float'}.get(expr[1].kind)
        return None

    def args(self, args: list[ast.Expr], routine: ast.Routine, tok) -> list[str]:
        required = sum(1 for p in routine.params if p.default is None)
        if not required <= len(args) <= len(routine.params):
            raise self.error(f'{routine.name} takes {required}-{len(routine.params)} arguments, got {len(args)}', tok)
        return [self.coerce(a, self.type_of_ref(p.type)) for a, p in zip(args, routine.params)]

    def call(self, e: ast.Call) -> tuple[str, str | None]:
        func = e.func
        if isinstance(func, ast.Name):
            return self.name(func, args=e.args, has_parens=True)
        if isinstance(func, ast.Member):
            return self.member(func, e.args, True, True)
        raise self.error('unsupported call target', e.tok)

    # ---- members ---------------------------------------------------------------------------------------------
    def member(self, e: ast.Member, args: list[ast.Expr], has_parens: bool, want_call: bool,
               as_target: bool = False) -> tuple[str, str | None]:
        key = e.name.lower()
        obj, otype = self.expr(e.obj)
        if otype is not None and otype.startswith('meta:'):
            return self.static_member(e, otype[5:], obj, args, has_parens)
        if otype in VECTOR_TYPES and key in VECTOR_FIELDS and not has_parens:
            return f'{obj}.{key}', 'integer' if otype == 'rintvector2' else 'single'
        if otype is not None and (otype.split('.')[0], key) in RECORD_METHODS:
            fname = RECORD_METHODS[(otype, key)]
            rtype = 'boolean' if key == 'iszerovector' else 'rvector3'
            return f'{LIB}.{fname}(' + ', '.join([obj] + [self.expr(a)[0] for a in args]) + ')', rtype
        candidates = self.lookup_member(otype, key, e.tok)
        spellings = {m.name for m in candidates}
        kinds = {m.kind for m in candidates}
        if len(spellings) > 1:
            raise self.error(f'member {e.name} is spelled {sorted(spellings)} on different types; receiver type '
                             f'{otype or "unknown"}', e.tok)
        if len(kinds) > 1:
            raise self.error(f'member {e.name} is a {sorted(kinds)} on different types; receiver type '
                             f'{otype or "unknown"}', e.tok)
        spelling, kind = spellings.pop(), kinds.pop()
        owner = candidates[0].owner if otype in self.sym.types else \
            '? ' + '/'.join(sorted({m.owner for m in candidates}))
        use = 'write' if as_target else 'call' if kind == 'method' else 'read'
        self.used_members.add((owner, spelling, use))
        obj = self.paren(e.obj, obj) if not isinstance(e.obj, (ast.Name, ast.Member, ast.Call, ast.Index)) else obj
        if kind == 'method':
            if as_target:
                raise self.error(f'assignment to method {spelling}', e.tok)
            code_args = self.member_args(candidates, args, e.tok)
            rtype = self.result_type(candidates, len(args))
            return f'{obj}.{spelling}(' + ', '.join(code_args) + ')', rtype
        if has_parens:
            raise self.error(f'{spelling} is a {kind}, not a method', e.tok)
        types = {self.norm_type(m.type) for m in candidates}
        return f'{obj}.{spelling}', types.pop() if len(types) == 1 else None

    @staticmethod
    def fitting(candidates: list[SymMember], argc: int) -> list[SymMember]:
        return [m for m in candidates if m.kind == 'method'
                and sum(1 for p in m.params if p.default is None) <= argc <= len(m.params)]

    def member_args(self, candidates: list[SymMember], args: list[ast.Expr], tok) -> list[str]:
        fitting = self.fitting(candidates, len(args))
        if not fitting:
            counts = sorted({len(m.params) for m in candidates})
            raise self.error(f'{candidates[0].name} takes {counts} arguments, got {len(args)}', tok)
        out = []
        for idx, a in enumerate(args):
            types = {self.norm_type(m.params[idx].type) for m in fitting}
            out.append(self.coerce(a, types.pop() if len(types) == 1 else None))
        return out

    def result_type(self, candidates: list[SymMember], argc: int) -> str | None:
        types = {self.norm_type(m.type) for m in (self.fitting(candidates, argc) or candidates)}
        return types.pop() if len(types) == 1 else None

    def lookup_member(self, otype: str | None, key: str, tok) -> list[SymMember]:
        if otype is not None and otype in self.sym.types:
            found = self.sym.script_members(otype).get(key)
            if not found:
                decl = self.sym.types[otype]
                raise self.error(f'{decl.name} has no public member {key}', tok)
            return found
        if otype is not None and not otype.startswith('array of') and otype not in ('nil',) \
                and otype not in self.sym.enums and not self.is_numeric(otype) and otype != 'string':
            raise self.error(f'member {key} on unknown type {otype}', tok)
        found = self.any_member(key)
        if not found:
            raise self.error(f'no exposed type has a member {key}', tok)
        return found

    def any_member(self, key: str) -> list[SymMember]:
        if not hasattr(self.sym, '_member_index'):
            index: dict[str, list[SymMember]] = {}
            for name in self.sym.exposed_type_names():
                for mkey, members in self.sym.script_members(name).items():
                    index.setdefault(mkey, []).extend(members)
            self.sym._member_index = index
        return self.sym._member_index.get(key, [])

    def static_member(self, e: ast.Member, type_key: str, obj: str, args: list[ast.Expr],
                      has_parens: bool) -> tuple[str, str | None]:
        key = e.name.lower()
        if (type_key, key) in RECORD_STATICS:
            callee, rtype = RECORD_STATICS[(type_key, key)]
            return f'{callee}(' + ', '.join(self.expr(a)[0] for a in args) + ')', rtype
        members = self.sym.script_members(type_key).get(key)
        if not members:
            raise self.error(f'{obj} has no public member {e.name}', e.tok)
        m = members[0]
        self.used_members.add((m.owner, m.name, 'call' if m.kind == 'method' else 'read'))
        if m.kind == 'method' and m.routine == 'constructor':
            # a constructor runs on a new instance of the class it is called on, even if an ancestor declares it
            members = [c for c in members if c.routine == 'constructor' and c.name == m.name]
            code_args = ', '.join(self.member_args(members, args, e.tok))
            return f'{obj}.new().{m.name}({code_args})', type_key
        if m.kind == 'method' and m.is_class:
            code_args = ', '.join(self.member_args(members, args, e.tok))
            return f'{obj}.{m.name}({code_args})', self.result_type(members, len(args))
        if m.kind in ('const',) or (m.is_class and not has_parens):
            return f'{obj}.{m.name}', self.norm_type(m.type)
        raise self.error(f'{obj}.{m.name} is not a constructor, class method or constant', e.tok)
