extends "res://tests/test_case.gd"
## The splash warheads TWarheadSplash{,Health,Damage,Heal}Component and TWarheadSpottyTeleportComponent
## (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:222-291, :655-1066): the capped damage / heal
## distribution, the area filters, a real server MeleeGolemTower's cone splash, and teleports (to a spot, to the
## team's nexus with offset, by projectile, the owner to its target).
## The game has the real server entity and collision managers; units have 68 health and no armor unless real.

const C = preload("res://src/runtime/dws/dws_const.gd")

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
	var IngameStatus := 2  # BC.gsPlaying
	var League := 3
	var Map := FakeMap.new()
	var EntityManager = null
	var ServerEntityManager = null
	var CollisionManager = null
	var DelayedEvents := TIntPriorityQueue.new()


class GlobalLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnReplace", C.eiReplaceEntity, C.epFirst, C.etTrigger, C.esGlobal))

	func OnReplace(OldID, NewID, IsSame) -> bool:
		Log.append(["Replace", OldID, NewID, IsSame])
		return true


## Traffic of one entity (ALLGROUP): [name, parameters...].
class EntityLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnExiled", C.eiExiled, C.epFirst, C.etWrite))
		e.append(XEvent("OnStand", C.eiStand, C.epFirst, C.etTrigger))
		e.append(XEvent("OnSync", C.eiSyncPosition, C.epFirst, C.etTrigger))
		e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnHealDone", C.eiHealDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnKillDone", C.eiKillDone, C.epFirst, C.etTrigger))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func OnExiled(Exiled) -> bool:
		Log.append(["Exiled", Exiled])
		return true

	func OnStand() -> bool:
		Log.append(["Stand"])
		return true

	func OnSync(Position) -> bool:
		Log.append(["Sync", Position])
		return true

	func OnDamageDone(Amount, DamageType, Target) -> bool:
		Log.append(["DamageDone", snappedf(Amount, 0.0001), DamageType, Target.ID])
		return true

	func OnHealDone(Amount, DamageType, Target) -> bool:
		Log.append(["HealDone", snappedf(Amount, 0.0001), DamageType, Target.ID])
		return true

	func OnKillDone(ID) -> bool:
		Log.append(["KillDone", ID, TEventbus.CurrentEvent_CalledToGroup.duplicate()])
		return true


## Answers eiEnumerateNexus like the nexus entities do.
class NexusMarker:
	extends TEntityComponent

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnEnumerateNexus", C.eiEnumerateNexus, C.epMiddle, C.etRead, C.esGlobal))

	func OnEnumerateNexus(Previous):
		var List: Array = Previous if Previous is Array else []
		List.append(Owner)
		return List


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
	if _game_entity != null:
		_bus.Game.CollisionManager = null
		_bus.Game.ServerEntityManager = null
		_bus.Game.DelayedEvents.Clear()
		_game_entity.Free()
		_bus.Game.Map.BuildZones.Free()
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	_log = null
	TEntity.LastScriptError = ""
	super()


## A unit in the collision tree (radius 0.5) with health.
func _unit(team: int, pos: Vector2, health: float = 68.0, props: Array = [C.upGround]) -> TEntity:
	var e := _shooter(team, pos, props)
	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reHealth, 68.0)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, health)
	THealthComponent.new().Create(e)
	e.CollisionRadius = 0.5
	TCollisionComponent.new().Create(e)
	return e


## A deployed entity outside the collision tree (the warheads' owner).
func _shooter(team: int, pos: Vector2, props: Array = [C.upGround]) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Position = pos
	e.Front = Vector2(0, 1)
	e.Deploy()
	return e


func _health(e: TEntity) -> float:
	return snappedf(e.BalanceSingle(C.reHealth), 0.0001)


func _splash(owner: TEntity, damage: float, factor = null, aoe: float = 3.0) -> void:
	owner.Blackboard.SetValue(C.eiWelaDamage, [1], damage)
	owner.Blackboard.SetValue(C.eiDamageType, [1], [C.dtMelee])
	owner.Blackboard.SetValue(C.eiWelaAreaOfEffect, [1], aoe)
	if factor != null:
		owner.Blackboard.SetValue(C.eiWelaSplashfactor, [1], factor)


func _fire(owner: TEntity, target) -> void:
	owner.Eventbus.Trigger(C.eiFireWarhead, [[RTarget.Create(target)]], [1])


