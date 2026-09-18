# Scripts: how the original runs them, what they use, how we transpile them

Source: `Engine/Engine.Script.pas`, `BaseConflict.Entity.pas` (`CreateFromScriptProc`, `ApplyScript*`),
`Engine/Engine.Helferlein.Windows.pas` (`HPreProcessor.ResolveDefines`). Numbers come from
`python tools/survey_scripts.py --json logs/script_survey.json` (rerun it after transpiler changes).

## How the original compiles and runs a script

- One `TScriptmanager` (DWScript `TDelphiWebScript`) per process. Unit/include search path is
  `Scripts/HelperScripts/`. Compiled programs are cached per lower-cased file path.
- **Defines**: the client adds `CLIENT` (`BaseConflictMainUnit.pas`), the game server adds `SERVER`
  (`GameServer/BaseConflict.Game.Server.pas`), debug builds add `DEBUG`. The two sides are separate processes,
  so every script is compiled twice in total: once with `CLIENT`, once with `SERVER`. `MAPEDITOR` is only set
  by the map editor, so `{$IFNDEF MAPEDITOR}` blocks are always in the game.
- **Preprocessing order** (`CompileScriptInternal`):
  1. `SCRIPTFILE_FILEPATH` / `SCRIPTFILE_NAME` → quoted path / name (plain text replace; no script uses them).
  2. `{$DEFINE X}` prepended for each define.
  3. `#define NAME text` (7 files): lines cut out, then every occurrence of `NAME` replaced **as plain text,
     case-sensitive, no word boundaries**, longest name first. The replacement runs to the end of the line.
  4. DWScript: `{$IFDEF}`, `{$IFNDEF}`, `{$ELSE}`, `{$ENDIF}`, `{$INCLUDE 'x'}`. An include gets step 3 on its
     own text only: a main file's `#define` never reaches an included file.
- **Running** (`TEntity.CreateFromScriptProc`): compile → `RunMain` (initialises globals) → set the globals
  `GlobalEventbus` and `Game` if the script declares them → call the entry point with the entity.
  - `var InheritsFrom : string` (31 scripts): the parent chain builds the entity first (its entry point runs
    fully), then the child's entry point of the same name runs on that entity. The entity keeps the child's
    file name (`ScriptFile`).
  - `var InheritsFromPreceding : string` (4): the child's entry point runs inside the initializer, i.e. right
    after `TEntity.Create` and **before** the base script's entry point.
  - Neither: this is the base script; it creates the entity (`IsAbstract` = meta), runs the initializer, then
    its entry point.
  - Unit entry points: `CreateData` → `CreateMeta` → `CreateEntity`, each calling the previous one.
  - `ApplyScript(file, proc = 'Apply', params)`: modifiers, scenarios. `ApplyScriptReturnGroups`: links, whose
    `Apply` is a `function ... : array of integer` returning the component groups it created.
  - AI (`Scripts/AI`): `Prepare(AiInterface)` once, `Think(AiInterface)` per tick (`Server.pas` ~4870).
- Exposed to scripts through RTTI: ~230 component classes (list: `classes` in the survey JSON), `TEntity`,
  blackboard/eventbus, `TGame`/`TClientGame`/`TServerGame`, the enums (`Enum*`, `EnumEventIdentifier` = `ei*`),
  records `RVector2/3/4`, `RIntVector2`, `RColor`, `RVariedSingle`, `RVariedVector3`, `RTarget`, arrays, a few
  constants (`ALLGROUP_INDEX`, `ANIMATION_*`, ...) and the function `Game`.

## What the scripts use (survey of all 509 files)

