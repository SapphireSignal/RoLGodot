extends "res://tests/test_case.gd"
## The link family (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:570-735, ...Server.pas:150):
## DelphiDictionary (Delphi's TDictionary) and RTarget.Hash, TWelaLinkEffectComponent, TLinkEventRedirecter,
## TWelaLinkEffectUnitPropertyComponent, TWelaEffectLinkPayCostMyselfComponentServer, TLinkBrainComponent,
## TLinkEffectDamageRedirectionComponent, TLinkEffectFireAtProducedUnitsComponent, and real scripts: a SmallCasterGolem
## giving an ally Crystal Power, a GatlingTurret gunning down an enemy while its ammo lasts.
## The game has the real server entity manager and collision manager, a fake map and a delayed-event queue pumped
## like TServerGame.Idle (as in test_spawning.gd).

const C = preload("res://src/runtime/dws/dws_const.gd")
const F = preload("res://tests/component_fakes.gd")

const LINK := "Links\\CrystalPowerLink"

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

	func ClampToZone(_Zone: String, Position: Vector2) -> Vector2:
		return Position


class FakeGame:
	extends RefCounted
	var IsShuttingDown := false
	var IsSandbox := false
	var Overwatch := false
	var OverwatchClearable := false
	var HasStarted := false
	var IngameStatus := 2  # BC.gsPlaying
	var League := 3
	var Map := FakeMap.new()
	var EntityManager = null
	var ServerEntityManager = null
	var CollisionManager = null
	var Statistics := TGameStatisticManager.new().Create()
	var DelayedEvents := TIntPriorityQueue.new()


## Global traffic: sent entities and delayed kills.
class GlobalLog:
	extends TEntityComponent
	var Sent: Array = []
	var Kills: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnSend", C.eiSendEntities, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnDelayedKill", C.eiDelayedKillEntity, C.epFirst, C.etTrigger, C.esGlobal))

	func OnSend(Entities) -> bool:
		Sent.append_array(Entities)
		return true

	func OnDelayedKill(EntityID) -> bool:
		Kills.append(EntityID)
		return true


## Entity traffic (ALLGROUP): [name, called-to group, parameters...] in call order.
class EntityLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnShame", C.eiYouHaveKilledMeShameOnYou, C.epFirst, C.etTrigger))
		e.append(XEvent("OnEstablish", C.eiLinkEstablish, C.epFirst, C.etTrigger))
		e.append(XEvent("OnBreak", C.eiLinkBreak, C.epFirst, C.etTrigger))
		e.append(XEvent("OnTakeDamage", C.eiTakeDamage, C.epLast, C.etRead))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func _group() -> Array:
		return TEventbus.CurrentEvent_CalledToGroup.duplicate()

	func OnFire(Targets) -> bool:
		Log.append(["Fire", _group(), Desc(Targets), TTimeManager.GetTimeStamp()])
		return true

	func OnDamageDone(Amount, _DamageType, Target) -> bool:
		Log.append(["DamageDone", _group(), Amount, Target.ID if Target is TEntity else Target])
		return true

	func OnShame(KilledUnitID) -> bool:
		Log.append(["Shame", _group(), KilledUnitID])
		return true

	func OnEstablish(_Source, Dest) -> bool:
		Log.append(["Establish", _group(), Dest.EntityID])
		return true

	func OnBreak(Target) -> bool:
		Log.append(["Break", _group(), Target.EntityID])
		return true

	func OnTakeDamage(Amount, DamageType, InflictorID, Previous):
		Log.append(["TakeDamage", _group(), Amount, DamageType, InflictorID, Previous, TTimeManager.GetTimeStamp()])
		return Previous

	static func Desc(Targets) -> Array:
		var Result: Array = []
		for Target: RTarget in ATarget.FromRParam(Targets):
			Result.append(Target.EntityID if Target.IsEntity() else "other")
		return Result


## Answers eiIsReady in its group with Ready.
class ReadySwitch:
	extends TEntityComponent
	var Ready := true

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnIsReady", C.eiIsReady, C.epLast, C.etRead))

	func OnIsReady(Previous):
		return Previous if Ready else false


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
		_log.Sent = []
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


func _unit(team: int, pos: Vector2, props: Array = [], health: float = 68.0, id: int = 0) -> TEntity:
	var e := TEntity.new().Create(_bus, id if id != 0 else _manager.GenerateUniqueID())
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


