# The map: zones, build zones, lanes, pathfinding

How the original's map works (`BaseConflict.Map.pas`, `BaseConflict.Classes.Pathfinding.pas`) and how the port
does it. Read `docs/entity-core.md` first for the general port conventions.

## Files

| File | Ports |
| --- | --- |
| `tools/convert_maps.py` | `Maps/<Name>/<Name>.bcm` (XML of `TMap`) → `src/content/maps/<Name>.json` (committed; `--check` in the test runner) |
| `src/runtime/map/t_map.gd` | `TMap` (`:197`): team/player count, boundaries, named zones, build zones, lanes, pathfinding |
| `src/runtime/map/t_build_zone.gd`, `t_build_zone_manager.gd` | `TBuildZone` (`:39`), `TBuildZoneManager` (`:115`) |
| `src/runtime/map/t_lane.gd`, `t_lane_manager.gd` | `TLane` + `RWaypoint` (`:138`), `TLaneManager` (`:169`) |
| `src/runtime/math/` | `RLine2D`, `RRay2D`, `TPolygon`, `TMultipolygon` (`Engine.Math.Collision2D.pas`), the members the game uses |
| `src/runtime/engine/t_2d_grid.gd`, `t_ring_buffer.gd`, `t_priority_queue.gd`, `t_int_priority_queue.gd` | `T2DGrid<T>`, `TRingBuffer<T>`, `TPriorityQueue<T>` / `TIntPriorityQueue<T>` (`Engine.Helferlein.DataStructures.pas`) |
| `src/runtime/classes/t_pathfinding*.gd`, `t_path*.gd` | `TPathfinding`, `TPathfindingTile`, `TPathfindingTileNeighbour`, `TPath`, `TPathWaypoint` |
| `src/runtime/components/t_wela_target_constraint_{grid,build_team,zone}_component.gd` | the three map-bound target constraints (`Shared.Wela.pas:249-375`) |

Tests: `tests/test_map.gd` (maps, build zones incl. the real server `Scenarios\PvPBlue`, lanes, zones, the
three constraints), `tests/test_pathfinding.gd` (grid, A*, reservations, the data structures).

## How the original works