| | |
| --- | --- |
| Files | 368 `.ets`, 110 `.dws`, 31 `.sps`; all preprocess cleanly for CLIENT and SERVER |
| Directives | `IFDEF CLIENT` 997, `IFDEF SERVER` 581, `ENDIF` 1593, `ELSE` 34, `IFNDEF MAPEDITOR` 15, `INCLUDE` 486 |
| Includes | `Math.dws` 227, `UnitTemplate` 59, `DropTemplate` 59, `SpawnerTemplate` 56, `SpellTemplate` 31, `BuildingTemplate` 28, `BuildingCardTemplate` 20, `CardTemplate` 4, `Globals` 2 |
| Markers | `{@UBL_Health}` 151, `UBL_Tier` 133, `UBL_Armortype` 74, `UBL_Damage` 71, `UBL_Range` 70, `UBL_Cooldown` 67, `UBL_SquadSize` 64, `UBL_SpawnerSquadSize` 51, `SBL_Tier` 49: balance tags in front of a literal; semantically comments, kept as trailing comments in the output |
| Statements | assignment, call, method chains (`.A.B(x)`), `if/then/else` 124, `for ... to ... do` 12, `while` 4, no `case`/`repeat`/`try`/`exit` |
| Expressions | `+ - * /`, `div` 4, `and` 24, `or` 1, `not` 11, comparisons, set/array literals `[a, b]` (9.6k), `as` casts, string concatenation |
| Declarations | procedures (1268), functions (51, `Result` assignment), `var` sections, typed `const`, default parameters, `array of T` parameters and results |
| Only in `Math.dws` | `type single = float`, record helpers (`RVector3.Create`, `SetX`...), a script-side `record RVariedVector3` with methods, `operator + (RVector3, RVector3)`, `forward`, `overload` |

`{$IFDEF}` placement: nearly always around whole statements or declarations, but not always:
34 scenario scripts switch a **parameter type** (`{$IFDEF SERVER}Game : TServerGame{$ELSE}Game : TClientGame{$ENDIF}`),
one splits a `var` section (`SpellTemplate.dws`) and one cuts a **method chain** in half (`Vecra.ets`,
`{$IFNDEF MAPEDITOR}` between `.ApplyLegacySizeFactor` and `.CreateNewAnimation`).

Pascal is case-insensitive and the scripts rely on it: 14 identifiers appear in several spellings
(`True`/`true`, `Result`/`result`, `TBrainWelaSelftargetComponent` 76× vs `TBrainWelaSelfTargetComponent` 5×,
`eiAttentionrange`/`eiAttentionRange`, `dtDoT`/`dtDot`, ...).

## Transpiler decisions (phase 1)

1. **One GDScript per script per side**: `src/content/scripts/{client,server}/<same path>.gd`. The transpiler
   preprocesses exactly like the original (above) with `CLIENT` or `SERVER`, then parses and emits. This is
   what the original compiled, and the irregular `{$IFDEF}` placements need no special cases. The two outputs
   are generated, never hand-edited, and committed (a few MB) so the game runs without Python or `reference/`.
2. **Names are canonicalised** to the spelling of the Delphi declaration (class, enum value, method), falling
   back to the most frequent spelling in the scripts. The symbol table is generated from the Pascal sources
   of the exposed classes and enums.
3. **`Math.dws` is not transpiled**: its records, helpers and operator are a hand-written runtime part of
   phase 2 (`RVector3` etc.). The transpiler maps `RVector3.Create(x, y, z)` and `a + b` on vectors to it.