## A bare link entity (no script) from source to dest.
func _link(source: TEntity, dest: TEntity) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], source.TeamID())
	e.Blackboard.SetValue(C.eiLinkSource, [], ATarget.ToRParam(ATarget.Make(source)))
	e.Blackboard.SetValue(C.eiLinkDest, [], ATarget.ToRParam(ATarget.Make(dest)))
	e.Deploy()
	return e


## One server frame at time t: due delayed events, then the global eiIdle (TServerGame.Idle), then the manager.
func _frame(t: float) -> void:
	TTimeManager.FakeTime = t
	TDelayedEventHandler.ProcessDueEvents(_bus.Game.DelayedEvents)
	_bus.Trigger(C.eiIdle)
	_manager.Idle()


func _fire(e: TEntity, targets: Array, group: Array) -> void:
	var t: Array = []
	for x in targets:
		t.append(RTarget.Create(x))
	e.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(t)], group)


func _classes(e: TEntity) -> Array:
	var Result: Array = []
	e.Eventbus.Trigger(C.eiEnumerateComponents, [func(comp) -> void: Result.append(comp.ClassName())])
	return Result


func _props(e: TEntity) -> Array:
	return RParam.AsSet(e.Eventbus.Read(C.eiUnitProperties, []))


func _dest_ids(link: TEntity) -> Array:
	return ATarget.FromRParam(link.Eventbus.Read(C.eiLinkDest, [])).map(func(t): return t.EntityID)


# --- DelphiDictionary and RTarget.Hash ---

## Keys hashed by themselves: Hash = key + 1. Created empty, the first Add grows to 4 slots (threshold 75% = 3):
## 3 → slot 0, 7 → bucket 0 taken → slot 1, 2 → slot 3. The 4th Add (count 3 >= 3) grows to 8 and rehashes.
## Removing while walking: removing 3 shifts 7 back into slot 0, which the walk has passed, so 7 is skipped.
func test_delphi_dictionary() -> void:
	var d := DelphiDictionary.new().Create(func(k: int) -> int: return k, func(a: int, b: int) -> bool: return a == b)
	d.Add(3, "a")
	d.Add(7, "b")
	d.Add(2, "c")
	check_eq(d.FHashes.size(), 4, "4 slots")
	check_eq(d.Keys(), [3, 7, 2], "slot order")
	check_eq([d.ContainsKey(7), d.ContainsKey(5), d.GetItem(2)], [true, false, "c"], "lookups")
	var visited: Array = []
	var slot := d.NextSlot(-1)
	while slot >= 0:
		var k = d.KeyAt(slot)
		visited.append(k)
		d.Remove(k)
		slot = d.NextSlot(slot)
	check_eq(visited, [3, 2], "7 moved back behind the walk and is skipped")
	check_eq([d.Keys(), d.Count], [[7], 1], "7 is left")
	d.Add(11, "d")
	d.Add(4, "e")
	check_eq(d.FHashes.size(), 4, "3 entries fit")
	d.Add(8, "f")
	check_eq(d.FHashes.size(), 8, "the 4th grows to 8")
	check_eq(d.Keys(), [7, 8, 11, 4], "rehashed into 8 slots: 7 → 0, 11 → 4, 4 → 5, then 8 → 1")


## RTarget.Hash: Ord(TargetType) xor EntityID xor the coordinate hash (0 for (0, 0)).
func test_rtarget_hash() -> void:
	check_eq(RTarget.Create(5).Hash(), C.ttEntity ^ 5, "entity: 2 xor ID")
	check_eq(RTarget.Create(Vector2.ZERO).Hash(), C.ttCoordinate, "the origin")
	check_eq(RTarget.CreateBuildTarget(4, Vector2i(1, 2)).Hash(), C.ttBuild, "build targets hash by type only")
	# (1, 0): Round(1 / 0.00001 * 73856093) mod MaxInt, xor 1
	check_eq(RTarget.Create(Vector2(1, 0)).Hash(), ((7385609300000 % 0x7FFFFFFF) ^ C.ttCoordinate) & 0xFFFFFFFF,
		"a coordinate")


# --- TWelaLinkEffectComponent + TWelaLinkEffectUnitPropertyComponent ---

