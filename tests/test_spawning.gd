extends "res://tests/test_case.gd"
## The spawning family: TGameStatisticManager, RTarget.ComputeSpawningPattern / GetRealBuildPosition,
## TServerEntityManagerComponent (GameServer/BaseConflict.EntityComponents.Server.pas:1817), the effects
## TWelaEffect{Factory,Replace,Projectile}Component + TProjectileEventRedirecter (...Server.Welas.pas:997-1947, :2626),
## the brains TBrain{Spawner,CapturePoint}Component (...Server.Brains.Special.pas), and real scripts: a
## VoidSkeletonSpawner placed on a build field spawning its squad, and a dying golem's soul flying to a soul gatherer.
## The game has the real server entity manager and collision manager, a fake map (real build zones and lanes, walk
## zone clamping recorded) and a delayed-event queue pumped like TServerGame.Idle.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TServerEntityManagerComponent
var _log: GlobalLog


class FakeMap:
	extends RefCounted
	var MapBoundaries := Rect2(-150, -150, 300, 300)
	var Lanes := TLaneManager.new().Create()
	var BuildZones := TBuildZoneManager.new()
	var Pathfinding = null
	var Clamped: Array = []

	func ClampToZone(Zone: String, Position: Vector2) -> Vector2:
		Clamped.append([Zone, Position])
		return Position


class FakeGame:
	extends RefCounted
	var Commanders: Array = []
	var Sandbox := false
	var Overwatch := false
	var OverwatchClearable := false
	var InGameStatus := 2  # BC.gsPlaying
	var Map := FakeMap.new()
	var EntityManager = null
	var ServerEntityManager = null
	var CollisionManager = null
	var Statistics := TGameStatisticManager.new().Create()
	var DelayedEvents := TIntPriorityQueue.new()

	func IsShuttingDown() -> bool:
		return false

	func IsSandbox() -> bool:
		return Sandbox

	func HasStarted() -> bool:
		return false

	func League() -> int:
		return 3


## Global traffic, on the game entity: [name, parameters...] in call order.
class GlobalLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnSend", C.eiSendEntities, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnDelayedKill", C.eiDelayedKillEntity, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnKill", C.eiKillEntity, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnReplace", C.eiReplaceEntity, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epFirst, C.etTrigger, C.esGlobal))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func OnSend(Entities) -> bool:
		Log.append(["Send", Entities.map(func(x): return x.ID)])
		return true

	func OnDelayedKill(EntityID) -> bool:
		Log.append(["DelayedKill", EntityID])
		return true

	func OnKill(EntityID) -> bool:
		Log.append(["Kill", EntityID])
		return true

	func OnReplace(OldID, NewID, IsSame) -> bool:
		Log.append(["Replace", OldID, NewID, IsSame])
		return true

	func OnWaveSpawn(GridID, Coordinate) -> bool:
		Log.append(["WaveSpawn", GridID, Coordinate])
		return true


## Entity traffic (ALLGROUP): [name, called-to group, parameters...] in call order.
class EntityLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
		e.append(XEvent("OnDeploy", C.eiDeploy, C.epLast, C.etTrigger))
		e.append(XEvent("OnProduced", C.eiWelaUnitProduced, C.epFirst, C.etTrigger))
		e.append(XEvent("OnShot", C.eiWelaShotProjectile, C.epFirst, C.etTrigger))
		e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnShame", C.eiYouHaveKilledMeShameOnYou, C.epFirst, C.etTrigger))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func _group() -> Array:
		return TEventbus.CurrentEvent_CalledToGroup.duplicate()

	func OnAfterCreate() -> bool:
		Log.append(["AfterCreate", _group()])
		return true

	func OnDeploy() -> bool:
		Log.append(["Deploy", _group()])
		return true

	func OnProduced(EntityID) -> bool:
		Log.append(["Produced", _group(), EntityID])
		return true

	func OnShot(Projectile) -> bool:
		Log.append(["Shot", _group(), Projectile.ID])
		return true

	func OnFire(Targets) -> bool:
		Log.append(["Fire", _group(), Desc(Targets)])
		return true

	func OnDamageDone(Amount, _DamageType, Target) -> bool:
		Log.append(["DamageDone", _group(), Amount, Target.ID])
		return true

	func OnShame(KilledUnitID) -> bool:
		Log.append(["Shame", _group(), KilledUnitID])
		return true

	static func Desc(Targets) -> Array:
		var Result: Array = []
		for Target: RTarget in ATarget.FromRParam(Targets):
			if Target.IsEntity():
				Result.append(Target.EntityID)
			elif Target.IsCoordinate():
				Result.append(Vector2(snappedf(Target.FTargetCoord.x, 0.0001), snappedf(Target.FTargetCoord.y, 0.0001)))
			else:
				Result.append("empty")
		return Result


## Records its destruction.
class Tracked:
	extends TEntityComponent
	var Freed := false

	func Destroy() -> void:
		Freed = true
		super()


## Answers eiWillDealDamage with a fixed amount.
class WillDealDamage:
	extends TEntityComponent
	var Amount = null

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnWillDealDamage", C.eiWillDealDamage, C.epMiddle, C.etRead))

	func OnWillDealDamage(_Amount, _DamageTypes, _TargetEntity, Previous):
		return Amount if Amount != null else Previous


