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
| `TGameThread` | same file, `:198` | one frame = `DoComputeGame` (own clock swapped in): TickTack, Idle, debug ticks, player state machine (waiting -> running = `Start` / aborted; running -> crashed when all players left); finished -> terminated + eiServerShutdown. Owns the `TServerNetworkComponent` |
| `TGameManager` (setups only) | same file, `:255-727` | the test server's sandbox game and its decks (`CreateTestserverGameInfo`, player token `"1"`) |
| `TClientGame` (part) | `BaseConflict.Game.Client.pas:79` | the client's game on a client bus: client map with decorations, collision and entity manager, `TClientNetworkComponent`, scenario scripts' client part (`Initialize`), game state (preparing -> running on the world's arrival). `JoinLocal` = the loading state's connect, `ReadyWhenLoaded` = the core state's client-ready. Input, camera, GUI, sound, commander manager, decay, minimap, build grid: not yet |
| Network (see below) | `...Shared.pas` `TNetworkComponent`, `...Server.pas` `TServerNetworkComponent`, `...Client.pas` `TClientNetworkComponent` | events and entities between server and client |

## Flow

1. `TGameThread.new().Create(GameInfo)`: `UpdateGamePlayers`, `TServerGame.Create` (bus, game entity,
   tick + director, map, managers), the entity data cache on the bus, then `PrepareGame` = `Initialize`:
   the scenario scripts (e.g. sandbox: Game, PvPBlue, PvPRed, PvPBase, Sandbox) spawn nexus / towers / lane node,
   add build zones and director events; then the commanders from `Commander\CommanderTemplate` with their cards,
   token mapping, surrender, eiAfterCreate on the game entity.
2. The owner calls `DoComputeGame` every frame (the original aims at 32 ms, `TARGET_FRAMETIME`). Tests step
   `TTimeManager.FakeTime` by 32 ms per frame.
3. All players playing (a client joined and sent NET_CLIENT_READY; headless runs without clients call
   `SetAllPlayersPlaying`) -> next frame `Start` -> eiGameCommencing: 10 s warm-up
   (`InGameStatus` loading -> warming -> playing), then eiGameTick; the first tick fires eiGameStart.
4. Ticks: the tick timer restarts at the frame that fires it, so at 32 ms frames a tick comes every 1024 ms
   (the original drifts the same way). Game.dws pays income per tick and triggers a wave every 2nd tick.
5. A nexus death -> eiLose -> `TeamLost` -> `IsFinished`; the next frame terminates the thread.

## Conventions

- The functions of `TGame` are methods, as in the original (`League()`, `IsSandbox()`, `HasStarted()`,
  `IsShuttingDown()`, `GameInformation.IsTutorial()`), properties stay properties (`InGameStatus`, `ServerTime`,
  `Map`, `EntityManager`, `Commanders`...). Test fakes of the game must follow this.
- The globals `Game`, `ServerGame`, `Map`, `GlobalEventbus`, `Overwatch` are the bus's `Game` and its members.
- `TTimeManager` is static; `TickTack` sets `ZDiff`. The server game keeps its own frame state (the original's
  per-thread `GameTimeManager`): `DoComputeGame` swaps it in (`SaveClock` / `RestoreClock`), so a client in the same
  process has its own `ZDiff` (its frame: `TTimeManager.TickTack`, eiIdle, `ReadyWhenLoaded`, `Idle`).

## Network

The original's game server and client are separate programs on TCP. The port runs both in one process over
`TLoopbackSocket` pairs (stand-in for `TTCPClientSocketDeluxe`: queued copies of `TCommandSequence` packets, send
order, no latency) and keeps the protocol:
1. Connect (`TClientGame.JoinLocal`): the server end goes to `TServerNetworkComponent.OnClientConnect`; the client
   sends NET_HELLO_SERVER + token; the server's next frame assigns the socket to that token's `TNetworkPlayer`
   (psPreparing) and answers NET_ASSIGNED_PLAYER with the token's commander IDs (unknown token: NET_SECURITY_ERROR).
2. `TClientGame.Create` makes `TClientNetworkComponent`, which sends NET_CLIENT_ENTER_CORE; the server answers with
   the world (`SendWorld`: NET_NEW_ENTITY with every deployed entity that has a script, then
   NET_SERVER_FINISHED_SEND_GAME_DATA). The client builds each entity (`TEntity.Deserialize`, TLogicToWorldComponent,
   eiAfterCreate, Deploy), then runs the token mapping: game state running.
3. The client says it is ready (eiClientReady -> NET_CLIENT_READY): psPlaying; with all players playing the game starts.
4. From then on: entities the server makes go out by eiSendEntities; every event that `EventIdentifierToNetworkSend`
   gives to the sender's side goes out as NET_EVENT (entity ID, event, group, component ID, write flag, parameters)
   and is invoked on the receiver's copy (`EntityManager.InvokeEventOnEntity`, 0 = global bus, 1 = game entity;
   unknown IDs are dropped). Client events (eiUseAbility, eiSurrender, eiClientCommand) go the other way: a card
   played on the client's commander copy reaches the server. Every packet to a player carries its send index last.

**Parameters** (`TNetworkComponent.RawParameters`): the original copies each parameter's raw bytes and the receiver
reads them by memory cast (as the port's `RParam` accessors do). Size-0 values (empty strings, empty arrays) arrive
empty; records the port keeps as objects are cloned. Deviation: a non-empty string arrives as sent. In the original
its UTF-16 bytes arrive untyped and `AsString` hard-casts the raw heap data to a string (at best twice as long with
garbage, short ones have no heap data at all). So network-sent string events (eiGameEvent) look unusable over a
real connection. Not verified in a running original.

**Serialized components** (`TSerializableEntityComponent`): with its entity the server sends each serializable
component: class (`XNetworkBaseType`: `TServerPrimaryTargetComponent` goes as `TPrimaryTargetComponent`), UniqueID,
group, fields. The client creates that component on its copy. This is how server-only components of the scripts
reach the client: `TMovementComponent` (the unit walks there), `THealthComponent`, `TPrimaryTargetComponent`, and
`TCommanderAbilityComponent` (whose client Init puts the cards on the client's commander). Which fields: the class's
**public and protected** fields, not private ones. This was derived, not compiled: the Delphi here is the Community
edition (no command-line compiler for an RTTI probe). The reasoning: TMovementComponent's private `FSyncTimer` is a
TTimer, and `Serialize` raises on class fields, so private fields cannot be in the RTTI (every unit sent would
crash the server). TCommanderAbilityComponent's protected card fields must arrive, or the client could not
resolve its cards (its comment says record fields with strings "explode" on deserialization). The forward
declaration `TEntityComponent = class;` stands under `{$RTTI EXPLICIT ... FIELDS([vcPublic, vcProtected])}`, and
the units' `{$RTTI INHERIT}` fits. `XNetworkSerialize(eiMoveTo)` on `FTarget`: after deserializing, the entity
Writes eiMoveTo [target] (a write: stored on the blackboard; TMovementComponent's handler is a trigger).

Not ported: reconnect (NET_RECONNECT, the resend buffer), ping log, TCP, packets split at `MAX_PACKET_SIZE` (one
NET_NEW_ENTITY packet, same order), the master-server report, the client's end screen (`TClientEntityManagerComponent`).
Tests: `tests/test_network.gd` (loopback, parameters, refused token, handshake + world + start, and a live match
where cards played on the client come back as units that walk, fight and die on both sides).

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

- Bots (`TPvPBotComponent`, a bot slot errors), the time manager pause, the rest of the client game (input,
  camera, HUD, commander manager, end screen).
