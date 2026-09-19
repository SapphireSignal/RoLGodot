extends "res://tests/test_case.gd"
## DelphiSort (Delphi 10.1 TArray.QuickSort), the targeting welas TWelaTargeting{,Radial,RadialAttention,Nexus,Self}
## Component (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:40-116, :1117-1245, :1567-1818, :2785,
## :3229) and the TWelaEfficiency* components (:828-885, :3036-3181).
## The game has the real entity manager and server collision manager over the Single map's boundaries. The owner
## (team 1, radius 0.5) stands at the origin; its wela is group 1, eiWelaRange 5.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent
var _owner: TEntity


class FakeMap:
	extends RefCounted
	var MapBoundaries := Rect2(-150, -150, 300, 300)


class FakeGame:
	extends RefCounted
	var Map := FakeMap.new()

	func IsShuttingDown() -> bool:
		return false

	var EntityManager = null
	var CollisionManager = null


## Records eiWelaYoureMyTarget: the IDs of the entities that targeted its owner.
class TargetProbe:
	extends TGDEntityComponent
	var TargetedBy: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnYoureMyTarget", C.eiWelaYoureMyTarget, C.epLast, C.etTrigger))

	func OnYoureMyTarget(Attacker) -> bool:
		TargetedBy.append(Attacker.ID)
		return true


## Answers eiEnumerateNexus like the nexus entities do.
class NexusMarker:
	extends TGDEntityComponent

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnEnumerateNexus", C.eiEnumerateNexus, C.epMiddle, C.etRead, C.esGlobal))

	func OnEnumerateNexus(Previous):
		var List: Array = Previous if Previous is Array else []
		List.append(Owner)
		return List


## A lane whose weighted distance punishes leaving the x axis ten times.
class FakeLane:
	extends RefCounted

	func GetWeightedDistance(Pos: Vector2, Target: Vector2) -> float:
		return absf(Target.x - Pos.x) + 10 * absf(Target.y - Pos.y)


func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_bus.Game.CollisionManager = TServerCollisionManagerComponent.new().Create(_game_entity)
	_owner = _unit(1, Vector2.ZERO)
	_owner.Blackboard.SetValue(C.eiWelaRange, [1], 5.0)


func after_each() -> void:
	TTimeManager.SetFakeTime(null)
	if _game_entity != null:
		_bus.Game.CollisionManager = null  # the units leave the tree without it while the game entity goes
		_game_entity.Free()  # frees the managers and every deployed entity
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	_owner = null
	TEntity.SetLastScriptError("")
	super()


func _unit(team: int, pos: Vector2, props: Array = [], radius: float = 0.5) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Position = pos
	e.CollisionRadius = radius
	TCollisionComponent.new().Create(e)
	e.Deploy()
	return e


func _probe(e: TEntity) -> TargetProbe:
	return TargetProbe.new().Create(e)


func _radial(group: Array = [1]) -> TWelaTargetingRadialComponent:
	return TWelaTargetingRadialComponent.new().CreateGrouped(_owner, group)


## eiWelaUpdateTargets in the group on a copy of current; returns the target entity IDs.
func _update(current: Array = [], group: Array = [1]) -> Array:
	var list := current.duplicate()
	_owner.Eventbus.Trigger(C.eiWelaUpdateTargets, [list], group)
	var ids: Array = []
	for t in list:
		ids.append(t.EntityID)
	return ids


func _validate(target, group: Array = [1]) -> bool:
	return RParam.AsBoolean(_owner.Eventbus.Read(C.eiWelaValidateTarget,
		[RTarget.Create(target) if target != null else null], group))


func _max_health(e: TEntity, cap: float) -> void:
	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reHealth, cap)


func _key_compare(a: Array, b: Array) -> int:
	return a[0] - b[0]


func test_delphi_sort() -> void:
	var values: Array = [[3, "a"], [1, "b"], [2, "c"], [5, "d"], [4, "e"], [0, "f"]]
	DelphiSort.Sort(values, _key_compare)
	var keys: Array = []
	for v in values:
		keys.append(v[0])
	check_eq(keys, [0, 1, 2, 3, 4, 5], "sorted by key")
	# two equal elements: pivot = first, neither loop moves, I <= J swaps them (Berlin has no 2-element shortcut)
	var ties: Array = [[1, "a"], [1, "b"]]
	DelphiSort.Sort(ties, _key_compare)
	check_eq([ties[0][1], ties[1][1]], ["b", "a"], "equal pair swapped")
	# [1a, 1b, 1c]: pivot 1b; I=0/J=2 swap -> c b a, I=1/J=1 self, I=2/J=0; L<J no; L=2 >= R: done
	var three: Array = [[1, "a"], [1, "b"], [1, "c"]]
	DelphiSort.Sort(three, _key_compare)
	check_eq([three[0][1], three[1][1], three[2][1]], ["c", "b", "a"], "equal triple reversed")


