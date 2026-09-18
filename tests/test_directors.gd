extends "res://tests/test_case.gd"
## The directors (GameServer/BaseConflict.EntityComponents.Server.pas): TScenarioDirectorComponent (:797, its unit
## pool from the real card database, timed actions, boss waves, squad formation, KI players) with the real
## Scenarios\AttackScenarioBase + AttackScenarioEasy scripts, TServerSandbox{,Command}Component (:435-443),
## TSandboxComponent (Shared.pas:464) and TTutorialDirectorServerComponent (:452).
## Spawns go to a recording server entity manager; entity kills, think blocks and resources use real entities.
## Expected costs come from the golem scripts: GetCardBaseCost (HelperScripts\CardTemplate.dws) is 100 / 150 / 200
## gold for tier 1 / 2 / 3, spawners x8 / x10 / x12 as wood; SmallMeleeGolem is tier 1 with squad 3, SmallRanged
## tier 1 squad 2, MediumMelee tier 2 squad 2, BigMelee tier 3 squad 1, SiegeGolem tier 2 squad 1.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const SCENARIO_BASE = "res://src/content/scripts/server/Scenarios/AttackScenarioBase.dws.gd"
const SCENARIO_EASY = "res://src/content/scripts/server/Scenarios/AttackScenarioEasy.dws.gd"

var _bus: TEventbus
var _game_entity: TEntity
var _probe: GlobalProbe


## Records every spawn as [kind, ...]; returns a dummy entity where the original returns one.
class RecordingManager:
	extends RefCounted
	var Log: Array = []

	func SpawnUnit(Position, Front, PatternFileName = "", League = -1, Level = -1, TeamID = 0, _A = null, _B = null):
		if not Position is Vector2:
			Log.append(["Script", Vector2(Position, Front), PatternFileName, League])
		else:
			Log.append(["Unit", Position, Front, PatternFileName, League, Level, TeamID])
		return null

	func SpawnUnitWithOverwatchAndFlee(Position, Front, PatternFileName, TeamID, FleeDistance):
		Log.append(["Guard", Position, Front, PatternFileName, TeamID, FleeDistance])
		return null

	func SpawnUnitWithoutLimitedLifetime(X: float, Y: float, PatternFileName: String, TeamID: int):
		Log.append(["Permanent", Vector2(X, Y), PatternFileName, TeamID])
		return RefCounted.new()

	func SpawnUnitWithoutLimitedLifetimeWithFront(X: float, Y: float, FX: float, FY: float, PatternFileName: String, TeamID: int):
		Log.append(["PermanentFront", Vector2(X, Y), Vector2(FX, FY), PatternFileName, TeamID])
		return null

	func SpawnSpawner(GridID: int, Coordinate: Vector2i, PatternFileName: String, TeamID: int, Owner: int, Creator):
		Log.append(["Spawner", GridID, Coordinate, PatternFileName, TeamID, Owner, Creator])
		return null

	func Kinds(kind: String) -> Array:
		return Log.filter(func(x): return x[0] == kind)


class FakeMap:
	extends RefCounted
	var Lanes := TLaneManager.new().Create()
	var Clamped: Array = []

	func ClampToZone(Zone: String, Position: Vector2) -> Vector2:
		Clamped.append([Zone, Position])
		return Position


class FakeScenario:
	extends RefCounted
	var MapName := "Single"


class FakeGameInformation:
	extends RefCounted
	var Scenario := FakeScenario.new()
	var ScenarioUID := "duel"


class FakeDirector:
	extends RefCounted
	var Cleared := 0

	func ClearEvents() -> void:
		Cleared += 1


class FakeGame:
	extends RefCounted
	var Map = FakeMap.new()
	var EntityManager = null
	var ServerEntityManager := RecordingManager.new()
	var ScenarioDirector = null
	var Commanders: Array = []
	var GameInformation := FakeGameInformation.new()
	var GameDirector := FakeDirector.new()
	var Overwatch := false
	var OverwatchClearable := false

	func IsShuttingDown() -> bool:
		return false

	func League() -> int:
		return 3