- **Map file** (`.bcm`): `TeamCount`, `PlayerCount`, `MapBoundaries` (both maps: -150..150) and `Zones`, named
  `TMultipolygon`s: `Walkzone` (`ZONE_WALK`), `Drop` (`ZONE_DROP`), `Spell1`/`Spell2`, `Camera`. A multipolygon is
  a list of additive and subtractive polygons; a point is inside when more additive than subtractive polygons
  contain it (Classic's drop and walk zones have a subtractive hole around the middle lane). The graphics
  (terrain, vegetation, water, light) are other files, loaded by the client map.
- **Build zones** come from the scenario scripts, not the map file:
  `Game.Map.BuildZones.AddBuildZone(TBuildZone.new().Create(ID).SetTeam(..).SetPosition(..).SetSize(8, 3)...)`.
  A zone is a grid of 2 x 2 fields (`GRIDNODESIZE`) around `Center`, oriented by `Front` (normalized) and
  `Left` (= Front rotated by +90°). Field (x, y) centers at `Center + 2 * Front * (y - Size.y/2 + 0.5) + 2 *
  Left * (x - Size.x/2 + 0.5)`; `PositionToCoord` inverts it with Delphi `Round` (banker's: a point on a
  field border can land either way). Fields hold `FIELD_FREE` (-1), a ban (`Block`: -2 and lower) or the ID of
  the entity blocking them (`eiSetGridFieldBlocking`, `TEntityManagerComponent`). A banned field is out of
  range. Out-of-grid fields read as free (T2DGrid default). Setting the size frees every field.
- **Lanes** are hard-coded ("Hacked values"): `TLaneManager.Create` builds the Classic map's two lanes, and
  `Lanes.single()` (called by the one-lane scenarios) replaces them with the Single map's one lane. A lane is a
  list of waypoint lines (x = ±60 across the lane) with fan directions that project points onto the line.
  `GetLanePropertiesOfEntity` picks the nearest lane and the direction towards the nearest enemy nexus.
- **Pathfinding**: A* over 0.8 x 0.8 tiles (`PATHFINDING_TILE_SIZE`; 374 x 374 on a 300 wide map, because 300 /
  single(0.8) = 374.99999). Tiles whose center is outside the walk zone are permanently blocked; entities block
  tiles (`BlockTile`); computed paths reserve 150 ms time slots (50-slot ring buffer per tile) from when a tile is
  entered until the next is entered, so later paths avoid them. Step cost = distance between tile centers;
  heuristic = beeline, or with waypoints (nexus targets) the way along the lane's waypoints ahead. The search
  stops at the target, when a neighbour is the target (checked before walkability) or when a tile's cost reaches
  the maximum path length. Each entity keeps its last path; a new path or `CancelLastComputedPath` releases it.

## Port conventions and gotchas

- **Maps are data**: `TMap.new().CreateFromFile(TMap.MapFile("Classic"))` reads the converted JSON. Rerun
  `python tools/convert_maps.py` if the pinned source changes. The export preset includes `src/content/maps/*.json`.
- **Vectors**: `RVector2` = `Vector2` (float32 components, like singles), `RIntVector2` / `RSmallIntVector2` =
  `Vector2i`, `RMatrix2x2.CreateBase(Left, Front)` = `Transform2D(Left, Front, 0)` (columns; same product).
  `RRectFloat` = `Rect2` for the map boundaries; tiles keep their four edges as singles (a Rect2 recomputes
  Right/Bottom through its size and can be one ulp off).
- **Singles**: values the original stores in singles go through `RParam.ToSingle` (tile edges, costs, heuristics);
  intermediate math is double, like Delphi's excess precision.
- **Priority queue ties decide paths**: `TPriorityQueue` compares singles with `CompareValue` (`L.CompareValue`,
  equal within a relative 1E-4, see `L.SameValue`) and among equal priorities returns the last inserted first.
  With a blocked tile between two equally long detours the path takes the one whose tiles were inserted last
  (the neighbour order runs top-left to bottom-right, so: south). `tests/test_pathfinding.gd` pins this.
- **Globals**: the original's `Map` global is the running game's map; `TPathfinding` keeps a reference to its map
  instead. `TLaneManager.GetLanePropertiesOfEntity(Game, ...)` / `GetOrientationOfNextLane(Game, ...)` take the
  Game (like `RTarget`); `ComputePath` uses the entity's global bus's Game. `GameTimeManager` (the per-game clock)
  is `TTimeManager.GetTimeStamp()` until the game loop (as in `TGameTimer`).
- **Lazy tiles**: `TPathfinding.Grid(x, y)` creates a tile on first access (with its walk-zone check), instead of
  building all 140k up front. A tile depends only on its position, so this is invisible.
- **Out parameters**: `TryGetBuildZone` / `TryGetNextWaypoint` return the value or null;
  `GetLanePropertiesOfEntity` returns `[Lane, Direction]`.
- `TBuildZoneManager.BuildZones` iterates in insertion order (the original: hash order; zones never overlap).
- **Kept quirks** (1:1): `TLane.DistanceToPoint` returns the distance to the last waypoint (its loop overwrites);
  `GetNextWaypoint` ignores the direction; the A* source keeps a stale heuristic from earlier searches; with
  `IgnoreOtherEntities` (units with `udUsePathfinding` off) only permanently blocked tiles are expanded, so such
  units would get a path only to an adjacent target, else an empty one. Unreachable in the game: those units walk
  straight (`TMovementComponent.IdleDirect`) and never ask for a path;
  `ComputeDebugPath` frees its path, which releases slots even though it reserved none.
- Skipped, no effect: `TPathfindingTileNeighbour.Create` computes the lane orientation and never uses it.
  Engine options never used: descending priority order (`TPriorityQueue.Order`), `TPathfinding.MaxUnitSize`
  (stored only), `TPathfindingTile.IsWalkable`'s `UnitSize`.

## Not ported yet

- Client debug rendering (`TBuildZone.RenderDebug/RenderEntityGrid/RenderOccupation`, `TLane.DebugRender`),
  the client map (`TClientMap`: terrain, water, vegetation), `TMap.SaveToFile` (map editor).
- The other users: the server's build and spawn logic. (Movement: `docs/entity-core.md`, "Movement".)