## A targeting stand-in: eiWelaUpdateTargets fills the list with Candidates.
class FakeTargeting:
	extends TEntityComponent
	var Candidates: Array = []  # of RTarget

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnUpdate", C.eiWelaUpdateTargets, C.epMiddle, C.etTrigger))

	func OnUpdate(Targets) -> bool:
		Targets.append_array(Candidates)
		return true


## A vector rounded to 4 decimals, for comparisons.
static func V(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001))


func _setup() -> void:
	TTimeManager.FakeTime = 1000.0
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TServerEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_bus.Game.ServerEntityManager = _manager
	_bus.Game.CollisionManager = TServerCollisionManagerComponent.new().Create(_game_entity)
	_log = GlobalLog.new().Create(_game_entity)


func after_each() -> void:
	TTimeManager.FakeTime = null
	TTimeManager.ZDiff = 0.0
	if _game_entity != null:
		_bus.Game.CollisionManager = null
		_bus.Game.ServerEntityManager = null
		_bus.Game.DelayedEvents.Clear()
		_game_entity.Free()  # frees the managers and every deployed entity
		_bus.Game.Map.BuildZones.Free()
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	_log = null
	TEntity.LastScriptError = ""
	super()


func _unit(team: int, pos: Vector2, props: Array = [], health: float = 68.0) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reHealth, health)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, health)
	THealthComponent.new().Create(e)
	e.Position = pos
	e.Front = Vector2(0, 1)
	e.CollisionRadius = 0.5
	TCollisionComponent.new().Create(e)
	e.Deploy()
	return e


## One server frame at time t: due delayed events, then the global eiIdle (TServerGame.Idle), then the manager.
func _frame(t: float) -> void:
	TTimeManager.FakeTime = t
	TDelayedEventHandler.ProcessDueEvents(_bus.Game.DelayedEvents)
	_bus.Trigger(C.eiIdle)
	_manager.Idle()


func _classes(e: TEntity) -> Array:
	var Result: Array = []
	e.Eventbus.Trigger(C.eiEnumerateComponents, [func(comp) -> void: Result.append(comp.ClassName())])
	return Result


## Build zone 1 of team 1: 4x4 fields around (0, 0) facing (0, 1) (so Left = (-1, 0)), spawning towards (10, 0) along
## (1, 0). Field (0, 0) is centred at (3, -3).
func _build_zone() -> TBuildZone:
	var Zone := TBuildZone.new().Create(1).SetTeam(1).SetPosition(0, 0).SetSize(4, 4).SetFront(0, 1) \
		.SetSpawnTarget(10, 0, 1, 0)
	_bus.Game.Map.BuildZones.AddBuildZone(Zone)
	return Zone


# --- statistics (BaseConflict.Classes.Server.pas:111) ---

func test_statistics() -> void:
	var s := TGameStatisticManager.new().Create()
	s.UnitSpawned(3, "Units\\Black\\VoidSkeleton_Black")
	s.UnitSpawned(3, "Units\\Black\\VoidSkeletonSpawner")
	s.UnitSpawned(3, "Units\\Neutral\\SomeBuilding")
	check_eq(s.GetCount(3, "unit_spawns_VoidSkeleton"), 1, "color suffix and path dropped")
	check_eq(s.GetCount(3, "unit_spawns_VoidSkeletonSpawner"), 1, "spawner counted by name")
	check_eq(s.GetCount(3, "unit_spawns_SomeBuilding"), 1, "building counted by name")
	check_eq(s.GetCount(3, "unit_spawns_building"), 1, "and as a building")
	check_eq(s.GetCount(3, BC.GSE_GLOBAL_SPAWNS), 1, "only the plain unit is a global spawn")
	s.UnitKills(3, "Spells\\Blue\\Relocate.sps")
	check_eq(s.GetCount(3, "unit_kills_Relocate"), 1, ".sps dropped")
	check_eq(s.GetCount(3, BC.GSE_GLOBAL_KILLS), 1, "global kill")
	s.WelaDamageMax(3, "X", 5)
	s.WelaDamageMax(3, "X", 3)
	check_eq(s.GetCount(3, "wela_gain_damage_X"), 5, "MaxEvent keeps the larger")
	s.AddCommander(3, 77)
	s.UnitSpawned(4, "Units\\A")
	var bus := TEventbus.new().Create(null)
	var stats := s.BuildStatistics(bus)
	bus.Free()
	check_eq(stats["duration"], 0, "eiGameTickCounter (unset)")
	check_eq(stats["commander_statistics"].size(), 1, "only commanders with a player")
	check_eq(stats["commander_statistics"][0]["player_id"], 77, "player id")
	check_eq(stats["commander_statistics"][0]["game_events"].size(), 9, "every event of commander 3")
	s.Free()


# --- spawn helpers (BaseConflict.Types.Target.pas:177, :284) ---

