"""Unit tests of the DWScript transpiler (lexer, parser, emitter) on small snippets with a hand-built symbol table.

Run: python -m unittest discover -s tools/tests   (tools/run_tests.ps1 runs it too). Needs no reference/ checkout.
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dws.emitter import EmitError, Emitter  # noqa: E402
from dws.lexer import tokenize  # noqa: E402
from dws.parser import ParseError, parse  # noqa: E402
from dws.symbols import EnumDecl, Member, Param, SymbolTable, TypeDecl  # noqa: E402


def symbols() -> SymbolTable:
    t = SymbolTable()
    t.types['tobject'] = TypeDecl('TObject', 'class', members=[Member('Create', 'method', 'public', '', 'constructor')])
    t.types['tentity'] = TypeDecl('TEntity', 'class', members=[
        Member('Blackboard', 'property', 'public', 'TBlackboard'),
        Member('ReserveFreeGroup', 'method', 'public', 'integer', 'function')])
    t.types['tblackboard'] = TypeDecl('TBlackboard', 'custom', members=[
        Member('SetValue', 'method', 'public', '', 'procedure',
               params=[Param('Event', 'EnumEventIdentifier'), Param('Group', 'TArray<System.Byte>'),
                       Param('Value', 'Variant')])])
    t.types['tentitycomponent'] = TypeDecl('TEntityComponent', 'class', members=[
        Member('CreateGrouped', 'method', 'public', '', 'constructor',
               params=[Param('Owner', 'TEntity'), Param('Group', 'TArray<Byte>')])])
    t.types['tfoocomponent'] = TypeDecl('TFooComponent', 'class', 'TEntityComponent', members=[
        Member('SetSpeed', 'method', 'public', 'TFooComponent', 'function', params=[Param('Speed', 'single')]),
        Member('SetSpeeds', 'method', 'public', 'TFooComponent', 'function',
               params=[Param('Speeds', 'TArray<single>')]),
        Member('Activate', 'method', 'public', 'TFooComponent', 'function'),
        Member('Count', 'property', 'public', 'integer')])
    t.add_enum(EnumDecl('EnumDamageType', [('dtSiege', 0), ('dtCharge', 1)]))
    t.add_enum(EnumDecl('EnumEventIdentifier', [('eiSpeed', 0)]))
    t.add_const('GROUP_SOUL', '', tokenize('11'))
    t.exposed_classes = ['TEntity', 'TFooComponent']
    t.custom_classes = ['TBlackboard']
    t.exposed_types = ['EnumDamageType', 'EnumEventIdentifier']
    t.exposed_consts = ['GROUP_SOUL']
    return t


def emit(source: str) -> str:
    return Emitter(symbols(), 'Test.dws', 'SERVER').emit(parse(tokenize(source, 'Test.dws')))


def body(source: str) -> list[str]:
    """Emitted statement lines of the single routine in source, without the line trail comments."""
    lines = emit(source).split('\n')
    start = next(i for i, line in enumerate(lines) if line.startswith('func '))
    return [line.split('  # ')[0] for line in lines[start + 1:] if line.startswith('\t')]


class EmitterTest(unittest.TestCase):
    def test_float_division_and_div(self):
        out = body('procedure P; var a : integer; x : single; begin x := a / 2; a := a div 2; end;')
        self.assertIn('\tx = float(a) / 2', out)
        self.assertIn('\ta = L.Div(a, 2)', out)

    def test_bitwise_versus_boolean(self):
        out = body('procedure P(a, b : integer; c : boolean); begin c := (a and b) = 0; c := c and not c; end;')
        self.assertIn('\tc = (a & b) == 0', out)
        self.assertIn('\tc = c and (not c)', out)

    def test_constructor_chain_and_parameterless_calls(self):
        out = body('procedure CreateEntity(Entity : TEntity); begin '
                   'TFooComponent.CreateGrouped(Entity, [GROUP_SOUL]).SetSpeed(1).Activate; end;')
        self.assertEqual(out, ['\tTFooComponent.new().CreateGrouped(Entity, [C.GROUP_SOUL]).SetSpeed(1.0).Activate()'])

    def test_float_arrays_are_coerced(self):
        out = body('procedure P(E : TEntity); begin TFooComponent.CreateGrouped(E, []).SetSpeeds([1, 2.5]); end;')
        self.assertIn('.SetSpeeds([1.0, 2.5])', out[0])

    def test_names_take_the_declared_spelling(self):
        out = body('procedure P(entity : TEntity); var g : integer; begin '
                   'g := ENTITY.reservefreegroup; entity.blackboard.setvalue(EISPEED, [g], [DTCHARGE]); end;')
        self.assertEqual(out[1], '\tg = entity.ReserveFreeGroup()')
        self.assertEqual(out[2], '\tentity.Blackboard.SetValue(C.eiSpeed, [g], [C.dtCharge])')

    def test_function_result_and_for_loop(self):
        out = body('function F(n : integer) : integer; var i : integer; begin '
                   'Result := 0; for i := 1 to n do Result := Result + i; end;')
        self.assertEqual(out, ['\tvar Result: int = 0', '\tvar i: int = 0', '\tResult = 0',
                               '\tfor _for_i in range(1, (n) + 1):', '\t\ti = _for_i', '\t\tResult = Result + i',
                               '\treturn Result'])

    def test_balance_markers_become_comments(self):
        text = emit('procedure P(E : TEntity); begin E.Blackboard.SetValue(eiSpeed, [], {@UBL_Health} 100); end;')
        self.assertIn('SetValue(C.eiSpeed, [], 100)  # 1 {@UBL_Health}', text)

    def test_unknown_names_stop_the_conversion(self):
        with self.assertRaisesRegex(EmitError, r'Test.dws:1: unknown identifier Nope'):
            emit('procedure P; begin Nope; end;')
        with self.assertRaisesRegex(EmitError, 'TEntity has no public member missing'):
            emit('procedure P(E : TEntity); begin E.Missing; end;')
        with self.assertRaisesRegex(EmitError, 'is a property, not a method'):
            emit('procedure P(E : TEntity); var c : integer; begin c := TFooComponent.CreateGrouped(E, []).Count(); end;')

    def test_unsupported_syntax_stops_the_parser(self):
        with self.assertRaisesRegex(ParseError, 'unsupported statement'):
            emit('procedure P; begin repeat until True; end;')


class StubTest(unittest.TestCase):
    def test_gd_param_count(self):
        # stubs size their constructors by the inherited method's parameter count
        from transpile_scripts import gd_param_count
        self.assertEqual(gd_param_count(''), 0)
        self.assertEqual(gd_param_count(' '), 0)
        self.assertEqual(gd_param_count('Owner = null'), 1)
        self.assertEqual(gd_param_count('Owner = null, Group = [1, 2], f: Callable = Callable()'), 3)


if __name__ == '__main__':
    unittest.main()
