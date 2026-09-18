# RoLGodot

A 1:1 Godot 4.7 port of **Rise of Legions**: its last version before the Crystal Clash rebrand.
The global rules in `C:\Users\srrwz\.claude\CLAUDE.md` always apply.

## Project rules
- Source of truth: `reference/rise-of-legions` at commit `96d5b8e4` (see `docs/source-of-truth.md`).
  Never use Crystal Clash content, the live game, or anything outside that snapshot for decisions.
- Stay inside `D:\Games\RoLGodot`. Never touch the owner's other repos.
- Lean repo and build: `reference/` is git-ignored, `.gdignore`d and excluded from export, like `tools/`,
  `tests/`, `docs/`. Get it with `tools/fetch_reference.ps1`.
- Original data uses German decimal commas and mismatched file-name case: parse/compare accordingly.
- Git identity: SapphireSignal <SapphireSignal@users.noreply.github.com>.
- Subagent roles and their cost: `docs/team.md`.

## Tools
- Godot: `D:\Godot\Godot_v4.7.1-stable_win64.exe` (console build `..._console.exe` for headless runs)
- Delphi: `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\`
- Tests: `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` (import + compile sweep + tests,
  hard timeout, logs in `logs/`). Test files: `tests/test_*.gd` extending `res://tests/test_case.gd`.

## Docs
- `docs/original-architecture.md`: how the original is built, file formats, gotchas.
- `docs/port-plan.md`: phases 0-9. `docs/gap-list.md`: user-visible behaviours and their status.
- `docs/scripts.md`: how the original runs scripts, the construct survey, transpiler decisions.

## Status
- 2026-09-18: Phase 0 (foundation) done: source pinned, reference cloned, architecture researched, Godot
  scaffold + test runner + `play.bat` + export preset. Next: phase 1, the DWScript → GDScript transpiler.
- 2026-09-18: Phase 1 steps 1-2 done: script engine read, lexer + preprocessor (`tools/dws/`), survey
  (`tools/survey_scripts.py`, all 509 scripts preprocess for CLIENT and SERVER), `docs/scripts.md`.
  Next: parser + GDScript emitter (step 3).