4. Enums, records and component classes are referenced through the runtime (the phase 2 work list is the
   survey's `classes` and `members`). Each generated file keeps its entry points with the original names
   (`CreateData`, `CreateMeta`, `CreateEntity`, `Apply`, `Prepare`, `Think`, ...) and a
   `# <file>:<line>` trail so every line traces back to the source.
5. Anything the parser does not know stops the conversion with file:line; nothing is skipped silently.

## What the scripts can see (symbol table, `tools/dws/symbols.py`)

Scanned from the interface sections of the Delphi sources (game folders win over `Engine/`, which holds an older
`TEntity`): `ScriptManager.ExposeClass` (329 classes), `ExposeType` (enums, records), `ExposeConstant` (84),
`ExposeFunction('Game')`. Members visible to a script = public/published members of the class and its
ancestors; root classes get `TObject` (`Create`, `Free`, `ClassName`). Two classes are built by hand with
`ScriptManager.CustomExpose` in `BaseConflict.Entity.pas` and **replace** the Delphi class on the script side:
`TBlackboard` (`SetValue`, `GetValue`, `SetIndexedValue`, `GetIndexedValue`, `SetIndexedValues`) and `TEventbus`
(`Trigger`, `TriggerGrouped`, `Write`, `WriteGrouped`), plus `RParam`.

## How the output looks (`tools/dws/emitter.py`)

| DWScript | GDScript |
| --- | --- |
| script | `src/content/scripts/{client,server}/<path>.gd`, `extends RefCounted`; globals → member vars, routines → methods with the original names; includes are inlined (templates appear in every script that includes them, as in the original) |
| `TFoo.Create(E)` / `CreateGrouped` (constructor) | `TFoo.new().Create(E)`: the runtime's constructors are instance methods returning `self` |
| `.FireAtGround` (parameterless method) | `.FireAtGround()`; the symbol table decides method vs property |
| names in any case | the declared spelling (`eiAttentionRange` → `C.eiAttentionrange`, as in the Delphi enum) |
| enum values, exposed constants | `C.<name>` (`src/runtime/dws/dws_const.gd`, generated) |
| Math.dws, built-ins | `L.<name>` (`src/runtime/dws/dws_lib.gd`, hand-written): `L.i/ii/f/ff`, `L.Div`, `L.Round` (half to even), `L.Random`, `L.Game()` ... |
| `RVector3.Create(x, y, z)`, `RVector2`, `RIntVector2` | `Vector3(x, y, z)` etc.; `.X` on them → `.x` |
| `/` | float division (`float(a) / b` unless an operand is a float) |
| `div`, `mod`, `and`/`or`/`not` on integers | `L.Div`, `%`, `&`/`|`/`~`; on booleans `and`/`or`/`not` |
| `Result`, `FunctionName := x` | local `var Result`, `return Result` at the end (no script uses `exit`) |
| `for i := a to b do` | `for _for_i in range(a, (b) + 1): i = _for_i` (bounds evaluated once, like Pascal) |
| `array + [x]` | Array concatenation (dynamic arrays); other set operators stop the conversion |
| int literal where a float is declared | `1.0` (also inside `[...]` passed to `TArray<single>`) |
| `{@UBL_Health} 100` | `100`, with `{@UBL_Health}` in the line's trailing comment |
| every statement | trailing `# <line>`; every routine a `# <file>:<line>` header |

Value types get GDScript type hints (int, float, bool, String, Vector*, Array) so Pascal's conversions happen;
objects stay untyped. GDScript does not check member names on objects at compile time, so the emitter checks
every member against the symbol table instead, using the static types it can follow (declared types,
constructor results, method result types).

`AI/MegaRootDude.dws` assigns an undeclared `ArcherDrop` in `Prepare`: the original **server** cannot compile
it. Its server output is a file with `const ORIGINAL_COMPILE_ERROR` so the runtime fails where the original
did (`ORIGINAL_COMPILE_ERRORS` in `tools/transpile_scripts.py`).

Also generated: `src/runtime/dws/stubs/<Class>.gd` (a `class_name` stub for each referenced Delphi class and
its ancestors, skipped once a hand-written file in `src/` declares the name; phase 2 replaces them),
`src/content/scripts/script_index.gd` (lower-case original path → file, per side) and `docs/script-api.md`
(every member the scripts use, per declaring class: the phase 2 work list). `.uid` files of generated scripts
are git-ignored.

## Tools

- `python tools/transpile_scripts.py`: regenerates everything above (`--check`: verify it is up to date,
  `--only X`: just scripts whose path contains X). Run it after changing anything in `tools/dws/`.
- `tools/dws/lexer.py`, `preprocess.py`, `parser.py`, `symbols.py`, `emitter.py`: the pipeline.
- `tools/tests/test_dws.py`: transpiler unit tests on snippets (no `reference/` needed); `tests/test_scripts.gd`
  runs generated code. Both run in `tools/run_tests.ps1`.
- `tools/survey_scripts.py`: the survey above; exit code 1 if any file fails to tokenize or preprocess.
