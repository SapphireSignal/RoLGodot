# Port plan

How we get from the Delphi original to a 1:1 Godot game, in phases. Each phase ends with something the owner
can run or check, tests green, and docs updated. Facts about the original: `original-architecture.md`.

## Principles

1. **Convert, don't hand-copy.** Content (≈500 scripts, 366 particle effects, 139 GUI screens, 29-language
   text, maps) is converted by tools in `tools/`, rerunnable from `reference/`. Hand-porting that much content
   breeds silent mistakes; a converter fails loudly and is fixed once.
2. **Port the systems by hand, line by line.** The entity/blackboard/eventbus core and the component classes
   (brains, welas, warheads) are ported from the Pascal source method by method, keeping names so any GDScript
   line can be traced back to its original.
3. **Simulation first, pictures second.** The game-server simulation is deterministic and testable
   headless. We prove numbers match (damage, cooldown timing, pathing) before we draw anything.
4. **Local-first.** The game server runs in-process. The master server (closed source) is replaced by a local
   profile that satisfies the `BaseConflict.Api.*` contract.
5. **Generated output is not committed if it is big.** Converters write game-ready files into `src/`/`assets/`
   only when those files are small or hand-edited afterwards; bulk assets are generated on setup.
   (Decision per asset type recorded in that converter's doc.)

## Phases

| # | Phase | Done when |
| --- | --- | --- |
| 0 | **Foundation**: pin source, docs, Godot scaffold, test runner, `play.bat`, export preset | ✅ this session |
| 1 | **Script transpiler**: DWScript subset → GDScript for all of `Scripts/` | every script converts and compiles in the sweep; conversion report shows 0 unsupported constructs |
| 2 | **Entity core**: `TEntity`, blackboard, eventbus, component base, shared components | unit tests mirror the Pascal behaviour (event order, grouped values) |
| 3 | **Simulation**: server components (brains, welas, warheads), game loop, pathfinding, the sandbox deck | headless sandbox match: Footman vs Footman trades hits at 13 dmg / 2000 ms with the right action point; lanes, spawners, nexus damage |
| 4 | **Asset pipeline**: meshes (FBX + XML → scene/material), textures (+ KTF decoder), maps (terrain, water, vegetation, lights) | the Classic map and every unit render in a viewer scene, side-by-side screenshots checked |
| 5 | **Playable sandbox**: camera, input, card hand, spawning, HUD, animations, minimap | the owner plays a sandbox match against the idle opponent |
| 6 | **Effects and sound**: particles (`.pfx`), shaders and post effects, FMOD extraction and event mapping | every card's effects and sounds present; audit per card |
| 7 | **Menus and meta**: GUI converter (`.dui`/`.scss`), main menu, collection, deckbuilder, shop (offline), quests, profile, settings, localisation | every screen reachable, text in all 29 languages |
| 8 | **Content breadth**: scenarios, mutators, tutorial, AI opponents, 2v2 / co-op modes | every scenario playable |
| 9 | **Release polish**: gap-list zero, performance, Windows export | lean build passes the export check |

Why this order: the scripts are the heart of the game and touch every system, so the transpiler (phase 1)
flushes out every language feature and component the core must support. Phases 2-3 then have a complete,
concrete list of what to port instead of guessing.
