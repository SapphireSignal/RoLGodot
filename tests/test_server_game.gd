extends "res://tests/test_case.gd"
## The game loop: HScenario / TScenarioInfoManager (BaseConflict.Constants.Scenario.pas), TGameDirectorComponent and
## TGameTickComponent (BaseConflict.EntityComponents.Shared.pas:59, :356), and a real sandbox game
## (TGameManager.CreateTestserverGameInfo, GameServer/BaseConflict.Game.Server.pas:531) run by TGameThread.
## Expected values come from the scripts: Scenarios\Game.dws adds tech level 2 at i([3,3,3,4,4], League) * 60 =
## tick 180 in league 1 (no showdown in a sandbox, no tech 3 in a PvP league 1); PvPRed / PvPBlue put the nexus at
## (+-96, -23) and a lane tower at (+-48, -23), PvPBase the lane node at (0, -23); Commander\CommanderTemplate starts
## with Game.StartingGold 300 of cap 400, 1600 wood, tier 1, 10 gold income per payout (every game tick). The sandbox
## (TServerSandboxComponent) gives every commander +100000 gold cap (unfilled), +100000 gold, +10000 wood and both
## tech levels when the game commences; each tech level adds Game.GoldCapPerTier = 100 to the gold cap.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const FRAME = 32.0  # TGameThread.TARGET_FRAMETIME

var _thread: TGameThread
var _bus: TEventbus
var _game_entity: TEntity


## On the game entity: records the global game flow events.
class FlowProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnGameCommencing", C.eiGameCommencing, C.epLast, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnGameStart", C.eiGameStart, C.epLast, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnGameTick", C.eiGameTick, C.epLast, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epLast, C.etTrigger, C.esGlobal))

	func Named(name: String) -> Array:
		return Log.filter(func(x): return x[0] == name)

	func OnGameCommencing() -> bool:
		Log.append(["Commencing", TTimeManager.GetFakeTime()])
		return true

	func OnGameStart() -> bool:
		Log.append(["Start", TTimeManager.GetFakeTime()])
		return true

	func OnGameTick() -> bool:
		Log.append(["Tick", TTimeManager.GetFakeTime()])
		return true

	func OnGameEvent(Eventname) -> bool:
		Log.append(["Event", Eventname])
		return true


func after_each() -> void:
	if _thread != null:
		_thread.Free()
	_thread = null
	if _game_entity != null:
		_game_entity.Free()
		_bus.Free()
	_game_entity = null
	_bus = null
	TTimeManager.SetFakeTime(null)
	TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES.duplicate()
	super()


# --- scenarios ---

func test_scenario_predicates_follow_the_uid() -> void:
	check(HScenario.IsPvP("sandbox") and HScenario.IsSandbox("sandbox"), "the sandbox is a PvP sandbox")
	check(not HScenario.IsDuo("sandbox") and HScenario.IsSingle("sandbox"), "the sandbox is single")
	check(HScenario.IsDuo("sandbox_duo") and HScenario.IsTeamMode("sandbox_duo"), "sandbox duo")
	check(HScenario.IsPvEScenario("pve_attack_solo") and not HScenario.IsPvP("pve_attack_solo"), "PvE attack")
	check(HScenario.IsDuo("pve_attack") and not HScenario.IsDuo("pve_attack_solo"), "attack duo by its ending")
	check(HScenario.IsTeamMode("duel2v2") and not HScenario.IsTeamMode("duel"), "duel team mode")
	check(HScenario.IsTutorial("tutorial") and HScenario.IsPvEScenario("tutorial"), "the tutorial is PvE")
	check(HScenario.IsPvP("ranked1vs1"), "ranked PvP")
	# kept: the PvE sandbox ends with 'sandbox', so it counts as PvP too
	check(HScenario.IsPvP("pve_sandbox") and HScenario.IsPvEScenario("pve_sandbox"), "PvE sandbox is both")