## Front (0, 1). One unit stands on the spot; two stand beside each other 1.5 × size apart (size 0.45, spawner
## 0.2): side (0, 1.5) turned 90° and halved = (-0.75, 0), the second turned by 180°; three stand on a circle.
func test_compute_spawning_pattern() -> void:
	var P := Vector2(10, 20)
	check_eq(RTarget.ComputeSpawningPattern(P, Vector2(0, 1), false, 0, 1), P, "one unit")
	check_eq(V(RTarget.ComputeSpawningPattern(P, Vector2(0, 1), false, 0, 2)), Vector2(9.25, 20), "first of two")
	check_eq(V(RTarget.ComputeSpawningPattern(P, Vector2(0, 1), false, 1, 2)), Vector2(10.75, 20), "second of two")
	check_eq(V(RTarget.ComputeSpawningPattern(P, Vector2(0, 1), true, 0, 2)), Vector2(9.6667, 20), "spawner: closer")
	var r := 1.5 / 0.45 * 0.45
	var third := Vector2(0, r).rotated(PI / 3).rotated(2.0 / 3 * 2 * PI)
	check_eq(V(RTarget.ComputeSpawningPattern(P, Vector2(0, 1), false, 2, 3)), V(P + third), "third of three")


## Field (0, 0) of the zone is centred at (3, -3); a 2x2 unit on it sits one field further along Left + Front.
func test_real_build_position() -> void:
	_setup()
	_build_zone()
	var t := RTarget.CreateBuildTarget(1, Vector2i(0, 0))
	check_eq(t.GetRealBuildPosition(_bus.Game, Vector2i(1, 1)), Vector2(3, -3), "1x1: the field centre")
	check_eq(t.GetRealBuildPosition(_bus.Game, Vector2i(2, 2)), Vector2(2, -2), "2x2: + Left + Front")


# --- TServerEntityManagerComponent ---

## SpawnUnit: the setup happens before the script's CreateEntity finishes (PreProcessing last), then the ID, the
## callback, eiAfterCreate, eiSendEntities, Deploy and PostProcessing.
func test_spawn_unit() -> void:
	_setup()
	var creator := _unit(1, Vector2(1, 1))
	creator.ScriptFile = "Units\\Colorless\\SmallMeleeGolem.ets"
	var order: Array = []
	var pre := func(x: TEntity) -> void:
		order.append(["pre", x.ID, x.TeamID(), x.Position])
		EntityLog.new().CreateGroupedAll(x)
	var callback := func(x: TEntity) -> void: order.append(["callback", x.ID])
	var post := func(x: TEntity) -> void: order.append(["post", _manager.HasEntityByID(x.ID)])
	var e = _manager.SpawnUnit(Vector2(3, 4), Vector2(1, 0), "Units\\Colorless\\SmallMeleeGolem",
		TServerEntityManagerComponent.INHERIT_FROM_GAME, TServerEntityManagerComponent.INHERIT_FROM_GAME, 2, 7, creator,
		callback, pre, post)
	check(e != null, "spawned: " + TEntity.LastScriptError)
	if e == null:
		return
	check_eq(e.ID, 3, "the next unique ID (game 1, creator 2)")
	check_eq(order, [["pre", 0, 2, Vector2(3, 4)], ["callback", 3], ["post", true]], "pre, callback, post")
	var logs: Array = []
	e.Eventbus.Trigger(C.eiEnumerateComponents, [func(comp) -> void: logs.append(comp)])
	logs = logs.filter(func(comp): return comp is EntityLog)
	check_eq(logs[0].Log, [["AfterCreate", []], ["Deploy", []]], "eiAfterCreate, then Deploy")
	check_eq(_log.Named("Send"), [[[3]]], "sent to the clients")
	check_eq(e.Position, Vector2(3, 4), "position")
	check_eq(e.Front, Vector2(1, 0), "front")
	check_eq(e.CommanderID(), 7, "owning commander")
	check_eq(e.Eventbus.Read(C.eiCreator, []), 2, "creator")
	check_eq(e.Eventbus.Read(C.eiCreatorScriptFileName, []), "SmallMeleeGolem", "creator's script file name")
	check_eq(e.CardLeague(), 3, "league of the game")
	check_eq(e.CardLevel(), BC.MAX_LEVEL, "max level")
	check_eq(_manager.GetEntityByID(3), e, "deployed")
	check_eq(_bus.Game.Map.Clamped, [[C.ZONE_WALK, Vector2(3, 4)]], "clamped to the walk zone")
	check_eq(_bus.Game.Statistics.GetCount(7, "unit_spawns_SmallMeleeGolem"), 1, "counted for the commander")
	# TStatisticsUnitComponent at eiAfterCreate: a melee golem with 68 health
	check_eq(_bus.Game.Statistics.GetCount(7, "wela_spawns_Melee"), 1, "a melee spawn")
	check_eq(_bus.Game.Statistics.GetCount(7, "wela_spawns_Ranged"), 0, "not ranged")
	check_eq(_bus.Game.Statistics.GetCount(7, "wela_spawns_gte500Health"), 0, "less than 500 health")