func test_radial_picks_nearest_enemy() -> void:
	_setup()
	_radial()
	var ally := _unit(1, Vector2(1, 0))
	var near := _unit(2, Vector2(3, 0))
	var far := _unit(2, Vector2(4, 0))
	var out := _unit(2, Vector2(7, 0))
	var near_probe := _probe(near)
	var far_probe := _probe(far)
	check_eq(_update(), [near.ID], "one slot (eiWelaTargetCount default 1): the nearest enemy")
	check_eq(near_probe.TargetedBy, [_owner.ID], "the target gets eiWelaYoureMyTarget [Owner]")
	check_eq(_update([RTarget.Create(far)]), [far.ID], "a full list is kept as it is")
	check_eq(far_probe.TargetedBy, [], "kept targets get no event")
	_owner.Blackboard.SetValue(C.eiWelaTargetCount, [1], 5)
	var ids := _update()
	ids.sort()
	var expected := [near.ID, far.ID]
	expected.sort()
	check_eq(ids, expected, "five slots: every enemy in range, not the ally, not the one at 7")
	check(not ids.has(ally.ID) and not ids.has(out.ID), "ally and out of range left out")
	check_eq(_update([RTarget.Create(far)]), [far.ID, near.ID], "current targets stay first, no duplicates")


func test_radial_priorities() -> void:
	_setup()
	var radial := _radial()
	var near := _unit(2, Vector2(2, 0))
	var mid := _unit(2, Vector2(0, 3))
	var far := _unit(2, Vector2(-4, 0))
	_owner.Blackboard.SetValue(C.eiWelaTargetCount, [1], 2)
	check_eq(_update(), [near.ID, mid.ID], "nearest first")
	radial.PrioritizeMostDistant()
	check_eq(_update(), [far.ID, mid.ID], "most distant first")
	radial.FPrioritizeMostDistant = false
	radial.PrioritizeMiddleDistant()
	# range 5.5, half 2.75: |2-2.75| = 0.75, |3-2.75| = 0.25, |4-2.75| = 1.25
	check_eq(_update(), [mid.ID, near.ID], "nearest to half the range first")
	radial.FPrioritizeMiddleDistant = false
	near.Blackboard.SetValue(C.eiUnitProperties, [], [C.upLowPrio])
	check_eq(_update(), [mid.ID, far.ID], "upLowPrio goes behind on equal efficiency")
	TWelaEfficiencyMaxHealthComponent.new().CreateGrouped(_owner, [1])
	_max_health(near, 100.0)
	_max_health(mid, 50.0)
	_max_health(far, 300.0)
	check_eq(_update(), [far.ID, near.ID], "efficiency (max health) beats distance and low priority")


func test_radial_cone_and_range_event() -> void:
	_setup()
	var radial := _radial()
	var behind := _unit(2, Vector2(-2, -2))
	var side := _unit(2, Vector2(0, 3))
	var ahead := _unit(2, Vector2(4, 0))
	radial.Cone(Vector2(1, 0), PI / 2)
	_owner.Blackboard.SetValue(C.eiWelaTargetCount, [1], 3)
	check_eq(_update(), [ahead.ID], "a 90 degree cone to +x: only the unit ahead")
	# (0, 3): 90 degrees off, its width angle atan(0.5 / 3) does not reach the 45 degree half cone
	radial.Cone(0.0, 1.0, PI)
	var ids := _update()
	ids.sort()
	var expected := [side.ID, ahead.ID]
	expected.sort()
	check_eq(ids, expected, "Cone(x, z, angle): half plane to +y, the unit ahead touches it with its radius")
	check(not ids.has(behind.ID), "behind stays out")
	radial.FCone = 0.0
	_owner.Blackboard.SetValue(C.eiAttentionrange, [1], 1.0)
	radial.RangeFromEvent(C.eiAttentionrange)
	check_eq(_update(), [], "RangeFromEvent(eiAttentionrange): 1 + 0.5 reaches nobody")