func test_scenario_info_manager_resolves_scripts_and_maps() -> void:
	var sandbox := HScenario.ResolveScenario("Sandbox", 3)
	check_eq(sandbox.ScenarioScriptfile, ["\\Scripts\\Scenarios\\Sandbox.dws", "\\Scripts\\Scenarios\\PvPBase.dws",
		"\\Scripts\\Scenarios\\PvPRed.dws", "\\Scripts\\Scenarios\\PvPBlue.dws", "\\Scripts\\Scenarios\\Game.dws"],
		"additional scripts first, then the PvP scripts")
	check_eq(sandbox.MapName, BC.MAP_SINGLE, "sandbox map")
	check(sandbox != HScenario.ResolveScenario("sandbox", 4), "one clone per league")
	var attack := HScenario.ResolveScenario("pve_attack", 2)
	check_eq(attack.ScenarioScriptfile[0], "\\Scripts\\Scenarios\\AttackDuoScenarioEasy.dws", "league 2 is easy")
	check_eq(attack.MapName, BC.MAP_DOUBLE, "duo map")
	check_eq(HScenario.ResolveMutator("Gigantic").MutatorScriptfile, ["\\Scripts\\Scenarios\\Mutators\\Gigantic.dws"],
		"mutator")


# --- game director and game tick ---

func _game_entity_setup() -> FlowProbe:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_game_entity = TEntity.new().Create(_bus, 1)
	TGameTickComponent.new().Create(_game_entity)
	return FlowProbe.new().Create(_game_entity)


func test_game_director_fires_due_events_last_added_first() -> void:
	TTimeManager.SetFakeTime(0.0)
	var probe := _game_entity_setup()
	var director := TGameDirectorComponent.new().Create(_game_entity)
	director.AddEvent(2, "Tech2").AddEventIf(false, 1, "never").AddEvent(1, "early").AddEvent(2, "Second")
	check_eq(_bus.Read(C.eiGameEventTimeTo, ["tech2"]), 2, "ticks to tech2")
	check_eq(_bus.Read(C.eiGameEventTimeTo, ["Tech2"]), -1, "names are stored lower case")
	check_eq(_bus.Read(C.eiGameEventTimeTo, ["never"]), -1, "a false condition adds nothing")
	_bus.Trigger(C.eiGameTick, [])
	check_eq(probe.Named("Event"), [["Event", "early"]], "tick 1")
	_bus.Trigger(C.eiGameTick, [])
	check_eq(probe.Named("Event"), [["Event", "early"], ["Event", "second"], ["Event", "tech2"]], "tick 2, last added first")
	check_eq(_bus.Read(C.eiGameEventTimeTo, ["tech2"]), -1, "fired events are gone")


func test_game_tick_warms_up_then_ticks_every_second() -> void:
	TTimeManager.SetFakeTime(1000.0)
	var probe := _game_entity_setup()
	check_eq(_bus.Read(C.eiGameTickTimeToFirstTick, []), BC.GAME_WARMING_DURATION, "paused before commencing")
	_bus.Trigger(C.eiIdle, [])
	check_eq(probe.Named("Tick"), [], "no tick while loading")
	_bus.Trigger(C.eiGameCommencing, [])
	TTimeManager.SetFakeTime(4000.0)
	check_eq(_bus.Read(C.eiGameTickTimeToFirstTick, []), 7000, "warm-up left")
	TTimeManager.SetFakeTime(10999.0)
	_bus.Trigger(C.eiIdle, [])
	check_eq(probe.Named("Tick"), [], "not yet")
	TTimeManager.SetFakeTime(11000.0)
	_bus.Trigger(C.eiIdle, [])
	check_eq(probe.Log, [["Commencing", 1000.0], ["Start", 11000.0], ["Tick", 11000.0]], "first tick starts the game")
	check_eq(_bus.Read(C.eiGameTickCounter, []), 1, "counter")
	check_eq(_bus.Read(C.eiGameTickTimeToFirstTick, []), 0, "ticking")
	_bus.Trigger(C.eiGameCommencing, [])
	TTimeManager.SetFakeTime(11999.0)
	_bus.Trigger(C.eiIdle, [])
	TTimeManager.SetFakeTime(12000.0)
	_bus.Trigger(C.eiIdle, [])
	check_eq(probe.Named("Tick"), [["Tick", 11000.0], ["Tick", 12000.0]], "then one tick per second")
	check_eq(probe.Named("Start").size(), 1, "one start")
	check_eq(_bus.Read(C.eiGameTickCounter, []), 2, "counter")


# --- the sandbox game ---

func _sandbox() -> TServerGame:
	TTimeManager.SetFakeTime(1000.0)
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	return _thread.InternalGame


