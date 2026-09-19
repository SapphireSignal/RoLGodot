extends "res://tests/test_case.gd"
## The small combat modifiers: TWelaReadyNthComponent, TWelaReadyEntityNearbyComponent,
## TModifierMultiplyDealtDamageComponent, TModifierBlindedComponent (GameServer/BaseConflict.EntityComponents.Server.
## Welas.pas:215-770) and TBuffTakenDamageMultiplierComponent (...Server.pas:61), with real scripts: Blind.dws on a
## SmallMeleeGolem, the VoidSkeleton's bonus damage, Bleeding.dws's heal reduction and the ObserverDrone's "no enemy
## near" check. Random rolls: Godot's RNG is seeded and the expected rolls are replayed from the same seed.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TServerEntityManagerComponent


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
		return false

	func HasStarted() -> bool:
		return false

	func League() -> int:
		return 3


## Entity traffic (ALLGROUP): [name, called-to group, parameters...] in call order.
class EntityLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnTakeDamage", C.eiTakeDamage, C.epLast, C.etRead))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func OnFire(Targets) -> bool:
		Log.append(["Fire", TEventbus.CurrentEvent_CalledToGroup.duplicate(),
			ATarget.FromRParam(Targets).map(func(t): return t.EntityID)])
		return true

	func OnTakeDamage(Amount, DamageType, InflictorID, Previous):
		Log.append(["TakeDamage", Amount, RParam.AsSet(DamageType), InflictorID])
		return Previous


## Answers eiWelaUpdateTargets in its group with the targets it holds.
class FakeTargeting:
	extends TEntityComponent
	var Targets: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnUpdate", C.eiWelaUpdateTargets, C.epMiddle, C.etTrigger))

	func OnUpdate(List) -> bool:
		List.append_array(Targets)
		return true


func _setup() -> void:
	TTimeManager.SetFakeTime(1000.0)
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TServerEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_bus.Game.ServerEntityManager = _manager
	_bus.Game.CollisionManager = TServerCollisionManagerComponent.new().Create(_game_entity)


func after_each() -> void:
	TTimeManager.SetFakeTime(null)
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
	TEntity.LastScriptError = ""
	randomize()
	super()


func _unit(team: int, pos: Vector2, props: Array = [], health: float = 100.0) -> TEntity:
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


func _ready(e: TEntity, group: Array) -> bool:
	return RParam.AsBooleanDefaultTrue(e.Eventbus.Read(C.eiIsReady, [], group))


## The rolls randf() gives after seed(s).
static func _rolls(s: int, n: int) -> Array:
	seed(s)
	var Result: Array = []
	for i in n:
		Result.append(randf())
	seed(s)
	return Result


# --- TWelaReadyNthComponent ---

## Each check counts: Nth(3) is ready on checks 3, 6; Invert on all but those; Counter(1) starts one on (ready on
## check 2); Times(2) only the first two checks; Nth(2).Times(5): checks 2 and 4.
func test_ready_nth() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	TWelaReadyNthComponent.new().CreateGrouped(e, [1]).Nth(3)
	TWelaReadyNthComponent.new().CreateGrouped(e, [2]).Nth(3).Invert()
	TWelaReadyNthComponent.new().CreateGrouped(e, [3]).Nth(3).Counter(1)
	TWelaReadyNthComponent.new().CreateGrouped(e, [4]).Times(2)
	TWelaReadyNthComponent.new().CreateGrouped(e, [5]).Nth(2).Times(5)
	var seen := {}
	for g in [1, 2, 3, 4, 5]:
		seen[g] = []
		for i in 7:
			seen[g].append(_ready(e, [g]))
	check_eq(seen[1], [false, false, true, false, false, true, false], "each 3rd")
	check_eq(seen[2], [true, true, false, true, true, false, true], "all but each 3rd")
	check_eq(seen[3], [false, true, false, false, true, false, false], "counter from 1")
	check_eq(seen[4], [true, true, false, false, false, false, false], "the first 2")
	check_eq(seen[5], [false, true, false, true, false, false, false], "each 2nd of the first 5")


# --- TWelaReadyEntityNearbyComponent ---