## The scripts' form: SpawnUnit(X, Y, Pattern, TeamID) faces (0, 1), has no commander nor creator. Spawners are
## not clamped to the walk zone.
func test_spawn_unit_script_form() -> void:
	_setup()
	var e = _manager.SpawnUnit(-5.0, 2.0, "Units\\Colorless\\SmallMeleeGolem", 1)
	check(e != null, "spawned: " + TEntity.LastScriptError)
	if e == null:
		return
	check_eq([e.Position, e.Front, e.TeamID()], [Vector2(-5, 2), Vector2(0, 1), 1], "position, front, team")
	check(RParam.IsEmpty(e.Eventbus.Read(C.eiOwnerCommander, [])), "no commander written")
	check(RParam.IsEmpty(e.Eventbus.Read(C.eiCreator, [])), "no creator")
	check_eq(_bus.Game.Statistics.GetCount(-1, "unit_spawns_SmallMeleeGolem"), 1, "counted for commander -1")
	_bus.Game.Map.Clamped.clear()
	var s = _manager.SpawnUnit(Vector2(1, 1), Vector2(0, 1), "Units\\Black\\VoidSkeletonSpawner", 5, 2, 1)
	check(s != null, "spawner spawned: " + TEntity.LastScriptError)
	check_eq(_bus.Game.Map.Clamped, [], "a spawner is not clamped")
	check_eq([s.CardLeague(), s.CardLevel()], [5, 2], "explicit league and level")


## eiDelayedKillEntity: unregistered (eiKillEntity) at the next Idle, freed at the one after.
func test_delayed_kill() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var t: Tracked = Tracked.new().Create(e)
	_bus.Trigger(C.eiDelayedKillEntity, [e.ID])
	check(_manager.HasEntityByID(e.ID), "still there this frame")
	_manager.Idle()
	check(not _manager.HasEntityByID(e.ID), "gone at the next Idle")
	check_eq(_log.Named("Kill"), [[e.ID]], "through eiKillEntity")
	check(not t.Freed, "not freed yet")
	_manager.Idle()
	check(t.Freed, "freed at the Idle after")
	check_eq(_log.Named("Kill").size(), 1, "killed once")


## SpawnUnitWithoutLimitedLifetime frees GROUP_BUILDING_LIFETIME (the real VoidAltar's 90 s lifetime) and faces
## (-1, 0); the overwatch variants add their brains; the sandbox adds overwatch to everything.
func test_spawn_variants() -> void:
	_setup()
	var altar = _manager.SpawnUnit(0.0, 0.0, "Units\\Black\\VoidAltar", 1)
	check(altar != null, "altar: " + TEntity.LastScriptError)
	if altar == null:
		return
	check_eq(altar.Blackboard.GetValue(C.eiCooldown, [C.GROUP_BUILDING_LIFETIME]), 90000, "a limited lifetime")
	var lasting = _manager.SpawnUnitWithoutLimitedLifetime(4.0, 0.0, "Units\\Black\\VoidAltar", 1)
	check(RParam.IsEmpty(lasting.Blackboard.GetValue(C.eiCooldown, [C.GROUP_BUILDING_LIFETIME])), "lifetime group freed")
	check_eq(lasting.Front, Vector2(-1, 0), "faces (-1, 0)")
	var watcher = _manager.SpawnUnitWithOverwatch(1.0, 2.0, 0.0, -1.0, "Units\\Colorless\\SmallMeleeGolem", 2)
	check_eq([watcher.Position, watcher.Front, watcher.TeamID()], [Vector2(1, 2), Vector2(0, -1), 2], "overwatch spawn")
	check(_classes(watcher).has("TBrainOverwatchComponent"), "has an overwatch brain")
	var flee = _manager.SpawnUnitWithOverwatchAndFlee(1.0, 2.0, 0.0, -1.0, "Units\\Colorless\\SmallMeleeGolem", 2, 3.0)
	check(_classes(flee).has("TBrainOverwatchComponent") and _classes(flee).has("TBrainFleeComponent"), "overwatch and flee")
	check(not _classes(altar).has("TBrainOverwatchComponent"), "no overwatch outside the sandbox")
	_bus.Game.Sandbox = true
	_bus.Game.Overwatch = true
	var sandboxed = _manager.SpawnUnit(0.0, 5.0, "Units\\Colorless\\SmallMeleeGolem", 1)
	check(_classes(sandboxed).has("TBrainOverwatchComponent"), "sandbox overwatch")
	_bus.Game.OverwatchClearable = true
	var clearable = _manager.SpawnUnit(0.0, 6.0, "Units\\Colorless\\SmallMeleeGolem", 1)
	check(_classes(clearable).has("TBrainOverwatchSandboxComponent"), "clearable sandbox overwatch")


## SpawnSpawner on field (0, 0): a 1x1 unit at the field centre facing the zone's front; the field is blocked with
## its ID and saved in eiBuildgridBlockedFields, eiBuildgridOwner is written in the setup.
func test_spawn_spawner() -> void:
	_setup()
	var zone := _build_zone()
	var s = _manager.SpawnSpawner(1, Vector2i(0, 0), "Units\\Black\\VoidSkeletonSpawner", 1, 7, null)
	check(s != null, "spawned: " + TEntity.LastScriptError)
	if s == null:
		return
	check_eq([s.Position, s.Front], [Vector2(3, -3), Vector2(0, 1)], "field centre, zone front")
	check_eq(s.Eventbus.Read(C.eiBuildgridOwner, []), 1, "eiBuildgridOwner")
	check_eq(zone.GetFieldID(Vector2i(0, 0)), s.ID, "field blocked by the spawner")
	check_eq(s.Eventbus.Read(C.eiBuildgridBlockedFields, []), [[1, Vector2i(0, 0)]], "blocked fields saved")


