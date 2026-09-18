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

## Not yet

- Network (`TServerNetworkComponent`), bots (`TPvPBotComponent`, a bot slot errors), the time manager pause,
  the client game (`TClientGame`).
- Performance: the headless sandbox runs only about as fast as real time with ~15 units (an exploratory run of
  ~110 s of game time took ~3 min of wall time, startup included). Profile before phase 5.