# --- the distribution (:779) ---

## 10 per unit, 20 in all over health 3, 50, 50: the weak one takes its 3, the other two share the remaining 11
## (5.5 each, under what is left of the per-unit cap, 7): 3 + 8.5 + 8.5 = 20. Types get dtSplash. With only two
## units in reach (3 and 50) the per-unit cap binds: 3 + 7 = 10 dealt, the 7 left are spread and capped at 10: 6.5 / 10.
func test_splash_damage_shared() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var a := _unit(2, Vector2(0, 0), 3.0)
	var b := _unit(2, Vector2(2, 0), 50.0)
	var c := _unit(2, Vector2(-2, 0), 50.0)
	_splash(owner, 10.0, 2.0)
	TWarheadSplashDamageComponent.new().CreateGrouped(owner, [1])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	_fire(owner, a)
	check_eq([_health(a), _health(b), _health(c)], [0.0, 41.5, 41.5], "3 / 8.5 / 8.5 taken")
	var done := log.Named("DamageDone")
	check_eq(done.size(), 3, "damage done for each")
	check_eq(done.map(func(x): return x[1]), [[C.dtMelee, C.dtSplash], [C.dtMelee, C.dtSplash], [C.dtMelee, C.dtSplash]], "types + dtSplash")
	check_eq(log.Named("KillDone"), [[a.ID, [1]]], "the weak one is killed")
	var d := _unit(2, Vector2(20, 0), 3.0)
	var e := _unit(2, Vector2(22, 0), 50.0)
	_fire(owner, d)
	check_eq([_health(d), _health(e)], [0.0, 40.0], "two in reach: 6.5 (on 3 health) and 10")


## 2 per unit, 20 in all over health 1, 1, 5: the round cap (2) runs out after two rounds, the rest is spread over
## everyone and capped at 2: all take 2.
func test_splash_damage_rest_spread() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var a := _unit(2, Vector2(0, 0), 1.0)
	var b := _unit(2, Vector2(2, 0), 1.0)
	var c := _unit(2, Vector2(-2, 0), 5.0)
	_splash(owner, 2.0, 10.0)
	TWarheadSplashDamageComponent.new().CreateGrouped(owner, [1])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	_fire(owner, a)
	check_eq(_health(c), 3.0, "the strong one takes the full 2")
	var dealt: Array = log.Named("DamageDone").map(func(x): return x[0])
	dealt.sort()
	check_eq(dealt, [1.0, 1.0, 2.0], "the weak ones had 1 health to lose")
	check_eq(log.Named("KillDone").size(), 2, "two killed")


## Without eiWelaSplashfactor (10000) everyone takes the full damage; AmountIsPercentage: damage × health cap.
func test_splash_damage_uncapped_and_percentage() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var a := _unit(2, Vector2(2, 0))
	var b := _unit(2, Vector2(0, 2))
	_splash(owner, 10.0)
	var w: TWarheadSplashDamageComponent = TWarheadSplashDamageComponent.new().CreateGrouped(owner, [1])
	_fire(owner, a)
	check_eq([_health(a), _health(b)], [58.0, 58.0], "10 each")
	w.AmountIsPercentage()
	owner.Blackboard.SetValue(C.eiWelaDamage, [1], 0.25)
	_fire(owner, a)
	check_eq([_health(a), _health(b)], [41.0, 41.0], "a quarter of 68 each")


## Heal 10 over units missing 2 and 30 (and one at full health, skipped): 2 and 8.
func test_splash_heal() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var a := _unit(1, Vector2(2, 0), 66.0)
	var b := _unit(1, Vector2(0, 2), 38.0)
	var full := _unit(1, Vector2(-2, 0), 68.0)
	_splash(owner, 10.0, 1.0)
	TWarheadSplashHealComponent.new().CreateGrouped(owner, [1])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(owner)
	_fire(owner, a)
	check_eq([_health(a), _health(b), _health(full)], [68.0, 46.0, 68.0], "2 and 8 healed")
	check_eq(log.Named("HealDone").map(func(x): return [x[0], x[2]]), [[2.0, a.ID], [8.0, b.ID]], "heal done")


# --- the area filters (:699) ---

