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
Phase 0 done (see `docs/port-plan.md`). Verified facts about the original are in
`docs/original-architecture.md`. If `reference/` is missing, run `tools\fetch_reference.ps1` (~800 MB download,
~3 GB checked out; run it in the background).

## Next: phase 1, the script transpiler
1. Read `Engine/Engine.Script.pas` to see how scripts are compiled: which symbols are exposed (the component
   classes, `RVector3`, enums), how `{$INCLUDE}` and `{$IFDEF CLIENT/SERVER}` are resolved.
2. Survey the DWScript constructs used across `Scripts/` (procedures, vars, if/else, for, fluent method chains,
   set literals `[a, b]`, `{@UBL_...}` markers, includes). Write the survey into `docs/scripts.md`.
3. Write `tools/transpile_scripts.py`: `.ets/.dws/.sps` → GDScript under `src/content/scripts/`, one file per
   script, keeping the three entry points. Unsupported constructs are reported, never skipped silently.
4. Test: every generated file passes the compile sweep (it needs stub component classes, which become the
   phase 2 work list).
Open question to resolve on the way: the last argument of `TCardInfo.Create` in `BaseConflict.Constants.Cards.pas`.