# --- TWelaEffectFactoryComponent ---

## eiWelaCount 2 at a spot with SpreadSpawns (no eiWelaAreaOfEffect): the spawning pattern around the spot, the
## owner's team, front, commander, league / level and skin; eiWelaUnitProduced in the fired group, then groupless.
func test_factory() -> void:
	_setup()
	var owner := _unit(1, Vector2(0, 0))
	owner.Front = Vector2(1, 0)
	owner.SkinID = "Gold"
	owner.Blackboard.SetValue(C.eiOwnerCommander, [], 7)
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, 2)
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLevel, 4)
	owner.Blackboard.SetValue(C.eiWelaUnitPattern, [3], "Units\\Colorless\\SmallMeleeGolem")
	owner.Blackboard.SetValue(C.eiWelaCount, [3], 2)
	TWelaEffectFactoryComponent.new().CreateGrouped(owner, [3]).SpreadSpawns()
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	owner.Eventbus.Trigger(C.eiFire, [[RTarget.Create(Vector2(10, 0))]], [3])
	var produced := log.Named("Produced")
	check_eq(produced.size(), 4, "two units, each announced twice")
	if produced.size() != 4:
		return
	check_eq([produced[0][0], produced[1][0]], [[3], []], "in the group, then groupless")
	var a = _manager.GetEntityByID(produced[0][1])
	var b = _manager.GetEntityByID(produced[2][1])
	check_eq([V(a.Position), V(b.Position)], [Vector2(10, 0.75), Vector2(10, -0.75)], "side by side across the front")
	check_eq([a.TeamID(), a.Front, a.CommanderID()], [1, Vector2(1, 0), 7], "team, front, commander")
	check_eq([a.CardLeague(), a.CardLevel()], [2, 4], "the owner's league and level")
	check_eq([a.SkinID, a.Blackboard.GetValue(C.eiSkinIdentifier, [])], ["Gold", "Gold"], "the owner's skin")
	check_eq(a.Eventbus.Read(C.eiCreator, []), owner.ID, "created by the owner")


## A build target: the unit of eiWelaNeededGridSize sits on its fields (blocked), facing the zone's front;
## SetSpawnedTeam overrides the team, PassTargets saves the targets (and spawns at the first only), PassCardValues
## copies reCardTimesPlayed / reLevel. A groupless fire announces the unit once.
func test_factory_build_target() -> void:
	_setup()
	var zone := _build_zone()
	var owner := _unit(1, Vector2(0, 20))
	owner.Blackboard.SetValue(C.eiWelaUnitPattern, [], "Units\\Colorless\\SmallMeleeGolem")
	owner.Blackboard.SetValue(C.eiWelaNeededGridSize, [], Vector2i(2, 1))
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardTimesPlayed, 4)
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reLevel, 2)
	TWelaEffectFactoryComponent.new().CreateGrouped(owner, []).SetSpawnedTeam(4).PassTargets().PassCardValues()
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	var targets := [RTarget.CreateBuildTarget(1, Vector2i(1, 2)), RTarget.Create(Vector2(50, 50))]
	owner.Eventbus.Trigger(C.eiFire, [targets])
	var produced := log.Named("Produced")
	check_eq(produced.size(), 1, "one unit (PassTargets: only the first target), announced once")
	if produced.size() != 1:
		return
	var u = _manager.GetEntityByID(produced[0][1])
	# field (1, 2) centre: Front * 2 * 0.5 + Left * 2 * -0.5 = (1, 1); 2x1: + Left * 1 = (0, 1)
	check_eq([u.Position, u.Front, u.TeamID()], [Vector2(0, 1), Vector2(0, 1), 4], "on the fields, zone front, team 4")
	check_eq(u.Eventbus.Read(C.eiBuildgridOwner, []), 1, "eiBuildgridOwner")
	check_eq([zone.GetFieldID(Vector2i(1, 2)), zone.GetFieldID(Vector2i(2, 2))], [0, 0],
		"both fields blocked, with ID 0: the PreProcessing runs before the unit has its ID (quirk kept)")
	check_eq(u.Eventbus.Read(C.eiBuildgridBlockedFields, []), [[1, Vector2i(1, 2)], [1, Vector2i(2, 2)]], "saved")
	check_eq(EntityLog.Desc(u.Eventbus.Read(C.eiWelaSavedTargets, [])).size(), 2, "the targets saved")
	check_eq([u.BalanceInt(C.reCardTimesPlayed), u.Balance(C.reLevel)], [4, 2], "card values passed")


# --- TWelaEffectReplaceComponent ---