## On the game entity: answers eiGameTickCounter and records the global events the directors send.
class GlobalProbe:
	extends TEntityComponent
	var Tick := 0
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnReadTick", C.eiGameTickCounter, C.epFirst, C.etRead, C.esGlobal))
		e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnGameTick", C.eiGameTick, C.epLast, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnDelayedKill", C.eiDelayedKillEntity, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epLast, C.etTrigger, C.esGlobal))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry[1])
		return Result

	func OnReadTick(_Previous):
		return Tick

	func OnGameEvent(Eventname) -> bool:
		Log.append(["GameEvent", Eventname])
		return true

	func OnGameTick() -> bool:
		Log.append(["GameTick", Tick])
		return true

	func OnDelayedKill(EntityID) -> bool:
		Log.append(["DelayedKill", EntityID])
		return true

	func OnWaveSpawn(GridID, _Coordinate) -> bool:
		Log.append(["WaveSpawn", GridID])
		return true


## On an entity: records resource transactions, stand and fire, with the group they were called to.
class EntityProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnTransaction", C.eiResourceTransaction, C.epFirst, C.etTrigger))
		e.append(XEvent("OnCapTransaction", C.eiResourceCapTransaction, C.epFirst, C.etTrigger))
		e.append(XEvent("OnStand", C.eiStand, C.epFirst, C.etTrigger))
		e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))

	func OnTransaction(Resource, Amount) -> bool:
		Log.append(["Transaction", Resource, Amount, TEventbus.CurrentEvent_CalledToGroup.duplicate()])
		return true

	func OnCapTransaction(Resource, Amount, Overwrite) -> bool:
		Log.append(["Cap", Resource, Amount, Overwrite])
		return true

	func OnStand() -> bool:
		Log.append(["Stand"])
		return true

	func OnFire(Targets) -> bool:
		Log.append(["Fire", Targets, TEventbus.CurrentEvent_CalledToGroup.duplicate()])
		return true


func _setup(real_map := false) -> void:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_bus.EntityDataCache = TEntityDataCache.new().Create(_bus)
	if real_map:
		_bus.Game.Map = TMap.new().CreateFromFile(TMap.MapFile("Single"))
	_game_entity = TEntity.new().Create(_bus, 1)
	_bus.Game.EntityManager = TEntityManagerComponent.new().Create(_game_entity)
	_probe = GlobalProbe.new().Create(_game_entity)


func after_each() -> void:
	TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES.duplicate()
	if _game_entity != null:
		_game_entity.Free()
		if _bus.Game.Map is TMap:
			_bus.Game.Map.Destroy()
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_probe = null
	super()


func _director() -> TScenarioDirectorComponent:
	return TScenarioDirectorComponent.new().Create(_game_entity)


func _unit(director: TScenarioDirectorComponent, identifier: String):
	return director.GetUnitsByIdentifier([identifier])[0]


func _names(units: Array) -> Array:
	return units.map(func(u): return u.Identifier)


func _tick(director: TScenarioDirectorComponent, tick: int) -> void:
	_probe.Tick = tick
	_bus.Trigger(C.eiGameTick, [])


func _entity(id: int, props: Array) -> TEntity:
	var e := TEntity.new().Create(_bus, id)
	e.Blackboard.SetValue(C.eiUnitProperties, [], DSet.Make(props))
	e.Deploy()
	return e


func _classes(e: TEntity) -> Array:
	var Result: Array = []
	e.Eventbus.Trigger(C.eiEnumerateComponents, [func(comp) -> void: Result.append(comp.ClassName())])
	return Result


# --- the scenario director ---

