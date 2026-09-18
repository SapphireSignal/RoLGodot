# CONTINUE

Hand-off note for the next session. Read `CLAUDE.md` first, then this.

## The owner's brief (session 1, 2026-09-18)
- Port **Rise of Legions** to **Godot** as a strict 1:1 replica of its **last update before it became
  Crystal Clash**. Every detail the same: units, cards, numbers, effects, sounds, UI, little touches.
- The original devs gave the owner permission to use and do anything with the game and its source.
- Build it in parts like a professional team, with care. Claude is the returning lead dev.
- Lean repo, lean Windows build. `play.bat` to launch. Professional GitHub repo (don't claim to be a team).
- Playful dev-team roster (`docs/team.md`): hired only when needed; agents cost the owner's usage.
- Never read or write the owner's other repos.

## Where we are
Phases 0 and 1 done (see `docs/port-plan.md`). Verified facts about the original are in
`docs/original-architecture.md`. If `reference/` is missing, run `tools\fetch_reference.ps1` (~800 MB download,
~3 GB checked out; run it in the background).

Phase 1: `docs/scripts.md` explains the pipeline and the output. `python tools/transpile_scripts.py` regenerates
`src/content/scripts/{client,server}/` (committed), `src/runtime/dws/dws_const.gd`, the class stubs in
`src/runtime/dws/stubs/` and `docs/script-api.md`. `tools/run_tests.ps1` runs the transpiler unit tests, checks
the generated files are up to date (when `reference/` exists) and runs the Godot compile sweep + tests.

## Next: phase 2, the entity core
Port by hand from `BaseConflict.Entity.pas` (method by method, Delphi names kept):
1. `TEntity`, `TBlackboard` (script side = the `CustomExpose` methods, see `docs/scripts.md`), `TEventbus`
   (events, priorities, groups), `TEntityComponent` (constructors `Create`/`CreateGrouped` are instance methods
   returning `self`: the transpiler emits `TFoo.new().CreateGrouped(...)`).
2. The script runner: `CreateFromScript` with `InheritsFrom` / `InheritsFromPreceding`, `ApplyScript`,
   `ApplyScriptReturnGroups`, `L.game_resolver`, the `ORIGINAL_COMPILE_ERROR` files (`script_index.gd` maps paths).
3. Unit tests mirroring the Pascal behaviour (event order, grouped values).
When a hand-written file declares `class_name TFoo`, rerun the transpiler: it drops the stub.
Delphi overloads (e.g. `TBlackboard.SetValue`) need one GDScript method that dispatches on the value's type.