## Asks the targeting of its targeting group: by default ready with no targets, ReadyIfTargets with some.
func test_ready_entity_nearby() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var targeting: FakeTargeting = FakeTargeting.new().CreateGrouped(e, [7])
	TWelaReadyEntityNearbyComponent.new().CreateGrouped(e, [6]).TargetingGroup([7])
	TWelaReadyEntityNearbyComponent.new().CreateGrouped(e, [8]).TargetingGroup([7]).ReadyIfTargets()
	check_eq([_ready(e, [6]), _ready(e, [8])], [true, false], "no targets")
	targeting.Targets = [RTarget.Create(99)]
	check_eq([_ready(e, [6]), _ready(e, [8])], [false, true], "a target")


## The real ObserverDrone's group 6 is ready while no enemy (ground or flying, like the drone) is in its radial range.
func test_real_observer_drone_nearby() -> void:
	_setup()
	var drone := _real("Units\\Blue\\ObserverDrone", 1, Vector2(0, 10))
	if drone == null:
		return
	check(_ready(drone, [6]), "alone: ready")
	_unit(1, Vector2(1, 10), [C.upUnit, C.upGround, C.upFlying])
	check(_ready(drone, [6]), "a friend does not count")
	_unit(2, Vector2(1, 10), [C.upUnit, C.upGround, C.upFlying])
	check(not _ready(drone, [6]), "an enemy next to it: not ready")


# --- TModifierMultiplyDealtDamageComponent ---

## eiWelaModifier 1.5 of value group [2], chance 0.5: rolls <= 0.5 multiply the damage so far (Previous if set) and
## fire [2] at the target; MustHave / MustNotHave filter the types.
func test_multiply_dealt_damage() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var target := _unit(2, Vector2(1, 0))
	e.Blackboard.SetValue(C.eiWelaModifier, [2], 1.5)
	e.Blackboard.SetValue(C.eiWelaChance, [2], 0.5)
	TModifierMultiplyDealtDamageComponent.new().CreateGrouped(e, [1]).MustHave([C.dtMelee]) \
		.MustNotHave([C.dtSpell]).SetValueGroup([2])
	var log: EntityLog = EntityLog.new().CreateGroupedAll(e)
	var rolls := _rolls(11, 6)
	var got: Array = []
	var want: Array = []
	for r in rolls:
		got.append(RParam.AsSingle(e.Eventbus.Read(C.eiWillDealDamage, [10.0, [C.dtMelee], target], [1])))
		want.append(15.0 if r <= 0.5 else 10.0)
	check_eq(got, want, "multiplied on the rolls <= 0.5")
	check_eq(log.Named("Fire").size(), want.count(15.0), "fires [2] on each")
	e.Blackboard.SetValue(C.eiWelaChance, [2], null)
	check_eq(RParam.AsSingle(e.Eventbus.Read(C.eiWillDealDamage, [10.0, [C.dtMelee], target], [1])), 15.0,
		"no chance: always")
	check_eq(log.Named("Fire").back(), [[2], [target.ID]], "fired at the target in [2]")
	check_eq(RParam.AsSingle(e.Eventbus.Read(C.eiWillDealDamage, [10.0, [C.dtRanged], target], [1])), 10.0,
		"MustHave melee")
	check_eq(RParam.AsSingle(e.Eventbus.Read(C.eiWillDealDamage, [10.0, [C.dtMelee, C.dtSpell], target], [1])), 10.0,
		"MustNotHave spell")


## The real VoidSkeleton: 150% melee damage against movement impaired targets ([2]), 200% against frozen ones ([3],
## where [2] refuses: MustNotHave frozen); spells unchanged.
func test_real_void_skeleton_bonus() -> void:
	_setup()
	var skeleton := _real("Units\\Black\\VoidSkeleton", 1, Vector2(0, 10))
	if skeleton == null:
		return
	var plain := _unit(2, Vector2(1, 10), [C.upUnit, C.upGround])
	var stunned := _unit(2, Vector2(1, 11), [C.upUnit, C.upGround, C.upStunned])
	var frozen := _unit(2, Vector2(1, 12), [C.upUnit, C.upGround, C.upFrozen, C.upStunned])
	var deal := func(t, types) -> float:
		return RParam.AsSingle(skeleton.Eventbus.Read(C.eiWillDealDamage, [16.0, types, t], [1]))
	check_eq([deal.call(plain, [C.dtMelee]), deal.call(stunned, [C.dtMelee]), deal.call(frozen, [C.dtMelee])],
		[16.0, 24.0, 32.0], "16, 24, 32")
	check_eq(deal.call(stunned, [C.dtMelee, C.dtSpell]), 16.0, "spells unchanged")