## Colorless, no spawners, no buildings (golem towers), at the game's league: the ten golem drops.
func test_unit_pool() -> void:
	_setup()
	var d := _director().ChooseUnitFaction(C.ecColorless)
	var names := _names(d.FUnitPool)
	names.sort()
	check_eq(names, ["BigCasterGolem", "BigFlyingGolem", "BigMeleeGolem", "BossGolem", "MediumMeleeGolem",
		"SiegeGolem", "SmallCasterGolem", "SmallFlyingGolem", "SmallMeleeGolem", "SmallRangedGolem"], "golem drops")
	check_eq(d.FLeague, 3, "the game's league")
	var small = _unit(d, "SmallMeleeGolem")
	check_eq([small.GoldCost, small.SquadSize, small.WoodCost], [100, 3, 800], "small melee: tier 1, squad 3")
	check_eq(small.DropFilename, "Units\\Colorless\\SmallMeleeGolem", "unit file of the drop")
	check_eq(small.SpawnerFileName, "Units\\Colorless\\SmallMeleeGolemSpawner", "its spawner")
	check_eq(small.Types, [TScenarioDirectorComponent.utUnit, TScenarioDirectorComponent.utGround,
		TScenarioDirectorComponent.utMelee, TScenarioDirectorComponent.utCannonFodder], "scenario unit types")
	var medium = _unit(d, "MediumMeleeGolem")
	check_eq([medium.GoldCost, medium.SquadSize, medium.WoodCost], [150, 2, 1500], "medium melee: tier 2")
	var big = _unit(d, "BigMeleeGolem")
	check_eq([big.GoldCost, big.SquadSize, big.WoodCost], [200, 1, 2400], "big melee: tier 3")
	var boss = _unit(d, "BossGolem")
	check_eq([boss.SpawnerFileName, boss.WoodCost], ["", 0], "the boss golem has no spawner")
	check_eq(d.FDropUnitSubset.FSubset.size(), 10, "drop subset = pool")
	check_eq(d.FSpawnerUnitSubset.FSubset.size(), 10, "spawner subset = pool")
	check_eq(_names(d.GetUnitsByIdentifier(["SiegeGolem", "SiegeGolem"])), ["SiegeGolem", "SiegeGolem"],
		"identifiers resolve in order, duplicates twice")


## Delphi's Shuffle never leaves the last item in place (Exchange(i, Random(i)), Random(i) < i): two items always
## swap, so a two-unit subset alternates between its units whatever the RNG says.
func test_shuffle_and_boss_wave() -> void:
	_setup()
	var d := _director().ChooseUnitFaction(C.ecColorless)
	var list := [1, 2]
	TScenarioDirectorComponent.Shuffle(list)
	check_eq(list, [2, 1], "two items swap")
	seed(7)
	var many := [1, 2, 3, 4, 5]
	TScenarioDirectorComponent.Shuffle(many)
	check(many[4] != 5, "the last item always moves")
	d.RegisterBossWave("First", ["MediumMeleeGolem"], ["SmallMeleeGolem", "SmallRangedGolem"])
	var wave = d.FBossWavePool[0]
	check_eq(wave.FixedGoldValue, 150, "fixed gold value")
	check_eq(_names(wave.ComputeBossWave(200)), ["MediumMeleeGolem", "SmallRangedGolem", "SmallMeleeGolem"],
		"fixed units, then dynamic ones alternating until the 200 gold are spent")
	check_eq(_names(wave.ComputeBossWave(99)), ["MediumMeleeGolem"], "no dynamic unit below its cost")


## Rows behind the point: cannon fodder, tanks / melee, ranged, siege; each row centred, 3 apart; more than 7 in a
## row wrap to the next row, the y offset keeps growing.
func test_squad_formation() -> void:
	_setup()
	var d := _director().SetTeam(5).ChooseUnitFaction(C.ecColorless)
	var manager: RecordingManager = _bus.Game.ServerEntityManager
	d.SpawnUnits(d.GetUnitsByIdentifier(["SiegeGolem", "SmallRangedGolem", "MediumMeleeGolem", "SmallMeleeGolem"]),
		Vector2(86, -23))
	var spawned := manager.Kinds("Unit")
	check_eq(spawned.map(func(x): return [x[1], x[3]]), [
		[Vector2(86, -26), "Units\\Colorless\\SmallMeleeGolem"], [Vector2(86, -23), "Units\\Colorless\\SmallMeleeGolem"],
		[Vector2(86, -20), "Units\\Colorless\\SmallMeleeGolem"],
		[Vector2(89, -24.5), "Units\\Colorless\\MediumMeleeGolem"], [Vector2(89, -21.5), "Units\\Colorless\\MediumMeleeGolem"],
		[Vector2(92, -24.5), "Units\\Colorless\\SmallRangedGolem"], [Vector2(92, -21.5), "Units\\Colorless\\SmallRangedGolem"],
		[Vector2(95, -23), "Units\\Colorless\\SiegeGolem"]], "rows and positions")
	check_eq(spawned[0][6], 5, "the director's team")
	check_eq([spawned[0][4], spawned[0][5]], [TServerEntityManagerComponent.INHERIT_FROM_GAME,
		TServerEntityManagerComponent.INHERIT_FROM_GAME], "league and level of the game")
	check_eq(spawned[0][2], _bus.Game.Map.Lanes.GetOrientationOfNextLane(_bus.Game, Vector2(86, -26), 5),
		"facing the next lane")
	check_eq(_bus.Game.Map.Clamped.size(), 8, "every target clamped to the walk zone")
	check_eq(_names(d.FLastUnitsSpawned).size(), 8, "last units spawned")
	# nine in the front row: seven, then a new row
	manager.Log.clear()
	d.SpawnUnits(d.GetUnitsByIdentifier(["SmallMeleeGolem", "SmallMeleeGolem", "SmallMeleeGolem"]), Vector2(0, 0), true)
	var guards := manager.Kinds("Guard")
	check_eq(guards.map(func(x): return x[1]), [Vector2(0, -12), Vector2(0, -9), Vector2(0, -6), Vector2(0, -3),
		Vector2(0, 0), Vector2(0, 3), Vector2(0, 6), Vector2(3, 9), Vector2(3, 12)], "wrapped row")
	check_eq([guards[0][4], guards[0][5]], [5, 30], "guards: overwatch and flee 30")


