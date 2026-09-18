"""Parser for the DWScript subset the original game's scripts use (see docs/scripts.md).

Input: the preprocessed token list (tools/dws/preprocess.py). Output: an AST of dataclasses. Anything outside the
subset raises ParseError with file:line; nothing is skipped silently. Declarations that come from
`HelperScripts/Math.dws` are not parsed: that file is hand-ported (src/runtime/dws_math.gd) and the parser only
records that the script included it.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .lexer import Token

MATH_FILE = 'helperscripts\\math.dws'


class ParseError(Exception):
    pass


# ---- expressions ----------------------------------------------------------------------------------------------
@dataclass
class Expr:
    tok: Token


@dataclass
class Literal(Expr):
    kind: str        # 'int', 'float', 'string'
    value: str


@dataclass
class Marked(Expr):
    marker: str      # balance marker in front of a value ({@UBL_Health} 100): semantically a comment
    expr: Expr


@dataclass
class Name(Expr):
    name: str


@dataclass
class Nil(Expr):
    pass


@dataclass
class Member(Expr):
    obj: Expr
    name: str


@dataclass
class Call(Expr):
    func: Expr
    args: list[Expr]


@dataclass
class Index(Expr):
    obj: Expr
    indices: list[Expr]


@dataclass
class SetLiteral(Expr):
    items: list[Expr]


@dataclass
class Range(Expr):
    low: Expr
    high: Expr


@dataclass
class Unary(Expr):
    op: str          # 'not', '-', '+'
    operand: Expr


@dataclass
class Binary(Expr):
    op: str          # lower-case Pascal operator: '+', 'div', 'and', '=', '<>', 'in', ...
    left: Expr
    right: Expr


@dataclass
class Cast(Expr):
    expr: Expr
    type: str


# ---- statements -----------------------------------------------------------------------------------------------
@dataclass
class Stmt:
    tok: Token


@dataclass
class Block(Stmt):
    body: list[Stmt]


@dataclass
class Assign(Stmt):
    target: Expr
    op: str          # ':=', '+=', '-=', '*=', '/='
    value: Expr


@dataclass
class CallStmt(Stmt):
    expr: Expr


@dataclass
class If(Stmt):
    cond: Expr
    then: Stmt | None
    else_: Stmt | None


@dataclass
class For(Stmt):
    var: str
    start: Expr
    stop: Expr
    downto: bool
    body: Stmt | None


@dataclass
class While(Stmt):
    cond: Expr
    body: Stmt | None


# ---- declarations ---------------------------------------------------------------------------------------------
@dataclass
class TypeRef:
    name: str            # 'integer', 'TEntity', ... or 'array' for dynamic/static arrays
    of: 'TypeRef | None' = None
    dims: list[tuple[Expr, Expr]] = field(default_factory=list)

    def __str__(self) -> str:
        if self.name == 'array':
            return 'array of ' + str(self.of)
        return self.name


@dataclass
class VarDecl:
    tok: Token
    names: list[str]
    type: TypeRef | None
    value: Expr | None
    is_const: bool = False


@dataclass
class Param:
    name: str
    type: TypeRef | None
    default: Expr | None
    modifier: str        # '', 'var', 'const', 'out'


@dataclass
class Routine:
    tok: Token
    kind: str            # 'procedure', 'function'
    name: str
    params: list[Param]
    result: TypeRef | None
    locals: list[VarDecl]
    body: Block


@dataclass
class Program:
    decls: list          # VarDecl and Routine, in source order (includes inlined)
    includes_math: bool


class Parser:
    def __init__(self, tokens: list[Token]):
        self.includes_math = any(t.file.lower().endswith(MATH_FILE) for t in tokens)
        self.t = [t for t in tokens if t.kind == 'eof' or not t.file.lower().endswith(MATH_FILE)]
        self.i = 0

    # ---- token helpers ---------------------------------------------------------------------------------------
    def peek(self, k: int = 0) -> Token:
        return self.t[min(self.i + k, len(self.t) - 1)]

    def at(self, kind: str, key: str | None = None, k: int = 0) -> bool:
        return self.peek(k).is_(kind, key)

    def at_kw(self, *keys: str) -> bool:
        return self.peek().kind == 'keyword' and self.peek().key in keys

    def at_sym(self, *syms: str) -> bool:
        return self.peek().kind == 'sym' and self.peek().value in syms

    def next(self) -> Token:
        tok = self.peek()
        self.i += 1
        return tok

    def error(self, msg: str, tok: Token | None = None):
        tok = tok or self.peek()
        return ParseError(f'{tok.file}:{tok.line}: {msg} (at {tok.value!r})')

    def expect(self, kind: str, key: str | None = None) -> Token:
        if not self.at(kind, key):
            raise self.error(f'expected {key or kind}')
        return self.next()

    def ident(self) -> Token:
        if self.peek().kind != 'ident':
            raise self.error('expected identifier')
        return self.next()

    def skip_semicolons(self) -> None:
        while self.at('sym', ';'):
            self.next()

    # ---- program ---------------------------------------------------------------------------------------------
    def parse_program(self) -> Program:
        decls: list = []
        self.skip_semicolons()
        while not self.at('eof'):
            if self.at_kw('var'):
                self.next()
                decls.extend(self.var_section(is_const=False))
            elif self.at_kw('const'):
                self.next()
                decls.extend(self.var_section(is_const=True))
            elif self.at_kw('procedure', 'function'):
                decls.append(self.routine())
            elif self.at_kw('begin'):   # main block, run by RunMain
                main = self.block()
                if not main.body and (self.at('sym', '.') or self.at('sym', ';')):
                    self.next()
                    continue
                raise self.error('a main block with statements is not supported', main.tok)
            else:
                raise self.error('unsupported top-level construct')
            self.skip_semicolons()
        return Program(decls, self.includes_math)

    def var_section(self, is_const: bool) -> list[VarDecl]:
        out = []
        while self.peek().kind == 'ident':
            tok = self.peek()
            names = [self.next().value]
            while self.at('sym', ','):
                self.next()
                names.append(self.ident().value)
            typ = value = None
            if self.at('sym', ':'):
                self.next()
                typ = self.type_ref()
            if self.at_sym('=', ':='):
                self.next()
                value = self.expression()
            if typ is None and value is None:
                raise self.error('declaration without type or value', tok)
            self.expect('sym', ';')
            out.append(VarDecl(tok, names, typ, value, is_const))
        return out

    def type_ref(self) -> TypeRef:
        if self.at_kw('array'):
            self.next()
            dims = []
            if self.at('sym', '['):
                self.next()
                while True:
                    low = self.expression()
                    self.expect('sym', '..')
                    dims.append((low, self.expression()))
                    if not self.at('sym', ','):
                        break
                    self.next()
                self.expect('sym', ']')
            self.expect('keyword', 'of')
            return TypeRef('array', self.type_ref(), dims)
        return TypeRef(self.ident().value)

    def routine(self) -> Routine:
        kind_tok = self.next()
        name = self.ident()
        if self.at('sym', '.'):
            raise self.error('methods are only supported in Math.dws', name)
        params: list[Param] = []
        if self.at('sym', '('):
            self.next()
            while not self.at('sym', ')'):
                modifier = ''
                if self.at_kw('var', 'const') or self.at('ident', 'out') and self.peek(1).kind == 'ident':
                    modifier = self.next().key
                names = [self.ident().value]
                while self.at('sym', ','):
                    self.next()
                    names.append(self.ident().value)
                typ = default = None
                if self.at('sym', ':'):
                    self.next()
                    typ = self.type_ref()
                if self.at('sym', '='):
                    self.next()
                    default = self.expression()
                params.extend(Param(n, typ, default, modifier) for n in names)
                if not self.at('sym', ')'):
                    self.expect('sym', ';')
            self.next()
        result = None
        if kind_tok.key == 'function':
            self.expect('sym', ':')
            result = self.type_ref()
        self.expect('sym', ';')
        if self.at('ident') and self.peek().key in ('overload', 'forward'):
            raise self.error(f'{self.peek().value} is only supported in Math.dws')
        local: list[VarDecl] = []
        while self.at_kw('var', 'const'):
            is_const = self.next().key == 'const'
            local.extend(self.var_section(is_const))
        if self.at_kw('procedure', 'function'):
            raise self.error('nested routines are not supported')
        body = self.block()
        self.expect('sym', ';')
        return Routine(kind_tok, kind_tok.key, name.value, params, result, local, body)

    # ---- statements ------------------------------------------------------------------------------------------
    def block(self) -> Block:
        tok = self.expect('keyword', 'begin')
        body = self.statement_list(('end',))
        self.expect('keyword', 'end')
        return Block(tok, body)

    def statement_list(self, enders: tuple[str, ...]) -> list[Stmt]:
        body = []
        while True:
            while self.at('sym', ';'):
                self.next()
            if self.at_kw(*enders) or self.at('eof'):
                return body
            stmt = self.statement()
            if stmt is not None:
                body.append(stmt)
            if not self.at('sym', ';') and not self.at_kw(*enders):
                raise self.error('expected ; between statements')

    def statement(self) -> Stmt | None:
        tok = self.peek()
        if self.at('sym', ';') or self.at_kw('end', 'else'):
            return None
        if self.at_kw('begin'):
            return self.block()
        if self.at_kw('if'):
            self.next()
            cond = self.expression()
            self.expect('keyword', 'then')
            then = self.statement()
            else_ = None
            if self.at_kw('else'):
                self.next()
                else_ = self.statement()
            return If(tok, cond, then, else_)
        if self.at_kw('for'):
            self.next()
            var = self.ident().value
            self.expect('sym', ':=')
            start = self.expression()
            if not self.at_kw('to', 'downto'):
                raise self.error('only for ... to/downto ... do is supported')
            downto = self.next().key == 'downto'
            stop = self.expression()
            self.expect('keyword', 'do')
            return For(tok, var, start, stop, downto, self.statement())
        if self.at_kw('while'):
            self.next()
            cond = self.expression()
            self.expect('keyword', 'do')
            return While(tok, cond, self.statement())
        if self.peek().kind == 'keyword' and self.peek().key not in ('not', 'nil', 'inherited'):
            raise self.error(f'unsupported statement {self.peek().value}')
        target = self.designator()
        if self.at_sym(':=', '+=', '-=', '*=', '/='):
            op = self.next().value
            return Assign(tok, target, op, self.expression())
        return CallStmt(tok, target)

    # ---- expressions -----------------------------------------------------------------------------------------
    REL_OPS = ('=', '<>', '<', '>', '<=', '>=')
    ADD_OPS = ('+', '-')
    MUL_OPS = ('*', '/')

    def expression(self) -> Expr:
        left = self.simple_expression()
        while self.at_sym(*self.REL_OPS) or self.at_kw('in', 'is'):
            tok = self.next()
            left = Binary(tok, tok.key, left, self.simple_expression())
        return left

    def simple_expression(self) -> Expr:
        left = self.term()
        while self.at_sym(*self.ADD_OPS) or self.at_kw('or', 'xor'):
            tok = self.next()
            left = Binary(tok, tok.key, left, self.term())
        return left

    def term(self) -> Expr:
        left = self.factor()
        while self.at_sym(*self.MUL_OPS) or self.at_kw('div', 'mod', 'and', 'shl', 'shr', 'as'):
            tok = self.next()
            if tok.key == 'as':
                left = Cast(tok, left, self.ident().value)
            else:
                left = Binary(tok, tok.key, left, self.factor())
        return left

    def factor(self) -> Expr:
        tok = self.peek()
        if tok.kind == 'marker':
            self.next()
            return Marked(tok, tok.value, self.factor())
        if self.at_kw('not'):
            self.next()
            return Unary(tok, 'not', self.factor())
        if self.at_sym('-', '+'):
            self.next()
            return Unary(tok, tok.value, self.factor())
        if tok.kind in ('int', 'float', 'string'):
            self.next()
            return self.postfix(Literal(tok, tok.kind, tok.value))
        if self.at_kw('nil'):
            self.next()
            return Nil(tok)
        return self.designator()

    def designator(self) -> Expr:
        tok = self.peek()
        if self.at('sym', '('):
            self.next()
            inner = self.expression()
            self.expect('sym', ')')
            return self.postfix(inner)
        if self.at('sym', '['):
            self.next()
            items = []
            while not self.at('sym', ']'):
                item = self.expression()
                if self.at('sym', '..'):
                    self.next()
                    item = Range(item.tok, item, self.expression())
                items.append(item)
                if not self.at('sym', ']'):
                    self.expect('sym', ',')
            self.next()
            return self.postfix(SetLiteral(tok, items))
        if tok.kind != 'ident':
            raise self.error('expected an expression')
        self.next()
        return self.postfix(Name(tok, tok.value))

    def postfix(self, expr: Expr) -> Expr:
        while True:
            tok = self.peek()
            if self.at('sym', '.'):
                self.next()
                name = self.peek()
                if name.kind not in ('ident', 'keyword'):   # keywords are valid member names (.Create, .End)
                    raise self.error('expected member name')
                self.next()
                expr = Member(name, expr, name.value)
            elif self.at('sym', '('):
                self.next()
                args = []
                while not self.at('sym', ')'):
                    args.append(self.expression())
                    if not self.at('sym', ')'):
                        self.expect('sym', ',')
                self.next()
                expr = Call(tok, expr, args)
            elif self.at('sym', '['):
                self.next()
                indices = [self.expression()]
                while self.at('sym', ','):
                    self.next()
                    indices.append(self.expression())
                self.expect('sym', ']')
                expr = Index(tok, expr, indices)
            else:
                return expr


def parse(tokens: list[Token]) -> Program:
    return Parser(tokens).parse_program()
