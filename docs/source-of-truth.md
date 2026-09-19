# Source of truth

The port copies **one** snapshot of the original game. Every check, comparison and decision uses this
snapshot and nothing else: not Crystal Clash, not the live Steam game, not videos or wikis.
If this snapshot cannot answer a question, we write that down in the gap list instead of guessing.

Exception (owner, 2026-09-19): screenshots and videos of **Rise of Legions** (never Crystal Clash) may serve as a
visual cross-check of what the snapshot and the reference build (`docs/original-build.md`) show: layout, look, feel.
The snapshot still wins where they disagree (a picture may show an older or newer version); a disagreement is written
down in `docs/visual-references.md` with the picture's source and date, not silently followed. The list of pictures
used is in that file.

## Pinned commits

| Repo | Commit | Date | Notes |
| --- | --- | --- | --- |
| [BrokenGamesUG/rise-of-legions](https://github.com/BrokenGamesUG/rise-of-legions) | `96d5b8e45296d67ae05d9e752ab44dd90c5116fe` | 2020-12-29 | "Initial commit": the only content commit. Everything after it changes README.md only. |
| [BrokenGamesUG/delphi3d-engine](https://github.com/BrokenGamesUG/delphi3d-engine) | `7c745ef3634437ef3eeee407d34b15baa3a693ce` | 2020-12-29 | "Initial commit": the only content commit. The RoL repo also carries its own `Engine/` copy; for game behaviour, the RoL repo's copy wins. |

Why this is the right version: the code was published on 2020-12-29, while the game still shipped as
*Rise of Legions*. The Crystal Clash rebrand came later and was never pushed to these repos. So the single
content commit **is** the last pre-Crystal-Clash version available. (Later README-only commits change nothing
the port depends on.)

`tools/fetch_reference.ps1` clones both at these commits into `reference/` (git-ignored, excluded from export,
and marked `.gdignore` so Godot never imports it).

## Licenses in the snapshot

- Code (outside the engine): GNU AGPL v3 (`LICENSE`).
- Engine: its own license, see the delphi3d-engine repo.
- Media: the README says CC0, but the snapshot also contains `MEDIA-LICENSE-CC-BY-NC-SA-4.0.txt`. The two
  disagree. Separately, the original developers gave the owner of this port direct permission to use the game
  and its source. The port credits the original creators and never presents their work as ours.

## Not in the snapshot

- The master server (accounts, matchmaking, shop, collection, quests). The README says it stays closed.
  The port must rebuild whatever of this the offline/local game needs, using the client API units
  (`BaseConflict.Api.*.pas`) as the contract.
- `Sound/Banks/Music.bank` ships as a split zip (`.001`-`.003`) and must be unpacked.