## Mirroring: guards on both lanes, each lane rolling its dynamic units anew; the fixed units' cost comes first.
func test_spawn_guards_and_mirroring() -> void:
	_setup()
	var d := _director().SetTeam(5).ChooseUnitFaction(C.ecColorless).EnableMirroring()
	var manager: RecordingManager = _bus.Game.ServerEntityManager
	d.SpawnGuards(-5, -23, ["MediumMeleeGolem"], ["SmallMeleeGolem", "SmallRangedGolem"], 350)
	var guards := manager.Kinds("Guard")
	# per lane: medium (150), then 200 gold: ranged, melee -> 2 + 2 + 3 units
	check_eq(guards.size(), 14, "seven guards per lane")
	check_eq(guards.slice(0, 7).all(func(x): return x[1].y < 0), true, "first lane")
	check_eq(guards.slice(7).all(func(x): return x[1].y > 0), true, "mirrored lane")
	d.SpawnUnit(1.0, -2.0, "Units\\X")
	d.SpawnUnitWithoutLimitedLifetime(3.0, -4.0, "Units\\Y")
	d.SpawnUnitWithoutLimitedLifetimeWithFront(5.0, -6.0, 1.0, 0.0, "Units\\Z")
	check_eq(manager.Kinds("Script"), [["Script", Vector2(1, -2), "Units\\X", 5], ["Script", Vector2(1, 2), "Units\\X", 5]],
		"SpawnUnit mirrored")
	check_eq(manager.Kinds("Permanent"), [["Permanent", Vector2(3, -4), "Units\\Y", 5],
		["Permanent", Vector2(3, 4), "Units\\Y", 5]], "without lifetime mirrored")
	check_eq(manager.Kinds("PermanentFront").size(), 2, "with front mirrored")
	d.DisableMirroring()
	check(d.SpawnUnitWithoutLimitedLifetimeAndReturnEntity(0.0, 0.0, "Units\\Y") != null, "returns the entity")


## Due actions run from the last queued to the first; the KI players think after them.
func test_actions_and_income() -> void:
	_setup()
	var d := _director().AddKIPlayer(2, 86, -23)
	d.ChangeGoldIncome(0, 5).ChangeWoodIncome(0, 7).ChangeGold(10, 50).AddEvent(10, "a").AddEvent(10, "b") \
		.AddEvent(20, "c")
	var player = d.FKIPlayers[0]
	check_eq([player.Buildgrid, player.SpawnPoint], [2, Vector2(86, -23)], "KI player")
	_tick(d, 0)
	check_eq([player.Gold, player.Wood, player.NextGoldSave], [5, 7, 300], "income, then the first (empty) drop")
	_tick(d, 9)
	check_eq(_probe.Named("GameEvent"), [], "nothing due")
	_tick(d, 10)
	check_eq(_probe.Named("GameEvent"), ["b", "a"], "last queued first")
	check_eq(player.Gold, 55, "gold set to 50, then income")
	check_eq(d.FActions.size(), 1, "executed actions dropped")
	_tick(d, 25)
	check_eq(_probe.Named("GameEvent"), ["b", "a", "c"], "late actions run at the next tick")


