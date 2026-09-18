# RoLGodot

A faithful port of **Rise of Legions** to **Godot 4.7**.

Rise of Legions by [Broken Games](http://brokengames.de/) is a mix of MOBA, tower defense and deckbuilding:
fast tug-of-war battles, solo, co-op or 2v2, with a collectible card deck. Its studio open-sourced the client and
game server in December 2020 ([BrokenGamesUG/rise-of-legions](https://github.com/BrokenGamesUG/rise-of-legions)),
and later rebranded the live game as *Crystal Clash*.

This project recreates the **last Rise of Legions version before that rebrand**, 1:1: the same units, cards,
numbers, effects, sounds and UI. It is a port, not a remake. Crystal Clash content is out of scope.

> Status: early. The project scaffold exists; the game is not playable yet. See [docs/](docs/) for the plan.

## Running

Requires [Godot 4.7](https://godotengine.org/). Double-click `play.bat`, or:

```bat
set GODOT=C:\path\to\Godot_v4.7.x-stable_win64.exe
play.bat
```

## Development

| Task | Command |
| --- | --- |
| Fetch the original sources (pinned commit) into `reference/` | `powershell -ExecutionPolicy Bypass -File tools\fetch_reference.ps1` |
| Run the headless test suite | `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` |

Layout:

```
src/        game code and scenes (GDScript)
tests/      headless tests (run_tests.gd runner, test_*.gd files)
tools/      fetch / extraction / test scripts (not exported)
docs/       design notes: original architecture, port plan, gap list (not exported)
reference/  pinned original source snapshot (git-ignored, not exported)
```

## Source of truth

Every gameplay and presentation decision is checked against the original source at a pinned commit.
See [docs/source-of-truth.md](docs/source-of-truth.md).

## Credits

Rise of Legions was made by Broken Games: Martin Lange and Tobias Tenbusch, with art by Sebastian Adomat,
model animations by Jennifer Jason, sound effects by Michael Klier, music by Julian Colbus and publishing by
Max Dohme. All original game content belongs to its creators. This port is an unofficial fan project and is
not affiliated with Broken Games.

## License

The port's code is licensed under the GNU AGPL v3, matching the original code base. Original assets carry
their original licenses; see [docs/source-of-truth.md](docs/source-of-truth.md).