## One frame of the game thread, TARGET_FRAMETIME after the last.
func _frame() -> void:
	TTimeManager.SetFakeTime(TTimeManager.GetFakeTime() + FRAME)
	_thread.DoComputeGame()


func _run_until(ms: float) -> void:
	while TTimeManager.GetFakeTime() + FRAME <= ms:
		_frame()


func _card_group(commander: TEntity, pattern: String) -> int:
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == pattern:
			return g
	return -1


func _balance(commander: TEntity, resource: int) -> float:
	return RParam.AsSingle(commander.Blackboard.GetIndexedValue(C.eiResourceBalance, [], resource))


## reTier is an integer resource.
func _tier(commander: TEntity) -> int:
	return RParam.AsInteger(commander.Blackboard.GetIndexedValue(C.eiResourceBalance, [], C.reTier))


func _units(game: TServerGame, property: int) -> Array:
	var Result: Array = []
	for entity: TEntity in game.EntityManager.FilterEntities([property], []):
		Result.append([entity.TeamID(), entity.Position])
	Result.sort()
	return Result


func test_sandbox_game_sets_up_the_scenario_and_the_commanders() -> void:
	var game := _sandbox()
	check_eq(TEntity.LastScriptError, "", "no script error")
	check(game.IsSandbox() and game.IsPvP() and game.IsOneLane() and not game.HasShowdown(), "a one lane sandbox")
	check_eq(game.League(), 1, "test server league")
	check_eq(game.InGameStatus, BC.gsLoading, "loading")
	check_eq(game.Commanders.size(), 16, "15 slots and a spectator")
	var teams: Array = game.Commanders.map(func(c: TEntity) -> int: return c.TeamID())
	check_eq(teams, [1, 2, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 5, 0], "sandbox decks first, spectator last")
	check_eq(game.GetTeamCount(), 5, "highest team ID")
	check_eq(game.GetCommandersPerTeam(2).size(), 7, "team 2")
	var ids: Array = game.Commanders.map(func(c: TEntity) -> int: return c.ID)
	# 1 is the game entity; the scenario's 5 units (2 nexus, 2 lane towers, the lane node) come first
	check_eq(ids, range(7, 23), "IDs from the entity manager")
	var player: TEntity = game.Commanders[0]
	check_eq(player.Eventbus.Read(C.eiOwnerCommander, []), player.ID, "owns itself")
	check_eq(player.Eventbus.Read(C.eiPlayerOwner, []), "Player", "player name")
	for pattern in ["Units\\White\\FootmanDrop", "Units\\White\\ArcherDrop", "Units\\White\\BallistaDrop",
			"Units\\White\\DefenderDrop", "Units\\White\\ArcherSpawner", "Units\\White\\FootmanSpawner"]:
		check(_card_group(player, pattern) >= 0, "sandbox deck card " + pattern)
	check_eq(_balance(player, C.reGold), 300.0, "starting gold")
	check_eq(RParam.AsSingle(player.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reGold)), 400.0, "gold cap")
	check_eq(_balance(player, C.reWood), 1600.0, "starting wood")
	check_eq(_tier(player), 1, "tier")
	check_eq(_bus_of(game).Read(C.eiTokenMapping, ["1"]), range(7, 22), "the player controls the 15 slots")
	check_eq(_bus_of(game).Read(C.eiTokenMapping, [""]), [22], "the spectator")
	check_eq(_bus_of(game).Read(C.eiTokenMapping, ["2"]), null, "unknown token")
	check_eq(_units(game, C.upNexus), [[1, Vector2(-96, -23)], [2, Vector2(96, -23)]], "nexuses")
	check_eq(_units(game, C.upLanetower), [[1, Vector2(-48, -23)], [2, Vector2(48, -23)]], "lane towers")
	check_eq(_units(game, C.upLaneNode), [[0, Vector2(0, -23)]], "lane node")
	check_eq(game.Map.BuildZones.GetBuildZone(0).TeamID, 1, "blue build zone")
	check_eq(game.Map.BuildZones.GetBuildZone(1).TeamID, 2, "red build zone")
	check_eq(_bus_of(game).Read(C.eiGameEventTimeTo, [C.GAME_EVENT_TECH_LEVEL_2]), 180, "tech 2 at 3 minutes")
	check_eq(_bus_of(game).Read(C.eiGameEventTimeTo, [C.GAME_EVENT_TECH_LEVEL_3]), -1, "no tech 3 in PvP league 1")
	check_eq(_bus_of(game).Read(C.eiGameEventTimeTo, [C.GAME_EVENT_SHOWDOWN]), -1, "no showdown in the sandbox")