## Queued at the same tick, the random boss wave (queued last) runs before the registration: it only sees the pool.
func test_random_boss_wave_and_registration() -> void:
	_setup()
	var d := _director().AddKIPlayer(2, 86, -23).ChooseUnitFaction(C.ecColorless)
	var manager: RecordingManager = _bus.Game.ServerEntityManager
	d.RegisterBossWave("A", ["MediumMeleeGolem"], []).RegisterBossWave("B", ["BigMeleeGolem"], [])
	d.RegisterBossWaveAtTime(5, "C", ["SiegeGolem"], []).SpawnRandomBossWave(5, 160).UnregisterBossWaveAtTime(6, "A")
	_tick(d, 5)
	check_eq(manager.Kinds("Unit").map(func(x): return x[3]),
		["Units\\Colorless\\MediumMeleeGolem", "Units\\Colorless\\MediumMeleeGolem"], "only wave A is affordable")
	check_eq(manager.Kinds("Unit")[0][1], Vector2(86, -24.5), "at the KI player's spawn point")
	check_eq(_names(d.FBossWavePool), ["B", "A", "C"], "C registered after (the pool was shuffled)")
	_tick(d, 6)
	check_eq(_names(d.FBossWavePool), ["B", "C"], "A unregistered")
	d.SpawnBossWave(7, "B", 0).DropUnitsNow(7)
	manager.Log.clear()
	_tick(d, 7)
	check_eq(manager.Kinds("Unit").map(func(x): return x[3]), ["Units\\Colorless\\BigMeleeGolem"], "named wave")


## Spawner fields skip the blocked corners 0, 7 and 16; the KI builds the next random spawner once it has the wood.
func test_ki_player_spawners() -> void:
	_setup()
	var d := _director().SetTeam(5).AddKIPlayer(2, 86, -23).ChooseUnitFaction(C.ecColorless)
	var manager: RecordingManager = _bus.Game.ServerEntityManager
	var probe := TScenarioDirectorComponent.KIPlayer.new(d, 0, Vector2.ZERO)
	var fields: Array = []
	for i in 17:
		fields.append(probe.GetNextSpawnerPosition())
	check_eq(fields, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1),
		Vector2i(7, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)], "field order")
	check_eq(probe.SpawnerCount, 20, "all 20 slots used")
	d.ChangeWood(0, 2000).ChangeWoodIncome(0, 10).ChangeUnitSpawnerSubset(0, ["SmallMeleeGolem", "SmallRangedGolem"])
	_tick(d, 0)
	var player = d.FKIPlayers[0]
	check_eq(player.NextSpawner.Identifier, "SmallRangedGolem", "first pick (the subset swapped)")
	_tick(d, 1)
	_tick(d, 2)
	check_eq(manager.Kinds("Spawner").map(func(x): return x.slice(1)), [
		[2, Vector2i(1, 0), "Units\\Colorless\\SmallRangedGolemSpawner", 5, -1, null],
		[2, Vector2i(2, 0), "Units\\Colorless\\SmallMeleeGolemSpawner", 5, -1, null]], "two spawners built")
	check_eq(player.Wood, 2030 - 1600, "800 wood each")
	check_eq(manager.Kinds("Unit"), [], "no drops: no golem costs exactly 300 gold")


