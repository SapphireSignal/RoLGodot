# The game loop (phase 3)

How a server game is set up and run. Code: `src/runtime/game/`, plus `TGameTickComponent`,
`TGameDirectorComponent`, `TTokenMappingComponent` and `TSurrenderComponent` in `src/runtime/components/`.
Tests: `tests/test_server_game.gd` (setup, ticks, end) and `tests/test_sandbox_match.gd` (the headless match).

## Pieces and their originals

| Port | Original | Role |
| --- | --- | --- |
| `TScenarioMetaInfo`, `TMutatorMetaInfo`, `TScenarioInfoManager`, `HScenario` | `BaseConflict.Constants.Scenario.pas` | scenario UID -> scripts + map per league; what a UID is (PvP, duo, sandbox...), by its name |
| `TGameInformation`, `TServerGameInformation`, `TCommanderInformation`, `TGamePlayer` | `BaseConflict.Game.pas`, `GameServer/BaseConflict.Types.Server.pas` | who plays: slots (commander decks), players by token, token -> slots |
| `TGame` | `BaseConflict.Game.pas` | game entity (ID 1) with the tick clock and the GameDirector, the map, start values the scripts set, `Initialize` applies the scenario scripts last to first |
| `TServerGame` | `GameServer/BaseConflict.Game.Server.pas:93` | the global bus (server side), server entity + collision managers, statistics, delayed events, commanders (one per slot + a spectator), `Start`, `Idle`, `TeamLost` |
| `TGameThread` | same file, `:198` | one frame = `DoComputeGame`: TickTack, Idle, debug ticks, waiting -> running (`Start`); finished -> terminated + eiServerShutdown |
| `TGameManager` (setups only) | same file, `:255-727` | the test server's sandbox game and its decks (`CreateTestserverGameInfo`) |
| `TClientGame` (part) | `BaseConflict.Game.Client.pas:79` | the client's game on a client bus: client map with decorations, collision and entity manager, scenario scripts' client part (`Initialize`); `ReceiveWorld(ServerGame)` / `AddServerEntity(stream)` stand in for the network (`SendWorld`, `DeserializeEntity`). Network, input, camera, GUI, sound, commander manager, decay, minimap, build grid: not yet |

## Flow

1. `TGameThread.new().Create(GameInfo)`: `UpdateGamePlayers`, `TServerGame.Create` (bus, game entity,
   tick + director, map, managers), the entity data cache on the bus, then `PrepareGame` = `Initialize`:
   the scenario scripts (e.g. sandbox: Game, PvPBlue, PvPRed, PvPBase, Sandbox) spawn nexus / towers / lane node,
   add build zones and director events; then the commanders from `Commander\CommanderTemplate` with their cards,
   token mapping, surrender, eiAfterCreate on the game entity.
2. The owner calls `DoComputeGame` every frame (the original aims at 32 ms, `TARGET_FRAMETIME`). Tests step
   `TTimeManager.FakeTime` by 32 ms per frame.
3. `SetAllPlayersPlaying` (stand-in for the network) -> next frame `Start` -> eiGameCommencing: 10 s warm-up
   (`InGameStatus` loading -> warming -> playing), then eiGameTick; the first tick fires eiGameStart.
4. Ticks: the tick timer restarts at the frame that fires it, so at 32 ms frames a tick comes every 1024 ms
   (the original drifts the same way). Game.dws pays income per tick and triggers a wave every 2nd tick.
5. A nexus death -> eiLose -> `TeamLost` -> `IsFinished`; the next frame terminates the thread.

## Conventions

- The functions of `TGame` are methods, as in the original (`League()`, `IsSandbox()`, `HasStarted()`,
  `IsShuttingDown()`, `GameInformation.IsTutorial()`), properties stay properties (`InGameStatus`, `ServerTime`,
  `Map`, `EntityManager`, `Commanders`...). Test fakes of the game must follow this.
- The globals `Game`, `ServerGame`, `Map`, `GlobalEventbus`, `Overwatch` are the bus's `Game` and its members.
- `TTimeManager` is static (one game at a time); `TickTack` sets `ZDiff`.

## Verified in the headless sandbox

- Footman vs Footman: 10.4 per hit (13 x medium armor 0.8), attack every 2000 ms (2048 at 32 ms frames), the
  hit 300 ms after the attack starts (320), the shield block swallows a hit every 5 s, death below 1 HP.
- A spawner fires on placement; later its field's turn in the 20-field wave rotation (~41 s).
- Footmen at the nexus deal 13 per hit; the nexus shoots back.

## Performance

`tests/profile_sandbox.gd` (run by hand, see its header; `PROFILE_HANDLERS=1` lists the costliest handlers) plays
the sandbox with a Footman drop and a spawner per side (16 units). The test server's sandbox has 16 commanders
(every colour's deck per player), so ~570 components listen to the global eiIdle, ~500 of them think timers that
read eiExiled and eiIsAlive every frame, as in the original.

| | before (2026-09-18) | after the bus speed-ups |
| --- | --- | --- |
| match frame (32 ms of game time) | 25.8 ms | 10.1 ms (0.31 x real time) |
| warm-up, 10 s of game time | 6.7 s | 2.3 s |
| `Trigger(eiThink)` on a commander (100 subscribers) | 108 us | 11 us |

What was slow: the handler lookup and `callv` per call, walking every subscriber of an event called to one group,
the event-stack array per event, the 37-way `match` of `EventIdentifierToNetworkSend` on every Trigger, set and
single conversions. Setup: 1.5 s per sandbox game (16 commanders with all their cards) plus 2.3 s of one-off
script and data loading on the first game. Left, if it matters later: the per-frame think-timer reads (~2 us each),
`THealthComponent.OnUnitProperies`, `TMovementComponent.OnIdle`.

## Not yet

- Network (`TServerNetworkComponent`), bots (`TPvPBotComponent`, a bot slot errors), the time manager pause,
  the client game (`TClientGame`).