## The owner replaces itself: it is killed next frame, the new unit takes its place, card values, commander and
## (KeepTakenDamage) missing health; eiWelaUnitProduced in the group, then eiReplaceEntity [owner, new, False].
func test_replace() -> void:
	_setup()
	var old := _unit(1, Vector2(5, 5))
	old.Front = Vector2(-1, 0)
	old.SkinID = "Gold"
	old.Blackboard.SetValue(C.eiOwnerCommander, [], 7)
	old.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, 50.0)
	old.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, 2)
	old.Blackboard.SetValue(C.eiWelaUnitPattern, [4], "Units\\Colorless\\SmallMeleeGolem")
	old.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reWood, 9.0)
	TWelaEffectReplaceComponent.new().CreateGrouped(old, [4]).KeepTakenDamage().KeepResource(C.reWood)
	var log: EntityLog = EntityLog.new().CreateGroupedAll(old)
	old.Eventbus.Trigger(C.eiFire, [[RTarget.Create(old)]], [4])
	check_eq(_log.Named("DelayedKill"), [[old.ID]], "the old unit dies next frame")
	var produced := log.Named("Produced")
	check_eq(produced.size(), 1, "announced once, in the group")
	if produced.size() != 1:
		return
	var u = _manager.GetEntityByID(produced[0][1])
	check_eq(produced[0][0], [4], "in group 4")
	check_eq([u.Position, u.Front, u.TeamID(), u.CommanderID()], [Vector2(5, 5), Vector2(-1, 0), 1, 7], "in its place")
	check_eq([u.CardLeague(), u.SkinID], [2, "Gold"], "league and skin")
	check_eq(u.BalanceSingle(C.reHealth), 68.0 - 18.0, "SmallMeleeGolem 68 - 18 taken")
	check_eq(u.BalanceSingle(C.reWood), 9.0, "wood kept")
	check_eq(_log.Named("Replace"), [[old.ID, u.ID, false]], "eiReplaceEntity [owner, new, False]")


# --- TWelaEffectProjectileComponent + TProjectileEventRedirecter ---

## A projectile per target from the owner: upProjectile, the group's values in [0], the target saved; the owner
## hears eiWelaShotProjectile in the group and groupless. The projectile passes damage done, kills and
## eiWillDealDamage on to its creator.
func test_projectile() -> void:
	_setup()
	var owner := _unit(1, Vector2(1, 0))
	var target := _unit(2, Vector2(6, 0))
	owner.Blackboard.SetValue(C.eiWelaUnitPattern, [5], "Projectiles\\Black\\SoulGatherProjectile")
	owner.Blackboard.SetValue(C.eiWelaDamage, [5], 7.5)
	owner.Blackboard.SetValue(C.eiDamageType, [5], [C.dtRanged])
	var effect: TWelaEffectProjectileComponent = TWelaEffectProjectileComponent.new().CreateGrouped(owner, [5])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	var will: WillDealDamage = WillDealDamage.new().Create(owner)
	check_eq(owner.Eventbus.Read(C.eiEfficiency, [target], [5]), 1.0, "efficiency 1")
	owner.Eventbus.Trigger(C.eiFire, [[RTarget.Create(target)]], [5])
	var shots := log.Named("Shot")
	check_eq(shots.size(), 2, "shot announced twice")
	if shots.size() != 2:
		return
	check_eq([shots[0][0], shots[1][0]], [[5], []], "in the group, then groupless")
	var p = _manager.GetEntityByID(shots[0][1])
	check_eq(p.Position, Vector2(1, 0), "starts at the owner")
	check(p.UnitProperties().has(C.upProjectile), "upProjectile")
	check_eq(p.Blackboard.GetValue(C.eiWelaDamage, [0]), 7.5, "damage copied to [0]")
	check_eq(p.Blackboard.GetValue(C.eiDamageType, [0]), [C.dtRanged], "damage type copied to [0]")
	check_eq(EntityLog.Desc(p.Blackboard.GetValue(C.eiWelaSavedTargets, [])), [target.ID], "target saved")
	p.Eventbus.Trigger(C.eiDamageDone, [3.0, [C.dtRanged], target])
	p.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [target.ID])
	check_eq(log.Named("DamageDone"), [[[], 3.0, target.ID]], "damage done passed on")
	check_eq(log.Named("Shame"), [[[], target.ID]], "kill passed on")
	will.Amount = 99.0
	check_eq(p.Eventbus.Read(C.eiWillDealDamage, [1.0, [], target]), 99.0, "the creator's eiWillDealDamage")
	_bus.Trigger(C.eiDelayedKillEntity, [owner.ID])
	_manager.Idle()
	p.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [target.ID])
	check_eq(_bus.Game.Statistics.GetCount(0, "unit_kills_"), 1,
		"creator gone: counted for the projectile's commander (none: 0) under the creator's script name (empty)")