## The real attack scenario: base script (map, nexus, boss, build zones, director) and the easy difficulty (towers,
## guards, timed waves), then the first minute of game ticks.
func test_real_attack_scenario() -> void:
	_setup(true)
	var game = _bus.Game
	load(SCENARIO_BASE).new().Apply(_game_entity, game)
	var d: TScenarioDirectorComponent = game.ScenarioDirector
	check(d != null, "director set on the game")
	if d == null:
		return
	check_eq([d.FTeamID, d.FKIPlayers.size(), d.FUnitPool.size(), d.FMirroringEnabled], [C.PVE_TEAM_ID, 1, 10, false],
		"team, KI player, pool, no mirroring")
	var manager: RecordingManager = game.ServerEntityManager
	check_eq(manager.Log[0], ["Script", Vector2(-96, -23), "Units\\Neutral\\NexusLevel1", 1], "the blue nexus")
	check_eq(manager.Log[1], ["Permanent", Vector2(96, -23), "Units\\Scenario\\BossSiegeGolemAttack.ets", C.PVE_TEAM_ID],
		"the boss")
	check(game.Map.BuildZones.TryGetBuildZone(2) != null, "the KI's build zone")
	manager.Log.clear()
	load(SCENARIO_EASY).new().Apply(_game_entity, game)
	check_eq(manager.Kinds("Script").size(), 3, "three lane towers")
	check_eq(manager.Kinds("Permanent").size(), 9, "nine golem towers")
	# guards (two-unit subsets alternate, ranged first): 300 = fixed melee (3) + ranged (2); 400 dynamic = ranged,
	# melee, ranged, melee (10); 500 = fixed 2 medium (4) + ranged (2), 100 dynamic = ranged (2); 0 = fixed only (10)
	check_eq(manager.Kinds("Guard").size(), 5 + 10 + 8 + 10, "guards")
	check_eq(d.FActions.size(), 16, "timed actions queued")
	check_eq(_names(d.FBossWavePool), ["FirstBossWave"], "first boss wave")
	manager.Log.clear()
	for tick in 61:
		_tick(d, tick)
	# wood 2000 + 10 per tick: ranged spawner at 0:01, melee at 0:02, ranged at 0:39 (800 wood each)
	check_eq(manager.Kinds("Spawner").map(func(x): return [x[1], x[2], x[3], x[4]]), [
		[2, Vector2i(1, 0), "Units\\Colorless\\SmallRangedGolemSpawner", C.PVE_TEAM_ID],
		[2, Vector2i(2, 0), "Units\\Colorless\\SmallMeleeGolemSpawner", C.PVE_TEAM_ID],
		[2, Vector2i(3, 0), "Units\\Colorless\\SmallRangedGolemSpawner", C.PVE_TEAM_ID]], "spawners")
	# 1:00, the first boss wave (350): fixed medium, then 200 dynamic: ranged, melee
	check_eq(manager.Kinds("Unit").map(func(x): return DelphiRtl.ExtractFileName(x[3])), ["SmallMeleeGolem", "SmallMeleeGolem",
		"SmallMeleeGolem", "MediumMeleeGolem", "MediumMeleeGolem", "SmallRangedGolem", "SmallRangedGolem"],
		"the first boss wave")
	check_eq(_names(d.FBossWavePool), ["FirstBossWave"], "unregistered only at 1:05")


# --- sandbox ---

func test_sandbox_resources_and_director() -> void:
	_setup()
	var commander := _entity(10, [])
	var log := EntityProbe.new().Create(commander)
	_bus.Game.Commanders = [commander]
	TServerSandboxComponent.new().Create(_game_entity)
	TSandboxComponent.new().Create(_game_entity)
	_bus.Trigger(C.eiGameCommencing, [])
	check_eq(log.Log, [["Cap", C.reGold, 100000.0, true], ["Transaction", C.reGold, 100000.0, []],
		["Transaction", C.reWood, 10000.0, []]], "infinite gold and wood")
	check_eq(_probe.Named("GameEvent"), [C.GAME_EVENT_TECH_LEVEL_2, C.GAME_EVENT_TECH_LEVEL_3], "tech levels")
	check_eq(_bus.Game.GameDirector.Cleared, 1, "the game director's events cleared")