# --- TModifierBlindedComponent ---

## Real Blind.dws on a real SmallMeleeGolem: the golem is upBlinded; each main weapon fire rolls, a roll <= 0.5
## misses: the blind group fires at the golem and the warhead is stopped (no damage); hits deal the golem's damage.
func test_real_blind() -> void:
	_setup()
	var golem := _real("Units\\Colorless\\SmallMeleeGolem", 1, Vector2(0, 10))
	if golem == null:
		return
	var target := _unit(2, Vector2(1, 10), [C.upUnit, C.upGround], 1000.0)
	golem.ApplyScript("Modifiers\\Blind.dws", "Apply", [golem])
	check(RParam.AsSet(golem.Eventbus.Read(C.eiUnitProperties, [])).has(C.upBlinded), "blinded")
	var log: EntityLog = EntityLog.new().CreateGroupedAll(golem)
	var tlog: EntityLog = EntityLog.new().CreateGroupedAll(target)
	var rolls := _rolls(5, 8)
	for r in rolls:
		golem.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(target))], [1])
	var misses := rolls.filter(func(r): return r <= 0.5).size()
	check(misses > 0 and misses < 8, "the seed gives both")
	var blind_fires := log.Named("Fire").filter(func(x): return x[0] != [1])
	check_eq(blind_fires.size(), misses, "the blind group fires on each miss")
	check(blind_fires.all(func(x): return x[1] == [golem.ID]), "at the golem")
	check_eq(tlog.Named("TakeDamage").size(), 8 - misses, "only hits deal damage")
	# a groupless fire does not roll
	var found: Array = []
	golem.Eventbus.Trigger(C.eiEnumerateComponents, [func(c) -> void: found.append(c)])
	var state = found.filter(func(c): return c is TModifierBlindedComponent)[0]
	var before: bool = state.FWillMiss
	seed(5)
	golem.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(target))])
	check_eq(state.FWillMiss, before, "no roll without a group")


## A missing shooter's projectile is marked upProjectileWillMiss.
func test_blinded_projectile() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var blinded: TModifierBlindedComponent = TModifierBlindedComponent.new().CreateGrouped(e, [1])
	var p := _unit(1, Vector2.ZERO)
	blinded.FWillMiss = true
	e.Eventbus.Trigger(C.eiWelaShotProjectile, [p], [1])
	check(RParam.AsSet(p.Blackboard.GetValue(C.eiUnitProperties, [])).has(C.upProjectileWillMiss), "marked")
	var q := _unit(1, Vector2.ZERO)
	blinded.FWillMiss = false
	e.Eventbus.Trigger(C.eiWelaShotProjectile, [q], [1])
	check(not RParam.AsSet(q.Blackboard.GetValue(C.eiUnitProperties, [])).has(C.upProjectileWillMiss), "hit: unmarked")


# --- TBuffTakenDamageMultiplierComponent ---

## Modifier 0.5 on ranged damage: 40 ranged → 20 taken; melee untouched; no modifier value: untouched. Flat 15: 40 → 25
## (at least 1: 10 → 1). MustHaveAny.
func test_taken_damage_multiplier() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO, [], 1000.0)
	e.Blackboard.SetValue(C.eiWelaModifier, [3], 0.5)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(e, [3]).DamageTypeMustHave([C.dtRanged])
	var health := func() -> float: return e.BalanceSingle(C.reHealth)
	e.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtRanged], 0])
	check_eq(health.call(), 980.0, "halved")
	e.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee], 0])
	check_eq(health.call(), 940.0, "melee untouched")
	var f := _unit(1, Vector2.ZERO, [], 1000.0)
	f.Blackboard.SetValue(C.eiWelaModifier, [3], 15.0)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(f, [3]).Flat().DamageTypeMustHaveAny([C.dtMelee, C.dtRanged])
	f.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee], 0])
	check_eq(f.BalanceSingle(C.reHealth), 975.0, "flat: 15 off")
	f.Eventbus.Read(C.eiTakeDamage, [10.0, [C.dtRanged], 0])
	check_eq(f.BalanceSingle(C.reHealth), 974.0, "flat: at least 1")
	f.Eventbus.Read(C.eiTakeDamage, [10.0, [C.dtSpell], 0])
	check_eq(f.BalanceSingle(C.reHealth), 964.0, "none of MustHaveAny: untouched")
	var n := _unit(1, Vector2.ZERO, [], 1000.0)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(n, [3])
	n.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee], 0])
	check_eq(n.BalanceSingle(C.reHealth), 960.0, "no modifier value: untouched")