## IgnoreMainTargets spares the target; a ground target spares flyers (TargetsGroundAndAir hits both); units beyond
## eiWelaAreaOfEffect (+ their radius) are safe.
func test_splash_filters() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var main := _unit(2, Vector2(0, 0))
	var near := _unit(2, Vector2(2, 0))
	var flyer := _unit(2, Vector2(0, 2), 68.0, [C.upFlying])
	var far := _unit(2, Vector2(3.6, 0))
	_splash(owner, 10.0)
	var w: TWarheadSplashDamageComponent = TWarheadSplashDamageComponent.new().CreateGrouped(owner, [1])
	w.IgnoreMainTargets()
	_fire(owner, main)
	check_eq([_health(main), _health(near), _health(flyer), _health(far)], [68.0, 58.0, 68.0, 68.0], "only the near unit")
	w.TargetsGroundAndAir()
	_fire(owner, main)
	check_eq([_health(main), _health(near), _health(flyer)], [68.0, 48.0, 58.0], "flyers too")
	_fire(owner, flyer)
	check_eq([_health(main), _health(flyer)], [58.0, 58.0], "a flyer target: everything in range but itself")


## LineFromOwner(1): the line from the owner (0, 0) towards the target, eiWelaAreaOfEffect (6) long; units whose
## circle comes within 0.5 of it are hit.
func test_splash_line() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, 0))
	var target := _unit(2, Vector2(4, 0))
	var on_line := _unit(2, Vector2(2, 0.9))
	var off_line := _unit(2, Vector2(2, 1.2))
	var at_end := _unit(2, Vector2(5.9, 0))
	var behind := _unit(2, Vector2(-1, 0))
	_splash(owner, 10.0, null, 6.0)
	TWarheadSplashDamageComponent.new().CreateGrouped(owner, [1]).LineFromOwner(1.0)
	_fire(owner, target)
	check_eq([_health(target), _health(on_line), _health(off_line), _health(at_end), _health(behind)],
		[58.0, 58.0, 68.0, 58.0, 68.0], "on the line only")


## The real server MeleeGolemTower (team 1) fires its splash wela (group 2: 0.333 × 150 damage, eiWelaAreaOfEffect 2,
## cone 3.141 = the half circle towards the target) at an enemy SmallMeleeGolem in front: the one beside it is hit
## too (both 49.95 × light armor 0.85 = 42.4575), the one behind and the one out of range are not, nor its ally.
func test_real_tower_splash() -> void:
	_setup()
	var tower := _real("Units\\Colorless\\MeleeGolemTower", 1, Vector2(0, 0))
	var front := _real("Units\\Colorless\\SmallMeleeGolem", 2, Vector2(1.5, 0))
	var side := _real("Units\\Colorless\\SmallMeleeGolem", 2, Vector2(0, 1.5))
	var back := _real("Units\\Colorless\\SmallMeleeGolem", 2, Vector2(-1.5, 0))
	var far := _real("Units\\Colorless\\SmallMeleeGolem", 2, Vector2(3, 0))
	var ally := _real("Units\\Colorless\\SmallMeleeGolem", 1, Vector2(0, -1.5))
	if tower == null or front == null or side == null or back == null or far == null or ally == null:
		return
	tower.Eventbus.Trigger(C.eiFire, [[RTarget.Create(front)]], [2])
	var hurt := func(e): return absf(e.BalanceSingle(C.reHealth) - (68.0 - 42.4575)) < 0.001
	check(hurt.call(front) and hurt.call(side), "front and side take 42.4575 (%s, %s)" % [_health(front), _health(side)])
	check_eq([_health(back), _health(far), _health(ally)], [68.0, 68.0, 68.0], "behind, out of range, ally: untouched")


func _real(script: String, team: int, pos: Vector2) -> TEntity:
	var init := func(x):
		x.ID = _manager.GenerateUniqueID()
		x.Blackboard.SetValue(C.eiTeamID, [], team)
		x.Position = pos
	var e := TEntity.CreateFromScript(script, _bus, init)
	check(e != null, script + ": " + TEntity.LastScriptError)
	if e != null:
		e.Deploy()
		e.Eventbus.Trigger(C.eiAfterCreate)
	return e


# --- teleport (:925) ---