func test_sandbox_commands() -> void:
	_setup()
	TServerSandboxCommandComponent.new().Create(_game_entity)
	var unit := _entity(10, [C.upUnit])
	var golem := _entity(11, [C.upUnit, C.upGolem])
	var nexus := _entity(12, [C.upBase, C.upBuilding])
	var spawner := _entity(13, [C.upSpawner])
	var tower := _entity(14, [C.upLanetower])
	var manager: RecordingManager = _bus.Game.ServerEntityManager
	_bus.Trigger(C.eiClientCommand, [BC.ccClearUnits, null])
	check_eq(_probe.Named("DelayedKill"), [10], "units, not golems nor bases")
	_probe.Log.clear()
	_bus.Trigger(C.eiClientCommand, [BC.ccClearAllUnits, null])
	check_eq(_probe.Named("DelayedKill"), [10, 11], "golems too")
	_probe.Log.clear()
	_bus.Trigger(C.eiClientCommand, [BC.ccClearSpawners, null])
	check_eq(_probe.Named("DelayedKill"), [13], "spawners")
	_probe.Log.clear()
	_bus.Trigger(C.eiClientCommand, [BC.ccClearLaneTowers, null])
	check_eq(_probe.Named("DelayedKill"), [14], "lane towers")
	check_eq(manager.Log, [["Script", Vector2(-48, -23), "Units\\Neutral\\LaneNode", 0],
		["Script", Vector2(0, -23), "Units\\Neutral\\LaneNode", 0],
		["Script", Vector2(48, -23), "Units\\Neutral\\LaneNode", 0]], "lane nodes back on the single lane")
	_probe.Log.clear()
	manager.Log.clear()
	_bus.Game.GameInformation.Scenario.MapName = BC.MAP_DOUBLE
	_bus.Trigger(C.eiClientCommand, [BC.ccBaseBuildingsLevel2, null])
	check_eq(_probe.Named("DelayedKill"), [12], "the nexus")
	check_eq(manager.Log.map(func(x): return [x[1], x[2], x[3]]), [
		[Vector2(-92, 0), "Units\\Neutral\\NexusLevel2", 1], [Vector2(-48, -23), "Units\\Neutral\\LanetowerLevel2", 1],
		[Vector2(0, -23), "Units\\Neutral\\LaneNode", 0], [Vector2(48, -23), "Units\\Neutral\\LanetowerLevel2", 2],
		[Vector2(-48, 23), "Units\\Neutral\\LanetowerLevel2", 1], [Vector2(0, 23), "Units\\Neutral\\LaneNode", 0],
		[Vector2(48, 23), "Units\\Neutral\\LanetowerLevel2", 2], [Vector2(92, 0), "Units\\Neutral\\NexusLevel2", 2]],
		"classic PvP base buildings")
	manager.Log.clear()
	_bus.Game.GameInformation.Scenario.MapName = BC.MAP_SINGLE
	_bus.Game.GameInformation.ScenarioUID = "pve_attack_solo"
	_bus.Trigger(C.eiClientCommand, [BC.ccBaseBuildingsLevel1, null])
	check_eq(manager.Log.map(func(x): return [x[1], x[2]]), [[Vector2(-96, -23), "Units\\Neutral\\NexusLevel1"],
		[Vector2(-48, -23), "Units\\Neutral\\LaneNode"], [Vector2(0, -23), "Units\\Neutral\\LaneNode"],
		[Vector2(48, -23), "Units\\Neutral\\LaneNode"]], "PvE: only the blue nexus and lane nodes")
	var nexus_log := EntityProbe.new().Create(nexus)
	_bus.Trigger(C.eiClientCommand, [BC.ccBaseBuildingsIndestructible, null])
	check_eq(nexus_log.Log.map(func(x): return x.slice(0, 3)), [["Cap", C.reHealth, 1000000.0],
		["Transaction", C.reHealth, 1000000.0], ["Cap", C.reMana, 10000], ["Transaction", C.reMana, 10000]],
		"indestructible bases")
	_bus.Trigger(C.eiClientCommand, [BC.ccToggleOverwatch, null])
	_bus.Trigger(C.eiClientCommand, [BC.ccToggleOverwatchSandbox, null])
	check_eq([_bus.Game.Overwatch, _bus.Game.OverwatchClearable], [true, true], "overwatch switches")
	TBrainOverwatchSandboxComponent.new().Create(unit)
	check(_classes(unit).has("TBrainOverwatchSandboxComponent"), "sandbox overwatch on the unit")
	_bus.Trigger(C.eiClientCommand, [BC.ccClearOverwatch, null])
	check(not _classes(unit).has("TBrainOverwatchSandboxComponent"), "cleared")
	_bus.Trigger(C.eiClientCommand, [BC.ccForceGameTick, null])
	check_eq(_probe.Named("GameTick").size(), 1, "forced game tick")
	check(golem != null and spawner != null, "entities alive")


# --- tutorial ---