func test_radial_validate() -> void:
	_setup()
	var radial := _radial()
	var enemy := _unit(2, Vector2(5.8, 0))
	check(_validate(enemy), "5.8 <= range 5 + own 0.5 + its 0.5")
	check(not _validate(null), "an empty target is not valid")
	check(not _validate(Vector2(1, 0)), "a coordinate has no efficiency: not valid")
	radial.IgnoreOwnCollisionradius()
	check(not _validate(enemy), "without the own radius 5.5 < 5.8")
	enemy.Position = Vector2(5, 0)
	check(_validate(enemy), "moved into range")
	enemy.Blackboard.SetValue(C.eiExiled, [], true)
	check(not _validate(enemy), "exiled: not possible")
	enemy.Blackboard.SetValue(C.eiExiled, [], false)
	TWelaTargetConstraintUnitPropertyComponent.new().CreateGrouped(_owner, [3]).MustNotHave([C.upInvisible])
	enemy.Blackboard.SetValue(C.eiUnitProperties, [], [C.upInvisible])
	check(_validate(enemy), "the constraint sits in group 3, the wela validates against its own group")
	radial.SetValidateGroup([3])
	check(not _validate(enemy), "SetValidateGroup([3]): the group-3 constraint now applies")


func test_random_picks() -> void:
	_setup()
	var radial := _radial()
	radial.PicksRandomTargets()
	var a := _unit(2, Vector2(2, 0))
	var b := _unit(2, Vector2(0, 2))
	var c := _unit(2, Vector2(-2, 0))
	_owner.Blackboard.SetValue(C.eiWelaTargetCount, [1], 5)
	var ids := _update()
	ids.sort()
	var expected := [a.ID, b.ID, c.ID]
	expected.sort()
	check_eq(ids, expected, "random without repetition: every enemy once")
	radial.MaxNewTargetCount(2)
	check_eq(_update().size(), 2, "MaxNewTargetCount(2)")
	radial.FMaxNewTargetCount = 0
	radial.PicksRandomTargetsWithRepetition()
	_owner.Blackboard.SetValue(C.eiWelaTargetCount, [1], 7)
	check_eq(_update().size(), 7, "with repetition the slots fill up with repeats")
	var radial2 := _radial([2])
	radial2.SetTargetTeamConstraintPriority(C.tcAllies).PicksRandomTargets()
	var ally := _unit(1, Vector2(1, 1))
	_owner.Blackboard.SetValue(C.eiWelaRange, [2], 5.0)
	_owner.Blackboard.SetValue(C.eiWelaTargetCount, [2], 2)
	ids = _update([], [2])
	ids.sort()
	expected = [_owner.ID, ally.ID]
	expected.sort()
	check_eq(ids, expected, "priority allies: team 1 (the owner and its ally) before the enemies")


func test_radial_attention() -> void:
	_setup()
	var attention := TWelaTargetingRadialAttentionComponent.new().CreateGrouped(_owner, [0])
	_owner.Blackboard.SetValue(C.eiAttentionrange, [0], 10.0)
	var beyond := _unit(2, Vector2(11, 0))
	check_eq(_update([RTarget.Create(beyond)], [0]), [], "11 is in the extended 12 but not in 10: cleared, empty")
	var side := _unit(2, Vector2(0, 5))
	var lane := _unit(2, Vector2(8, 0))
	check_eq(_update([], [0]), [side.ID], "no lane: the nearest")
	_owner.Blackboard.SetValue(C.eiGetLane, [], FakeLane.new())
	check_eq(_update([], [0]), [lane.ID], "with a lane: the least weighted distance")
	attention.DisableStraightPreference()
	check_eq(_update([], [0]), [side.ID], "DisableStraightPreference: the nearest again")
	check(not _validate(side, [0]), "efficiency 0 is not enough to stay a target")
	TWelaEfficiencyUnitPropertyComponent.new().CreateGrouped(_owner, [0]).Reverse()
	check(_validate(side, [0]), "efficiency 1 within attention range")
	check(not _validate(beyond, [0]), "beyond attention range (radii do not count)")