func _linker(team: int = 1) -> TEntity:
	var owner := _unit(team, Vector2(0, 10))
	owner.Blackboard.SetValue(C.eiLinkPattern, [2], LINK)
	owner.Blackboard.SetValue(C.eiOwnerCommander, [], 7)
	TWelaLinkEffectComponent.new().CreateGrouped(owner, [2]).CreatorGroup([5])
	TWelaLinkEffectUnitPropertyComponent.new().CreateGrouped(owner, [2], C.upInvisible)
	return owner


## Fire at a target: eiLinkEstablish [owner, target] in the group; the link is the CrystalPowerLink script at (0, 0),
## team, commander, creator of the owner, with upLink, source / dest, creator group and a redirecter; the dest gets
## upInvisible. Firing at a linked target again stops at the link effect (the unit property component never sees it).
func test_establish_link() -> void:
	_setup()
	var owner := _linker()
	var a := _unit(1, Vector2(2, 10), [C.upUnit])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	_fire(owner, [a], [2])
	check_eq(log.Named("Establish"), [[[2], a.ID]], "eiLinkEstablish in the group")
	check_eq(_log.Sent.size(), 1, "one link spawned")
	if _log.Sent.size() != 1:
		return
	var link: TEntity = _log.Sent[0]
	check_eq(link.ScriptFileName(), "CrystalPowerLink", "the link pattern")
	check_eq([link.TeamID(), link.CommanderID(), link.Position], [1, 7, Vector2.ZERO], "team, commander, at (0, 0)")
	check_eq(RParam.AsInteger(link.Eventbus.Read(C.eiCreator, [])), owner.ID, "created by the owner")
	check(_props(link).has(C.upLink), "upLink")
	check_eq(ATarget.FromRParam(link.Eventbus.Read(C.eiLinkSource, [])).map(func(t): return t.EntityID), [owner.ID],
		"source")
	check_eq(_dest_ids(link), [a.ID], "dest")
	check_eq(RParam.AsSet(link.Eventbus.Read(C.eiCreatorGroup, [])), [5], "creator group")
	check(_classes(link).has("TLinkEventRedirecter"), "a redirecter")
	check(_props(a).has(C.upInvisible), "the dest gets the property")
	check(_props(a).has(C.upHasCrystalPower), "the link script applied Crystal Power")
	# again: stopped at epFirst
	a.Blackboard.SetValue(C.eiUnitProperties, [], [C.upUnit])
	_fire(owner, [a], [2])
	check_eq(_log.Sent.size(), 1, "no second link")
	check(not _props(a).has(C.upInvisible), "the property component did not run")


## eiWelaTargetCount 2: the third link breaks the oldest first (its link is killed, the property removed); eiLinkBreak
## kills a link; eiExiled True, eiDie and the global eiLose break all.
func test_target_count_and_breaks() -> void:
	_setup()
	var owner := _linker()
	owner.Blackboard.SetValue(C.eiWelaTargetCount, [2], 2)
	var a := _unit(1, Vector2(2, 10), [C.upUnit])
	var b := _unit(1, Vector2(3, 10), [C.upUnit])
	var c := _unit(1, Vector2(4, 10), [C.upUnit])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	_fire(owner, [a, b], [2])
	check_eq(_log.Sent.size(), 2, "two links")
	_fire(owner, [c], [2])
	check_eq(log.Named("Break"), [[[2], a.ID]], "the oldest breaks")
	check_eq(_log.Kills, [_log.Sent[0].ID], "its link is killed")
	check(not _props(a).has(C.upInvisible) and _props(b).has(C.upInvisible), "a lost the property, b keeps it")
	check_eq(_dest_ids(_log.Sent[2]), [c.ID], "then c is linked")
	owner.Eventbus.Trigger(C.eiLinkBreak, [RTarget.Create(b)], [2])
	check_eq(_log.Kills, [_log.Sent[0].ID, _log.Sent[1].ID], "eiLinkBreak kills b's link")
	owner.Eventbus.Trigger(C.eiLinkBreak, [RTarget.Create(b)], [2])
	check_eq(_log.Kills.size(), 2, "breaking an unlinked target kills nothing")
	owner.Eventbus.Write(C.eiExiled, [false])
	check_eq(_log.Kills.size(), 2, "not exiled: nothing")
	owner.Eventbus.Write(C.eiExiled, [true])
	check_eq(_log.Kills, [_log.Sent[0].ID, _log.Sent[1].ID, _log.Sent[2].ID], "exile breaks all")
	_fire(owner, [a], [2])
	_bus.Trigger(C.eiLose, [2])
	check_eq(_log.Kills.back(), _log.Sent[3].ID, "the global eiLose breaks all")
	_fire(owner, [b], [2])
	owner.Eventbus.Trigger(C.eiDie, [0, 0])
	check_eq(_log.Kills.back(), _log.Sent[4].ID, "death breaks all")