func _bus_of(game: TServerGame) -> TEventbus:
	return game.GlobalEventbus


func test_sandbox_game_starts_when_the_players_play() -> void:
	var game := _sandbox()
	var probe := FlowProbe.new().Create(game.GameEntity)
	_run_until(2000.0)
	check_eq(probe.Log, [], "waits for the players")
	check_eq(game.InGameStatus, BC.gsLoading, "loading")
	check_eq(TThreadContext.Current().GameTimeManager.ZDiff, FRAME, "frame time")
	_thread.SetAllPlayersPlaying()
	_frame()
	var commenced: float = TTimeManager.GetFakeTime()
	check_eq(probe.Named("Commencing"), [["Commencing", commenced]], "the game commences")
	check_eq(game.InGameStatus, BC.gsLoading, "still loading: the full warm-up is left")
	TTimeManager.SetFakeTime(TTimeManager.GetFakeTime() + 1.0)
	check_eq(game.InGameStatus, BC.gsWarming, "warming")
	TTimeManager.SetFakeTime(TTimeManager.GetFakeTime() - 1.0)
	var player: TEntity = game.Commanders[0]
	check_eq(_balance(player, C.reGold), 100300.0, "sandbox gold")
	check_eq(_balance(player, C.reWood), 11600.0, "sandbox wood")
	check_eq(_tier(player), 3, "both tech levels")
	check_eq(RParam.AsSingle(player.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reGold)), 100600.0,
		"gold cap: 400 + 100000, plus 100 per tier upgrade")
	_run_until(commenced + BC.GAME_WARMING_DURATION - 1.0)
	check_eq(probe.Named("Tick"), [], "warm-up")
	_frame()
	var first_tick: float = TTimeManager.GetFakeTime()
	check(first_tick >= commenced + BC.GAME_WARMING_DURATION, "after the warm-up")
	check_eq(probe.Named("Start"), [["Start", first_tick]], "the game starts at the first tick")
	check_eq(game.InGameStatus, BC.gsPlaying, "playing")
	check(game.HasStarted(), "started")
	check_eq(_balance(player, C.reGold), 100310.0, "income at the first tick")
	# the tick timer restarts at the frame that fires it: at 32 ms frames a tick comes every 1024 ms
	_run_until(first_tick + 3 * 1024.0 - 1.0)
	check_eq(_bus_of(game).Read(C.eiGameTickCounter, []), 3, "not yet the 4th tick")
	_frame()
	check_eq(TTimeManager.GetFakeTime(), first_tick + 3 * 1024.0, "4th tick frame")
	check_eq(_bus_of(game).Read(C.eiGameTickCounter, []), 4, "a tick per 1024 ms")
	check_eq(_balance(player, C.reGold), 100340.0, "10 gold per tick")
	check_eq(TEntity.LastScriptError, "", "no script error")


func test_team_lost_finishes_the_game() -> void:
	var game := _sandbox()
	var probe := FlowProbe.new().Create(game.GameEntity)
	_thread.SetAllPlayersPlaying()
	_frame()
	var nexus: TEntity = game.EntityManager.NexusByTeamID(2)
	nexus.Eventbus.Trigger(C.eiKill, [-1, -1])
	_frame()
	_frame()
	check(game.IsFinished, "finished")
	check_eq(game.BuildStatistics()["winner_team_id"], 1, "team 1 won")
	var ticks_before: int = probe.Named("Tick").size()
	_frame()
	check(_thread.Terminated, "the thread ends")
	check_eq(_thread.GameFinishedState, TGameThread.gfFinished, "finished state")
	check_eq(probe.Named("Tick").size(), ticks_before, "no more idle")


func test_surrender_kills_the_nexus() -> void:
	var game := _sandbox()
	_thread.SetAllPlayersPlaying()
	_frame()
	_bus_of(game).Trigger(C.eiSurrender, [1])
	check_eq(game.FSurrenderedTeamID, 1, "surrendered")
	_frame()
	_frame()
	check(game.IsFinished, "the nexus died, team 1 lost")
	check_eq(game.FWinnerTeamID, 2, "team 2 won")