## Reverse: the projectile starts at the target and flies back to the owner; MultipleProjectiles shoots eiWelaCount.
func test_projectile_reverse_multiple() -> void:
	_setup()
	var owner := _unit(1, Vector2(0, 0))
	var target := _unit(2, Vector2(6, 0))
	owner.Blackboard.SetValue(C.eiWelaUnitPattern, [5], "Projectiles\\Black\\SoulGatherProjectile")
	owner.Blackboard.SetValue(C.eiWelaCount, [5], 3)
	TWelaEffectProjectileComponent.new().CreateGrouped(owner, [5]).Reverse().MultipleProjectiles()
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	owner.Eventbus.Trigger(C.eiFire, [[RTarget.Create(target)]], [5])
	var shots := log.Named("Shot")
	check_eq(shots.size(), 6, "three projectiles")
	if shots.size() != 6:
		return
	var p = _manager.GetEntityByID(shots[0][1])
	check_eq(p.Position, Vector2(6, 0), "starts at the target")
	check_eq(EntityLog.Desc(p.Blackboard.GetValue(C.eiWelaSavedTargets, [])), [owner.ID], "aims at the owner")
	check_eq(p.Blackboard.GetValue(C.eiWelaCount, [0]), 3, "eiWelaCount copied")


## A shooter standing exactly at (0, 0) counts as a commander without position: the projectile starts at the target.
func test_projectile_from_origin() -> void:
	_setup()
	var owner := _unit(1, Vector2(0, 0))
	var target := _unit(2, Vector2(6, 0))
	owner.Blackboard.SetValue(C.eiWelaUnitPattern, [5], "Projectiles\\Black\\SoulGatherProjectile")
	TWelaEffectProjectileComponent.new().CreateGrouped(owner, [5])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	owner.Eventbus.Trigger(C.eiFire, [[RTarget.Create(target)]], [5])
	var shots := log.Named("Shot")
	check_eq(shots.size(), 2, "one projectile")
	if shots.size() == 2:
		check_eq(_manager.GetEntityByID(shots[0][1]).Position, Vector2(6, 0), "starts at the target")


# --- TBrainSpawnerComponent ---

## ApplyGridOffset uses RMatrix2x2.Inverse as coded (the transpose of the inverse): field (0, 0) (centre (3, -3))
## gives the offset (-3, -3), not (3, 3); the spawn target base is the identity here, so it fires at (7, -3).
func test_brain_spawner() -> void:
	_setup()
	_build_zone()
	var s := _unit(1, Vector2(3, -3))
	s.Blackboard.SetValue(C.eiBuildgridOwner, [], 1)
	s.Blackboard.SetValue(C.eiBuildgridBlockedFields, [], [[1, Vector2i(0, 0)]])
	var brain: TBrainSpawnerComponent = TBrainSpawnerComponent.new().CreateGrouped(s, [0]).ApplyGridOffset()
	var log: EntityLog = EntityLog.new().CreateGroupedAll(s)
	_bus.Trigger(C.eiWaveSpawn, [2, Vector2i(0, 0)])
	_bus.Trigger(C.eiWaveSpawn, [1, Vector2i(1, 0)])
	check_eq(log.Named("Fire"), [], "other grid or field: no spawn")
	_bus.Trigger(C.eiWaveSpawn, [1, Vector2i(0, 0)])
	check_eq(log.Named("Fire"), [[[0], [Vector2(7, -3)]]], "fires in its group at the spawn target + offset")
	check_eq(TBrainSpawnerComponent.Matrix2x2Inverse(Transform2D(Vector2(2, 0), Vector2(1, 1), Vector2.ZERO)),
		Transform2D(Vector2(0.5, -0.5), Vector2(0, 1), Vector2.ZERO), "the coded inverse of [[2, 1], [0, 1]]")
	_log.Log.clear()
	_bus.Trigger(C.eiGameStart)
	check_eq(_log.Named("WaveSpawn"), [[1, Vector2i(0, 0)]], "asks for its own wave at game start")
	_log.Log.clear()
	brain.FireNotInitially()
	_bus.Trigger(C.eiGameStart)
	check_eq(_log.Named("WaveSpawn"), [], "FireNotInitially: not at game start")


# --- TBrainCapturePointComponent ---

## One team near captures (fires its positive group, the other team's negative group); two teams stop the capture
## (idle group); a blocked team (eiIsReady of TeamID + 10 false) cannot capture.
func test_brain_capture_point() -> void:
	_setup()
	var node := _unit(0, Vector2(0, 0))
	var a := _unit(1, Vector2(1, 0))
	var b := _unit(2, Vector2(-1, 0))
	var targeting: FakeTargeting = FakeTargeting.new().CreateGrouped(node, [1])
	TBrainCapturePointComponent.new().CreateGrouped(node, [1]).SetIdleGroup([8]).SetTeamGroup(1, [2], [3]) \
		.SetTeamGroup(2, [6], [7])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(node)
	node.Eventbus.Trigger(C.eiThink)
	check_eq(log.Named("Fire"), [[[8], [node.ID]]], "nobody near: idle")
	log.Log.clear()
	targeting.Candidates = [RTarget.Create(a)]
	node.Eventbus.Trigger(C.eiThink)
	check_eq(log.Named("Fire"), [[[2], [node.ID]], [[7], [node.ID]]], "team 1 captures: its positive, team 2's negative")
	log.Log.clear()
	targeting.Candidates = [RTarget.Create(a), RTarget.Create(b)]
	node.Eventbus.Trigger(C.eiThink)
	check_eq(log.Named("Fire"), [[[8], [node.ID]]], "contested: nobody holds it")
	log.Log.clear()
	node.Blackboard.SetValue(C.eiIsReady, [12], false)
	targeting.Candidates = [RTarget.Create(b)]
	node.Eventbus.Trigger(C.eiThink)
	check_eq(log.Named("Fire"), [[[8], [node.ID]]], "team 2 is blocked")