## ToCoordinate: the target is exiled, re-keyed (eiReplaceEntity [old, new, True]) so targeting lets go of it, put
## on the spot, stands, syncs its position and comes back.
func test_teleport_to_coordinate() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var t := _unit(2, Vector2(0, 0))
	var old_id := t.ID
	var log: EntityLog = EntityLog.new().CreateGroupedAll(t)
	TWarheadSpottyTeleportComponent.new().CreateGrouped(owner, [1]).ToCoordinate(20, 5)
	_fire(owner, t)
	check_eq(_log.Log, [["Replace", old_id, old_id + 1, true]], "re-keyed with the next unique ID")
	check_eq(t.ID, old_id + 1, "the entity has its new ID")
	check_eq(_manager.GetEntityByID(old_id + 1), t, "registered under it")
	check_eq(t.Position, Vector2(20, 5), "on the spot")
	check_eq(log.Log, [["Exiled", true], ["Stand"], ["Sync", Vector2(20, 5)], ["Exiled", false]], "exile, stand, sync, back")


## ToNexus with Offset(1) + OffsetByCollisionRadius: the team's nexus at (10, 0), the unit coming from (0, 0) lands
## 1 + 0.5 + 0.5 short of it on its side: (8, 0).
func test_teleport_to_nexus_with_offset() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var nexus := _shooter(2, Vector2(10, 0))
	nexus.CollisionRadius = 0.5
	NexusMarker.new().Create(nexus)
	var t := _unit(2, Vector2(0, 0))
	TWarheadSpottyTeleportComponent.new().CreateGrouped(owner, [1]).ToNexus().Offset(1.0).OffsetByCollisionRadius()
	_fire(owner, t)
	check_eq(t.Position, Vector2(8, 0), "beside its nexus")


## AsProjectile (Homeland): the unit is exiled and a projectile of eiWelaUnitPattern flies from it; the projectile
## carries a teleport warhead in group [0] imprinted with the unit and aimed at the landing spot, which is also its
## saved target. When it fires, the unit lands there (no second exile or re-key). Its commander is the owner's ID.
func test_teleport_as_projectile() -> void:
	_setup()
	var owner := _shooter(1, Vector2(0, -20))
	var nexus := _shooter(2, Vector2(10, 0))
	nexus.CollisionRadius = 0.5
	NexusMarker.new().Create(nexus)
	var t := _unit(2, Vector2(0, 0))
	owner.Blackboard.SetValue(C.eiWelaUnitPattern, [1], "Projectiles\\Black\\SoulGatherProjectile")
	TWarheadSpottyTeleportComponent.new().CreateGrouped(owner, [1]).ToNexus().Offset(1.0).OffsetByCollisionRadius() \
		.AsProjectile()
	var log: EntityLog = EntityLog.new().CreateGroupedAll(t)
	var count_before := _manager.GetDeployedEntityCount()
	_fire(owner, t)
	check_eq(_manager.GetDeployedEntityCount(), count_before + 1, "a projectile")
	check_eq(t.Position, Vector2(0, 0), "not moved yet")
	check_eq(log.Log, [["Exiled", true]], "exiled")
	var p: TEntity = _manager.GetDeployedEntityList().back()
	check_eq([p.Position, p.Front, p.CommanderID()], [Vector2(0, 0), Vector2(1, 0), owner.ID], "from the unit, towards the nexus")
	var saved: Array = ATarget.FromRParam(p.Eventbus.Read(C.eiWelaSavedTargets, []))
	check_eq(saved.size() == 1 and saved[0].IsCoordinate() and saved[0].FTargetCoord == Vector2(8, 0), true, "aimed at (8, 0)")
	var replaced := _log.Log.size()
	p.Eventbus.Trigger(C.eiFireWarhead, [saved], [0])
	check_eq(t.Position, Vector2(8, 0), "landed")
	check_eq(log.Log, [["Exiled", true], ["Stand"], ["Sync", Vector2(8, 0)], ["Exiled", false]], "lands and comes back")
	check_eq(_log.Log.size(), replaced, "no second re-key")


## Neither nexus nor fixed target: the owner goes to its target.
func test_teleport_owner_to_target() -> void:
	_setup()
	var owner := _unit(1, Vector2(0, -20))
	var t := _unit(2, Vector2(3, 4))
	TWarheadSpottyTeleportComponent.new().CreateGrouped(owner, [1])
	_fire(owner, t)
	check_eq([owner.Position, t.Position], [Vector2(3, 4), Vector2(3, 4)], "the owner jumped to the target")