## Breaking all walks the TDictionary in slot order while each break removes its entry. Dest IDs 1001 and 1005 hash
## to bucket 0 ((2 xor ID) + 1 = 1004 / 1008, 4 slots), 1008 to bucket 3 (1011): slots 0, 1, 3. Removing 1001 shifts
## 1005 back into slot 0, behind the walk: its link survives the owner's death.
func test_break_all_skips_a_shifted_link() -> void:
	_setup()
	var owner := _linker()
	var a := _unit(1, Vector2(2, 10), [C.upUnit], 68.0, 1001)
	var b := _unit(1, Vector2(3, 10), [C.upUnit], 68.0, 1005)
	var c := _unit(1, Vector2(4, 10), [C.upUnit], 68.0, 1008)
	_fire(owner, [a, b, c], [2])
	check_eq(_log.Sent.size(), 3, "three links")
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	owner.Eventbus.Trigger(C.eiDie, [0, 0])
	check_eq(log.Named("Break"), [[[2], 1001], [[2], 1008]], "1005 is skipped")
	check_eq(_log.Kills, [owner.ID, _log.Sent[0].ID, _log.Sent[2].ID], "the owner, then two links: b's lives on")
	check(_props(b).has(C.upInvisible), "b keeps the property")


# --- TLinkEventRedirecter ---

## Empty eiCooldown / eiWelaDamage / eiDamageType reads on a link come from the source's link effect group; values of
## its own stay; damage done and kills go to the source; with the source gone the reads are empty.
func test_link_event_redirecter() -> void:
	_setup()
	var source := _unit(1, Vector2(0, 10))
	var dest := _unit(2, Vector2(2, 10))
	source.Blackboard.SetValue(C.eiCooldown, [1], 500)
	source.Blackboard.SetValue(C.eiWelaDamage, [1], 15.0)
	source.Blackboard.SetValue(C.eiWelaDamage, [3], 99.0)
	source.Blackboard.SetValue(C.eiDamageType, [1], [C.dtRanged])
	var link := _link(source, dest)
	TLinkEventRedirecter.new().CreateGrouped(link, [C.ALLGROUP_INDEX], [0, 1])
	link.Blackboard.SetValue(C.eiWelaDamage, [1], 3.0)
	check_eq(RParam.AsInteger(link.Eventbus.Read(C.eiCooldown, [], [0])), 500, "cooldown from the source")
	check_eq(RParam.AsSingle(link.Eventbus.Read(C.eiWelaDamage, [], [0])), 15.0, "damage from the source's [0, 1]")
	check_eq(RParam.AsSingle(link.Eventbus.Read(C.eiWelaDamage, [], [1])), 3.0, "own damage stays")
	check_eq(RParam.AsSet(link.Eventbus.Read(C.eiDamageType, [])), [C.dtRanged], "damage type")
	var log: EntityLog = EntityLog.new().CreateGroupedAll(source)
	link.Eventbus.Trigger(C.eiDamageDone, [15.0, [C.dtRanged], dest], [0])
	link.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [dest.ID])
	check_eq(log.Log, [["DamageDone", [], 15.0, dest.ID], ["Shame", [], dest.ID]], "passed on to the source")
	_bus.Trigger(C.eiDelayedKillEntity, [source.ID])
	_frame(1010.0)
	_frame(1020.0)
	check(not _manager.HasEntityByID(source.ID), "the source is gone")
	check(RParam.IsEmpty(link.Eventbus.Read(C.eiCooldown, [], [0])), "source gone: empty")


# --- TLinkBrainComponent ---

