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

Phase 1 steps 1-2 done: `docs/scripts.md` holds how the original compiles and runs scripts (defines,
`#define` quirk, includes, `InheritsFrom`), the construct survey and the transpiler decisions (one output per
side, canonical name spelling, `Math.dws` hand-ported). Front end: `tools/dws/lexer.py`,
`tools/dws/preprocess.py`; survey: `python tools/survey_scripts.py --json logs/script_survey.json`.

## Next: phase 1, the script transpiler
3. Write `tools/dws/parser.py` (AST for the subset in `docs/scripts.md`) and `tools/transpile_scripts.py`:
   preprocess per side → parse → emit `src/content/scripts/{client,server}/<path>.gd`, keeping entry points.
   Unsupported constructs stop with file:line, never skipped silently. Build the symbol table for canonical
   spellings from the Pascal declarations of the exposed classes and enums.
4. Test: every generated file passes the compile sweep (it needs stub component classes, which become the
   phase 2 work list: the survey's `classes` and `members`).
Open question to resolve on the way: the last argument of `TCardInfo.Create` in `BaseConflict.Constants.Cards.pas`.