# --- real scripts ---

## The real VoidSkeletonSpawner placed on field (0, 0) of team 1's zone: at game start it asks for its wave, its
## brain fires group 0 at (7, -3) and the factory spawns the squad of two VoidSkeletons beside each other (spawner
## pattern: 0.3333 either side across the front (0, 1)), team 1, commander 7, the game's league 3 at level 5.
func test_real_spawner_spawns_its_squad() -> void:
	_setup()
	var zone := _build_zone()
	var s = _manager.SpawnSpawner(1, Vector2i(0, 0), "Units\\Black\\VoidSkeletonSpawner", 1, 7, null)
	check(s != null, "spawner: " + TEntity.LastScriptError)
	if s == null:
		return
	check_eq(zone.GetFieldID(Vector2i(0, 0)), s.ID, "its field is blocked")
	var log: EntityLog = EntityLog.new().CreateGroupedAll(s)
	_bus.Trigger(C.eiGameStart)
	check_eq(log.Named("Fire"), [[[0], [Vector2(7, -3)]]], "fires its wave")
	var produced := log.Named("Produced")
	check_eq(produced.size(), 4, "two skeletons, each announced twice")
	if produced.size() != 4:
		return
	var a = _manager.GetEntityByID(produced[0][1])
	var b = _manager.GetEntityByID(produced[2][1])
	check_eq(a.ScriptFileName(), "VoidSkeleton", "VoidSkeletons")
	check_eq([V(a.Position), V(b.Position)], [Vector2(6.6667, -3), Vector2(7.3333, -3)], "side by side")
	check_eq([a.TeamID(), a.CommanderID(), a.Front], [1, 7, Vector2(0, 1)], "team, commander, front")
	check_eq([a.CardLeague(), a.CardLevel()], [3, 5], "league and level")
	check_eq(_bus.Game.Statistics.GetCount(7, "unit_spawns_VoidSkeleton"), 2, "two skeletons counted")


## A real server SmallMeleeGolem (team 2) dies next to a soul gatherer (team 1, mana 0 / 10, 5 away): its GROUP_SOUL
## factory spawns the real SoulGatherProjectileSpawner where it fell; one frame later the spawner shoots a
## SoulGatherProjectile (speed 10 / s) at the gatherer and kills itself; the soul flies and gives 1 mana.
func test_real_golem_soul_reaches_gatherer() -> void:
	_setup()
	var killer := _unit(1, Vector2(0, 12))
	var gatherer := _unit(1, Vector2(5, 10), [C.upSoulGatherer, C.upGround])
	gatherer.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reMana, 10)
	gatherer.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reMana, 0)
	var init := func(x):
		x.ID = _manager.GenerateUniqueID()
		x.Blackboard.SetValue(C.eiTeamID, [], 2)
		x.Position = Vector2(0, 10)
	var golem := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus, init)
	check(golem != null, "golem: " + TEntity.LastScriptError)
	if golem == null:
		return
	golem.Deploy()
	golem.Eventbus.Trigger(C.eiAfterCreate)
	var golem_id := golem.ID
	var log: EntityLog = EntityLog.new().CreateGroupedAll(golem)
	golem.Eventbus.Read(C.eiTakeDamage, [500.0, [C.dtMelee], killer.ID])
	var produced := log.Named("Produced")
	check_eq(produced.size(), 2, "the soul spawner, announced in GROUP_SOUL and groupless")
	if produced.size() != 2:
		return
	check_eq(produced[0][0], [C.GROUP_SOUL], "in GROUP_SOUL")
	var spawner = _manager.GetEntityByID(produced[0][1])
	check_eq(spawner.ScriptFileName(), "SoulGatherProjectileSpawner", "the soul spawner")
	check_eq([spawner.Position, spawner.TeamID()], [Vector2(0, 10), 2], "where the golem fell, its team")
	var spawner_log: EntityLog = EntityLog.new().CreateGroupedAll(spawner)
	var spawner_id: int = spawner.ID
	TTimeManager.ZDiff = 10.0
	var t := 1000.0
	var shot_at := -1.0
	var mana := 0
	while t < 3000.0 and mana == 0:
		t += 10.0
		_frame(t)
		if shot_at < 0 and spawner_log.Named("Shot").size() > 0:
			shot_at = t
		mana = gatherer.BalanceInt(C.reMana)
	var shots := spawner_log.Named("Shot")
	check(shots.size() > 0, "the spawner shot its soul")
	if shots.size() == 0:
		return
	check_eq(shots[0][0], [0], "from group 0")
	check_eq(mana, 1, "the soul gives 1 mana")
	check(not _manager.HasEntityByID(golem_id), "the golem is gone")
	check(not _manager.HasEntityByID(spawner_id), "the spawner killed itself")
	_frame(t + 10.0)
	check(not _manager.HasEntityByID(shots[0][1]), "the soul is gone after its hit")
	check(t - shot_at >= 400.0 and t - shot_at <= 600.0, "5 away at 10 / s: about 500 ms of flight (%d)" % (t - shot_at))