func test_tutorial_freeze() -> void:
	_setup()
	TTutorialDirectorServerComponent.new().Create(_game_entity)
	var unit := _entity(10, [C.upUnit])
	var log := EntityProbe.new().Create(unit)
	var charm := _entity(11, [C.upCharm])
	_bus.Trigger(C.eiClientCommand, [BC.ccTutorialGameEvent, C.GAME_EVENT_FREEZE_GAME])
	check(_classes(unit).has("TThinkBlockComponent"), "units blocked")
	check(not _classes(charm).has("TThinkBlockComponent"), "charms not")
	check_eq(log.Log, [["Stand"]], "units stand")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_FREEZE_GAME])
	check_eq(_classes(unit).count("TThinkBlockComponent"), 1, "freezing twice blocks once")
	var late := _entity(12, [C.upUnit])
	check(_classes(late).has("TThinkBlockComponent"), "new entities blocked while frozen")
	_bus.Trigger(C.eiGameTick, [])
	check_eq(_probe.Named("GameTick"), [], "no game tick while frozen")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_UNFREEZE_GAME])
	check(not _classes(unit).has("TThinkBlockComponent") and not _classes(late).has("TThinkBlockComponent"),
		"unfrozen")
	_bus.Trigger(C.eiGameTick, [])
	check_eq(_probe.Named("GameTick").size(), 1, "game ticks again")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_SKIP_WARMING])
	check_eq(_probe.Named("GameTick").size(), 2, "skipping the warming ticks once")


func test_tutorial_switches_and_resources() -> void:
	_setup()
	TTutorialDirectorServerComponent.new().Create(_game_entity)
	var commander := _entity(10, [])
	var log := EntityProbe.new().Create(commander)
	TResourceManagerComponent.new().Create(commander)
	_bus.Game.Commanders = [commander]
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_DEACTIVATE_SPAWNER])
	_bus.Trigger(C.eiWaveSpawn, [2, Vector2i.ZERO])
	check_eq(_probe.Named("WaveSpawn"), [], "wave spawns stopped")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_ACTIVATE_SPAWNER])
	_bus.Trigger(C.eiWaveSpawn, [2, Vector2i.ZERO])
	check_eq(_probe.Named("WaveSpawn"), [2], "and on again")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_DEACTIVATE_INCOME])
	var zero := RIncome.FromRParam(_bus.Read(C.eiIncome, [10]))
	check_eq([zero.Gold, zero.Wood], [0.0, 0.0], "no income")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_ACTIVATE_INCOME])
	check_eq(_bus.Read(C.eiIncome, [10]), null, "income passes through")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_DEACTIVATE_CARD_COST])
	check(TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES.has(C.reGold) and
		TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES.has(C.reCharge), "cards are free")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_ACTIVATE_CARD_COST])
	check_eq(TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES, TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES,
		"cards cost again")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_REFRESH_GOLD])
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_GIVE_GOLD_PREFIX + "250"])
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_GIVE_WOOD_PREFIX + "x"])
	check_eq(log.Log.map(func(x): return x.slice(0, 3)), [["Transaction", C.reGold, 10000.0],
		["Transaction", C.reGold, 250.0], ["Transaction", C.reWood, 100.0]], "refill, give, default 100")
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_SET_WOOD_PREFIX + "7"])
	check_eq(commander.Blackboard.GetIndexedValue(C.eiResourceBalance, [], C.reWood), 7.0, "wood set")
	log = EntityProbe.new().CreateGrouped(commander, [3, 4, 5])
	commander.Blackboard.SetIndexedValue(C.eiResourceCap, [3], C.reCharge, 2)
	commander.Blackboard.SetValue(C.eiDamageType, [4], [C.dtCharge])
	commander.Blackboard.SetValue(C.eiDamageType, [5], DSet.Make([C.dtCharge, C.dtRanged]))
	_bus.Trigger(C.eiGameEvent, [C.GAME_EVENT_REFRESH_CHARGES])
	check_eq(log.Log.map(func(x): return [x[0], x[1] if x[0] == "Transaction" else x[1].size(), x[-1]]),
		[["Transaction", C.reCharge, [3]], ["Fire", 1, [4]]], "charges refilled, pure charge welas fired")
	check(log.Log[1][1][0].IsEmpty(), "at one empty target")


func test_str_to_int_def() -> void:
	check_eq([DelphiRtl.StrToIntDef("250", 100), DelphiRtl.StrToIntDef(" -12", 100), DelphiRtl.StrToIntDef("$1F", 0),
		DelphiRtl.StrToIntDef("0x10", 0), DelphiRtl.StrToIntDef("", 100), DelphiRtl.StrToIntDef("12a", 100),
		DelphiRtl.StrToIntDef("2147483648", 100), DelphiRtl.StrToIntDef("-2147483648", 100)],
		[250, -12, 31, 16, 100, 100, 100, -2147483648], "Val rules")