## Cooldown 500 (redirected from the source): the first idle (t 1000) fetches it and starts; FiresAtCreate fires group
## [1] at the dest at once. Expired at 1500: one shot in [0] at the dest (and FiresAtSources [2] at the source). At
## 2700 it expired 2.4 times: two shots each, restart with the fraction (last time 2500), so the next is at 3000.
## Not ready at 3000: no shots, the timer restarts (next at 3500).
func test_link_brain() -> void:
	_setup()
	var source := _unit(1, Vector2(0, 10))
	var dest := _unit(2, Vector2(2, 10))
	source.Blackboard.SetValue(C.eiCooldown, [0], 500)
	var link := _link(source, dest)
	TLinkEventRedirecter.new().CreateGrouped(link, [C.ALLGROUP_INDEX], [0])
	TLinkBrainComponent.new().CreateGrouped(link, [0]).FiresAtCreate([1]).FiresAtSources([2])
	var ready: ReadySwitch = ReadySwitch.new().CreateGrouped(link, [0])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(link)
	var shots := func() -> Array: return log.Named("Fire").map(func(x): return [x[0], x[1], x[2]])
	_frame(1000.0)
	check_eq(shots.call(), [[[1], [dest.ID], 1000]], "at create in [1]")
	_frame(1499.0)
	check_eq(shots.call().size(), 1, "not yet")
	_frame(1500.0)
	check_eq(shots.call().slice(1), [[[0], [dest.ID], 1500], [[2], [source.ID], 1500]], "dest in [0], source in [2]")
	_frame(2700.0)
	check_eq(shots.call().slice(3), [[[0], [dest.ID], 2700], [[0], [dest.ID], 2700], [[2], [source.ID], 2700],
		[[2], [source.ID], 2700]], "twice each")
	_frame(2999.0)
	check_eq(shots.call().size(), 7, "the fraction carried over")
	ready.Ready = false
	_frame(3000.0)
	check_eq(shots.call().size(), 7, "not ready: no shots")
	ready.Ready = true
	_frame(3499.0)
	check_eq(shots.call().size(), 7, "restarted at 3000")
	_frame(3500.0)
	check_eq(shots.call().size(), 9, "fires at 3500")


# --- TWelaEffectLinkPayCostMyselfComponentServer ---

## Mana 3, 1 per second (group [1], paid groupless): the first link pays 1 at once (1000); a think at 2500 pays the
## 1 whole second (rest 500 carries); a second link costs nothing; breaking one of two pays nothing; a think at
## 3999 pays 1 (mana 0: emptied, fires [2] at the owner, not ready any more); breaking the last link pays the time
## since 3000 (already empty: no second fire); without links a think pays nothing.
func test_pay_cost_myself() -> void:
	_setup()
	var owner := _unit(1, Vector2(0, 10))
	owner.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reMana, 20)
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reMana, 3)
	owner.Blackboard.SetIndexedValue(C.eiResourceCost, [1], C.reMana, 1)
	var pay: TWelaEffectLinkPayCostMyselfComponentServer = TWelaEffectLinkPayCostMyselfComponentServer.new() \
		.CreateGrouped(owner, [1]).FireOnEmpty([2]).SetPayingGroupForType(C.reMana, [])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	var mana := func() -> int: return owner.BalanceInt(C.reMana)
	var a := RTarget.Create(11)
	var b := RTarget.Create(12)
	check(RParam.AsBoolean(owner.Eventbus.Read(C.eiIsReady, [], [1])), "ready with mana")
	owner.Eventbus.Trigger(C.eiLinkEstablish, [RTarget.Create(owner), a], [1])
	check_eq(mana.call(), 2, "the first link pays at once")
	TTimeManager.FakeTime = 2500.0
	owner.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq([mana.call(), pay.FLastAppliedTimestamp], [1, 2000], "one whole second paid, the rest carries")
	owner.Eventbus.Trigger(C.eiLinkEstablish, [RTarget.Create(owner), b], [1])
	check_eq([mana.call(), pay.FLinkCount], [1, 2], "a second link costs nothing extra")
	owner.Eventbus.Trigger(C.eiLinkBreak, [b], [1])
	check_eq([mana.call(), pay.FLinkCount], [1, 1], "breaking one of two pays nothing")
	TTimeManager.FakeTime = 3999.0
	owner.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq(mana.call(), 0, "emptied")
	check_eq(log.Named("Fire").map(func(x): return [x[0], x[1]]), [[[2], [owner.ID]]], "fires on empty")
	check(not RParam.AsBoolean(owner.Eventbus.Read(C.eiIsReady, [], [1])), "not ready any more")
	TTimeManager.FakeTime = 5000.0
	owner.Eventbus.Trigger(C.eiLinkBreak, [a], [1])
	check_eq(pay.FLinkCount, 0, "no links")
	check_eq(log.Named("Fire").size(), 1, "already empty: no second fire")
	var after: int = mana.call()
	TTimeManager.FakeTime = 9000.0
	owner.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq(mana.call(), after, "no links: nothing paid")