func test_nexus_and_self() -> void:
	_setup()
	TWelaTargetingNexusComponent.new().CreateGrouped(_owner, [4])
	TWelaTargetingSelfComponent.new().CreateGrouped(_owner, [5])
	var own_nexus := _unit(1, Vector2(-100, 0))
	NexusMarker.new().Create(own_nexus)
	var other_nexus := _unit(2, Vector2(150, 0))
	NexusMarker.new().Create(other_nexus)
	# far_nexus: 100 away, the nearest enemy nexus
	var far_nexus := _unit(3, Vector2(100, 0))
	NexusMarker.new().Create(far_nexus)
	check_eq(_update([RTarget.Create(own_nexus)], [4]), [far_nexus.ID], "the nearest enemy nexus")
	check(not _validate(far_nexus, [4]), "efficiency 0: not valid")
	TWelaEfficiencyMaxHealthComponent.new().CreateGrouped(_owner, [4, 5])
	_max_health(far_nexus, 1000.0)
	check(_validate(far_nexus, [4]), "positive efficiency: valid")
	check(not _validate(Vector2(100, 0), [4]), "a coordinate is not")
	check_eq(_update([RTarget.Create(far_nexus)], [5]), [_owner.ID], "self: the owner only")
	check(not _validate(_owner, [5]), "self with efficiency 0 (no health cap): not valid")
	_max_health(_owner, 10.0)
	check(_validate(_owner, [5]), "self with a health cap")
	check(not _validate(far_nexus, [5]), "self does not validate others")


func test_efficiency_components() -> void:
	TTimeManager.SetFakeTime(1000.0)
	_setup()
	var target := _unit(2, Vector2(1, 0), [C.upFlying])
	target.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, 30.0)
	_max_health(target, 100.0)
	target.Blackboard.SetValue(C.eiDamageType, [C.GROUP_MAINWEAPON], [C.dtMelee])
	TTimeManager.SetFakeTime(1500.0)
	var cases := [
		[TWelaEfficiencyMissingHealthComponent.new(), 70.0, "missing health 100 - 30"],
		[TWelaEfficiencyCreatedComponent.new(), 500.0, "age 1500 - 1000 ms"],
		[TWelaEfficiencyMaxHealthComponent.new(), 100.0, "max health"],
	]
	var group := 10
	for c in cases:
		c[0].CreateGrouped(_owner, [group])
		check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [group])), c[1], c[2])
		group += 1
	var inverse = TWelaEfficiencyMaxHealthComponent.new().CreateGrouped(_owner, [20]).Inverse()
	check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [20])), 9900.0, "inverse: 10000 - 100")
	TWelaEfficiencyDamageTypeComponent.new().CreateGrouped(_owner, [21]).Prioritize([C.dtMelee])
	check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [21])), 1.0, "melee main weapon")
	TWelaEfficiencyDamageTypeComponent.new().CreateGrouped(_owner, [22]).Prioritize([C.dtRanged])
	check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [22])), 0.0, "not ranged")
	TWelaEfficiencyUnitPropertyComponent.new().CreateGrouped(_owner, [23]).Prioritize([C.upFlying, C.upMonumental])
	check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [23])), 1.0, "flying")
	TWelaEfficiencyUnitPropertyComponent.new().CreateGrouped(_owner, [24]).Prioritize([C.upBuilding]).Reverse()
	check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [24])), 1.0, "reversed: not a building")
	TWelaEfficiencyUnitPropertyComponent.new().CreateGrouped(_owner, [20]).Reverse()
	check_eq(RParam.AsSingle(_owner.Eventbus.Read(C.eiEfficiency, [target], [20])), 9901.0, "components of a group add up")
	check(inverse != null, "inverse built")


## Real script: two server SmallMeleeGolems (range 1 in [0, 1], radius 0.55, attention 22; group 0 attention
## targeting, group 1 radial targeting). Radial reach = 1 + 0.55 + 0.55 = 2.1.
func test_real_golems() -> void:
	_setup()
	var golems: Array = []
	for i in 2:
		var team: int = i + 1
		var pos := Vector2(0, 10) if i == 0 else Vector2(2.0, 10)
		var init := func(x):
			x.ID = _manager.GenerateUniqueID()
			x.Blackboard.SetValue(C.eiTeamID, [], team)
			x.Position = pos
		var g := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus, init)
		check(g != null, "created: " + TEntity.GetLastScriptError())
		if g == null:
			return
		g.Deploy()
		golems.append(g)
	_owner = golems[0]
	check_eq(_update([], [1]), [golems[1].ID], "golem 2 at 2.0 is within the radial reach 2.1")
	check(_validate(golems[1], [1]), "and valid")
	golems[1].Position = Vector2(2.3, 10)
	check(not _validate(golems[1], [1]), "at 2.3 no longer valid")
	check_eq(_update([], [1]), [], "nor found")
	check_eq(_update([], [0]), [golems[1].ID], "attention (22) still approaches it")
	golems[1].Blackboard.SetValue(C.eiUnitProperties, [], DSet.Union(golems[1].UnitProperties(), [C.upInvisible]))
	check_eq(_update([], [0]), [], "invisible: the constraints on [0, 1] rule it out")