## Dodge (chance 0.3): a roll < 0.3 takes nothing and fires its group at the owner, else full damage.
func test_taken_damage_dodge() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO, [], 1000.0)
	e.Blackboard.SetValue(C.eiWelaModifier, [3], 0.3)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(e, [3]).DodgeDamage()
	var log: EntityLog = EntityLog.new().CreateGroupedAll(e)
	var rolls := _rolls(3, 10)
	var want := 1000.0
	for r in rolls:
		e.Eventbus.Read(C.eiTakeDamage, [10.0, [C.dtMelee], 0])
		if r >= 0.3:
			want -= 10.0
	check_eq(e.BalanceSingle(C.reHealth), want, "dodged the rolls < 0.3")
	check_eq(log.Named("Fire").size(), rolls.filter(func(r): return r < 0.3).size(), "fires on each dodge")


## Reflect (0.25): the inflictor takes the reduced 30 of 40 as irredirectable damage inflicted by itself; its own
## reflection buff does not send it back. Flat 15 reflects what is left (25).
func test_taken_damage_reflect() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO, [], 1000.0)
	var attacker := _unit(2, Vector2(1, 0), [], 1000.0)
	e.Blackboard.SetValue(C.eiWelaModifier, [3], 0.25)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(e, [3]).ReflectReducedDamage()
	attacker.Blackboard.SetValue(C.eiWelaModifier, [3], 0.5)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(attacker, [3]).ReflectReducedDamage()
	var alog: EntityLog = EntityLog.new().CreateGroupedAll(attacker)
	e.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee], attacker.ID])
	check_eq(e.BalanceSingle(C.reHealth), 990.0, "takes a quarter")
	check_eq(alog.Named("TakeDamage"), [[15.0, [C.dtMelee, C.dtIrredirectable], attacker.ID]],
		"30 reflected, halved by the attacker's own buff, not sent back")
	check_eq(attacker.BalanceSingle(C.reHealth), 985.0, "the attacker took 15")
	e.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee, C.dtIrredirectable], attacker.ID])
	check_eq(attacker.BalanceSingle(C.reHealth), 985.0, "irredirectable damage is not reflected")
	var f := _unit(1, Vector2.ZERO, [], 1000.0)
	f.Blackboard.SetValue(C.eiWelaModifier, [3], 15.0)
	TBuffTakenDamageMultiplierComponent.new().CreateGrouped(f, [3]).Flat().ReflectReducedDamage()
	var plain := _unit(2, Vector2(1, 0), [], 1000.0)
	f.Eventbus.Read(C.eiTakeDamage, [40.0, [C.dtMelee], plain.ID])
	check_eq([f.BalanceSingle(C.reHealth), plain.BalanceSingle(C.reHealth)], [975.0, 975.0],
		"flat: 25 taken and 25 reflected")


## Real Bleeding.dws: heals are cut to 60% (ApplyOnHeal); damage untouched.
func test_real_bleeding_heal() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO, [], 100.0)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, 50.0)
	e.ApplyScript("Modifiers\\Bleeding.dws", "Apply", [e])
	check(RParam.AsSet(e.Eventbus.Read(C.eiUnitProperties, [])).has(C.upBleeding), "bleeding")
	var healed := RParam.AsSingle(e.Eventbus.Read(C.eiHeal, [10.0, [], 0]))
	check_eq([healed, e.BalanceSingle(C.reHealth)], [6.0, 56.0], "10 heal → 6")
	e.Eventbus.Read(C.eiTakeDamage, [10.0, [C.dtMelee], 0])
	check_eq(e.BalanceSingle(C.reHealth), 46.0, "damage untouched")