# --- TLinkEffectDamageRedirectionComponent / TLinkEffectFireAtProducedUnitsComponent ---

## Modifier 0.25: of 40 damage to the source, 10 goes to the dest as its own damage (types + dtIrredirectable +
## dtRedirected, same inflictor), 30 stays. Irredirectable damage stays whole. DestinationToSource hooks the dest.
func test_damage_redirection() -> void:
	_setup()
	var source := _unit(1, Vector2(0, 10), [], 100.0)
	var dest := _unit(1, Vector2(2, 10), [], 100.0)
	var link := _link(source, dest)
	link.Blackboard.SetValue(C.eiWelaModifier, [0], 0.25)
	TLinkEffectDamageRedirectionComponent.new().CreateGrouped(link, [0])
	link.Eventbus.Trigger(C.eiAfterCreate)
	var dlog: EntityLog = EntityLog.new().CreateGroupedAll(dest)
	source.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee], 77])
	check_eq([source.BalanceSingle(C.reHealth), dest.BalanceSingle(C.reHealth)], [70.0, 90.0], "30 stay, 10 go")
	var taken := dlog.Named("TakeDamage")
	check_eq(taken.size(), 1, "the dest took one hit")
	if taken.size() == 1:
		check_eq([taken[0][1], taken[0][2], taken[0][3]], [10.0, [C.dtMelee, C.dtIrredirectable, C.dtRedirected], 77],
			"its amount, types and inflictor")
	source.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee, C.dtIrredirectable], 77])
	check_eq([source.BalanceSingle(C.reHealth), dest.BalanceSingle(C.reHealth)], [30.0, 90.0], "irredirectable")
	link.Free()
	source.Eventbus.Read(C.eiTakeDamage, [10.0, [C.dtMelee], 77])
	check_eq([source.BalanceSingle(C.reHealth), dest.BalanceSingle(C.reHealth)], [20.0, 90.0], "unhooked with the link")
	var link2 := _link(source, dest)
	TLinkEffectDamageRedirectionComponent.new().CreateGrouped(link2, [0]).DestinationToSource()
	link2.Eventbus.Trigger(C.eiAfterCreate)
	dest.Eventbus.Read(C.eiTakeDamage, [10.0, [C.dtMelee], 77])
	check_eq([source.BalanceSingle(C.reHealth), dest.BalanceSingle(C.reHealth)], [10.0, 90.0],
		"DestinationToSource: all (no modifier) goes to the source")


## Every unit the dest produces makes the link fire at it in its group. The hook keeps the link component's group, so
## the dest's grouped announcement (a factory's fired group) does not reach it, only the groupless one after it.
func test_fire_at_produced_units() -> void:
	_setup()
	var source := _unit(1, Vector2(0, 10))
	var dest := _unit(1, Vector2(2, 10))
	var link := _link(source, dest)
	TLinkEffectFireAtProducedUnitsComponent.new().CreateGrouped(link, [3])
	link.Eventbus.Trigger(C.eiAfterCreate)
	var log: EntityLog = EntityLog.new().CreateGroupedAll(link)
	dest.Eventbus.Trigger(C.eiWelaUnitProduced, [77], [4])
	check_eq(log.Named("Fire").size(), 0, "the grouped announcement does not reach it")
	dest.Eventbus.Trigger(C.eiWelaUnitProduced, [77])
	check_eq(log.Named("Fire").map(func(x): return [x[0], x[1]]), [[[3], [77]]], "fires at the new unit")


# --- real scripts ---

## A real SmallCasterGolem (team 1) and an allied unit 3 away (in its 8.0 Crystal Power range): the golem links to
## it (CrystalPowerLink) and the ally gets upHasCrystalPower; when the golem dies its link is killed and, once the
## link is freed, the ally loses Crystal Power.
func test_real_crystal_power() -> void:
	_setup()
	var ally := _unit(1, Vector2(3, 10), [C.upUnit, C.upGround])
	var init := func(x):
		x.ID = _manager.GenerateUniqueID()
		x.Blackboard.SetValue(C.eiTeamID, [], 1)
		x.Position = Vector2(0, 10)
	var golem := TEntity.CreateFromScript("Units\\Colorless\\SmallCasterGolem", _bus, init)
	check(golem != null, "golem: " + TEntity.LastScriptError)
	if golem == null:
		return
	golem.Deploy()
	golem.Eventbus.Trigger(C.eiAfterCreate)
	var t := 1000.0
	while t < 3000.0 and not _props(ally).has(C.upHasCrystalPower):
		t += 10.0
		_frame(t)
	check(_props(ally).has(C.upHasCrystalPower), "the ally has Crystal Power")
	var links := _log.Sent.filter(func(e): return e.ScriptFileName() == "CrystalPowerLink")
	check_eq(links.size(), 1, "one link")
	if links.size() != 1:
		return
	var link: TEntity = links[0]
	check_eq(_dest_ids(link), [ally.ID], "to the ally")
	var link_id := link.ID
	golem.Eventbus.Read(C.eiTakeDamage, [500.0, [C.dtMelee], 0])
	check(_log.Kills.has(link_id), "the golem's death kills the link")
	for i in 3:
		t += 10.0
		_frame(t)
	check(not _manager.HasEntityByID(link_id), "the link is gone")
	check(not _props(ally).has(C.upHasCrystalPower), "the ally lost Crystal Power")


## A real GatlingTurret (team 1, 20 mana, 1 mana per second of link) and an enemy 4 away (range 6). Its link brain's
## LinkTime 500 expires at 1500 (a think, every 250 ms): it links to the enemy (GatlingTowerLink; the first link costs
## 1 mana). The link's brain starts in that same idle and fires every 500 ms (cooldown redirected from the turret) from
## 2000: the link's own 3 splash damage, then 15 spotty damage (the turret's). Mana is paid on the thinks at each
## whole second: 19 more seconds empty it at 20500; that think pays first, then the link brain finds the weapon not
## ready and breaks the link (the link still fires in that frame): 38 volleys, 9316 health left, no link afterwards.
func test_real_gatling_turret() -> void:
	_setup()
	var enemy := _unit(2, Vector2(4, 10), [C.upUnit, C.upGround], 10000.0)
	var init := func(x):
		x.ID = _manager.GenerateUniqueID()
		x.Blackboard.SetValue(C.eiTeamID, [], 1)
		x.Position = Vector2(0, 10)
	var turret := TEntity.CreateFromScript("Units\\Blue\\GatlingTurret", _bus, init)
	check(turret != null, "turret: " + TEntity.LastScriptError)
	if turret == null:
		return
	turret.Deploy()
	turret.Eventbus.Trigger(C.eiAfterCreate)
	var elog: EntityLog = EntityLog.new().CreateGroupedAll(enemy)
	var t := 1000.0
	var linked_at := -1.0
	var mana_at_3500 := -1
	while t < 25000.0:
		t += 10.0
		_frame(t)
		if linked_at < 0 and _log.Sent.any(func(e): return e.ScriptFileName() == "GatlingTowerLink"):
			linked_at = t
			check_eq(turret.BalanceInt(C.reMana), 19, "the first link costs 1 mana")
		if t == 3500.0:
			mana_at_3500 = turret.BalanceInt(C.reMana)
	check_eq(linked_at, 1500.0, "linked at 1500")
	check_eq(mana_at_3500, 17, "paid at 2500 and 3500")
	var hits := elog.Named("TakeDamage")
	check_eq(hits.slice(0, 2).map(func(x): return [x[1], x[5]]), [[3.0, 2000], [15.0, 2000]], "splash, then spotty")
	var spotty := hits.filter(func(x): return x[1] == 15.0)
	check_eq(spotty.size(), 38, "38 volleys")
	if spotty.size() == 38:
		check_eq([spotty[1][5], spotty[37][5]], [2500, 20500], "every 500 ms until 20500")
	check_eq(hits.size(), 76, "each with a splash")
	check_eq(turret.BalanceInt(C.reMana), 0, "out of ammo")
	check_eq(enemy.BalanceSingle(C.reHealth), 9316.0, "38 × 18 damage")
	var links := _log.Sent.filter(func(e): return e.ScriptFileName() == "GatlingTowerLink")
	check_eq(links.size(), 1, "one link, never rebuilt")
	if links.size() == 1:
		check(_log.Kills.has(links[0].ID), "the link was killed")
