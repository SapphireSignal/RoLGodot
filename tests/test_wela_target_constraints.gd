extends "res://tests/test_case.gd"
## RTarget / ATarget / RTargetValidity (BaseConflict.Types.Target.pas) and the TWelaTargetConstraint* and
## TWelaTriggerCheck* components (BaseConflict.EntityComponents.Shared.Wela.pas:1363-1830, :2666-3240).
## A wela in group 1 of the owner (team 1); eiWelaTargetPossible read [ATarget] in [1] returns an RTargetValidity.
## The game uses the real TEntityManagerComponent.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent
var _owner: TEntity


class FakeGame:
	extends RefCounted
	var EntityManager = null

	func IsShuttingDown() -> bool:
		return false



func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_owner = _unit(1)


func after_each() -> void:
	if _game_entity != null:
		_game_entity.Free()  # frees the manager and every deployed entity
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	_owner = null
	super()


func _unit(team: int, props: Array = [], pos := Vector2.ZERO) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Position = pos
	e.Deploy()
	return e


func _validity(targets: Array, group: Array = [1], event: int = C.eiWelaTargetPossible):
	return _owner.Eventbus.Read(event, [ATarget.ToRParam(targets)], group)


func _valid(target, group: Array = [1]) -> bool:
	return RTargetValidity.FromRParam(_validity(ATarget.Make(target), group)).IsValid()


func test_target_types() -> void:
	check(RTarget.Create(Vector2(1, 1)).Equal(RTarget.Create(Vector2(1.05, 0.95))), "coordinates within 0.1 are equal")
	check(not RTarget.Create(Vector2(1, 1)).Equal(RTarget.Create(Vector2(1.1, 1))), "0.1 apart is not")
	check(RTarget.Create(5).Equal(RTarget.Create(5)) and not RTarget.Create(5).Equal(RTarget.Create(Vector2.ZERO)), "entity")
	check(RTarget.Create(null).IsEmpty(), "nil entity: empty")
	var list := [RTarget.Create(Vector2.ZERO), RTarget.Create(7)]
	check(ATarget.Contains(list, RTarget.Create(7)), "contains the entity")
	check(not ATarget.Contains(list, RTarget.Create(Vector2.ZERO)), "Contains only works for entities")
	var v := RTargetValidity.Create([RTarget.Create(3), RTarget.CreateEmpty()])
	check(not v.IsValid(), "an empty target is invalid from the start")
	v = RTargetValidity.Create([RTarget.Create(3)])
	v.SetValidity(0, false)
	v.SetValidity(0, true)
	check(not v.IsValid(), "once invalid, stays invalid")
	check(RTargetValidity.FromRParam(null).IsValid(), "from an empty RParam: valid")


func test_team_unit_property_not_self() -> void:
	_setup()
	TWelaTargetConstraintEnemiesComponent.new().CreateGrouped(_owner, [1])
	TWelaTargetConstraintUnitPropertyComponent.new().CreateGrouped(_owner, [1]).MustNotHave([C.upInvisible])
	TWelaTargetConstraintNotSelfComponent.new().CreateGrouped(_owner, [1])
	var enemy := _unit(2)
	var ally := _unit(1)
	var hidden := _unit(2, [C.upInvisible])
	check(_valid(enemy), "enemy")
	check(not _valid(ally), "ally")
	check(not _valid(_owner), "self")
	check(not _valid(hidden), "invisible enemy")
	check(not _valid(Vector2(3, 3)), "a spot: no entity")
	check(not RTargetValidity.FromRParam(_validity([RTarget.Create(enemy), RTarget.Create(ally)])).IsValid(),
			"one invalid target of two: invalid")
	check_eq(_validity(ATarget.Make(ally), [2]), null, "reads to other groups are not checked")
	check_eq(_validity(ATarget.Make(ally), [1], C.eiWarheadTargetPossible), null, "warhead checks are separate")


func test_allies_team_id_and_warhead() -> void:
	_setup()
	TWelaTargetConstraintAlliesComponent.new().CreateGrouped(_owner, [1]).ConstraintsWarhead()
	TWelaTargetConstraintTeamIDComponent.new().CreateGrouped(_owner, [2]).SetTargetTeam(3).Invert()
	var ally := _unit(1)
	var enemy := _unit(2)
	var team3 := _unit(3)
	check_eq(_validity(ATarget.Make(enemy)), null, "ConstraintsWarhead: not a wela check")
	check(RTargetValidity.FromRParam(_validity(ATarget.Make(ally), [1], C.eiWarheadTargetPossible)).IsValid(), "ally ok")
	check(not RTargetValidity.FromRParam(_validity(ATarget.Make(enemy), [1], C.eiWarheadTargetPossible)).IsValid(), "enemy not")
	check(_valid(enemy, [2]), "Invert: team 2 is not team 3")
	check(not _valid(team3, [2]), "Invert: team 3 excluded")


func test_resource() -> void:
	_setup()
	var target := _unit(2)
	target.Eventbus.Write(C.eiResourceCap, [C.reHealth, 100.0])
	target.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 40.0])
	var c: TWelaTargetConstraintResourceComponent = TWelaTargetConstraintResourceComponent.new().CreateGrouped(_owner, [1])
	c.CheckResource(C.reHealth).CheckNotFull()
	check(_valid(target), "40 of 100: not full")
	c.CheckFull()
	check(not _valid(target), "not full")
	c.CompareMissingToReference().Comparator(C.coGreaterEqual).Reference(60)
	check(_valid(target), "missing 60 >= 60")
	c.CheckResource(C.reMana)
	check(not _valid(target), "no mana at all: never possible")


func test_resource_compare() -> void:
	_setup()
	_owner.Eventbus.Write(C.eiResourceCap, [C.reHealth, 200.0])
	_owner.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 50.0])
	var target := _unit(2)
	target.Eventbus.Write(C.eiResourceCap, [C.reHealth, 100.0])
	target.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 100.0])
	var c: TWelaTargetConstraintResourceCompareComponent = TWelaTargetConstraintResourceCompareComponent.new().CreateGrouped(_owner, [1])
	c.ComparedResource(C.reHealth).SetComparator(C.coLower)
	check(_valid(target), "own 50 < target 100")
	c.TargetFactor(0.5)
	check(not _valid(target), "50 < 100 * 0.5 is false")
	c.ComparesResourceCap().SetComparator(C.coGreater).TargetFactor(1.5)
	check(_valid(target), "caps: 200 > 150")


func test_boolean() -> void:
	_setup()
	TWelaTargetConstraintTeamIDComponent.new().CreateGrouped(_owner, [2]).SetTargetTeam(2)
	TWelaTargetConstraintUnitPropertyComponent.new().CreateGrouped(_owner, [3]).MustHave([C.upBuilding])
	var b: TWelaTargetConstraintBooleanComponent = TWelaTargetConstraintBooleanComponent.new().CreateGrouped(_owner, [1]).GroupA([2]).GroupB([3])
	var unit2 := _unit(2)
	var tower2 := _unit(2, [C.upBuilding])
	var tower3 := _unit(3, [C.upBuilding])
	check(not _valid(unit2) and _valid(tower2), "AND: team 2 building")
	b.OperatorOr()
	check(_valid(unit2) and _valid(tower3), "OR")
	b.OperatorAnd().NotB()
	check(_valid(unit2) and not _valid(tower2), "team 2 and NOT a building")


func test_dynamic_zone() -> void:
	_setup()
	var tower := _unit(1, [], Vector2(10, 0))
	tower.Blackboard.SetValue(C.eiWelaRange, [3], 5.0)
	TDynamicZoneRadialEmitterComponent.new().CreateGrouped(tower, [3]).SetZone([C.dzDrop])
	var c: TWelaTargetConstraintDynamicZoneComponent = TWelaTargetConstraintDynamicZoneComponent.new().CreateGrouped(_owner, [1]).SetZone([C.dzDrop])
	check(_valid(Vector2(12, 0)), "near our tower")
	check(not _valid(Vector2(20, 0)), "outside")
	check(_valid(_unit(2, [], Vector2(11, 0))), "an entity target counts at its position")
	tower.Blackboard.SetValue(C.eiTeamID, [], 2)
	check(not _valid(Vector2(12, 0)), "enemy tower's zone")
	c.IgnoresTeams()
	check(_valid(Vector2(12, 0)), "IgnoresTeams")


func test_card_name_creator_event_wela_property() -> void:
	_setup()
	var golem := _unit(2)
	golem.FScriptFile = "Units\\Colorless\\SmallMeleeGolem.ets"
	TWelaTargetConstraintCardNameComponent.new().CreateGrouped(_owner, [1]).AddCard("Nexus").AddCard("smallmelee")
	check(_valid(golem), "file name starts with it, case ignored")
	check(not _valid(_unit(2)), "other card")

	TWelaTargetConstraintCreatorIsAliveComponent.new().CreateGrouped(_owner, [2])
	var spawned := _unit(2)
	spawned.Blackboard.SetValue(C.eiCreator, [], golem.ID)
	check(_valid(spawned, [2]), "creator alive")
	spawned.Blackboard.SetValue(C.eiCreator, [], 999)
	check(not _valid(spawned, [2]), "creator gone")

	TWelaTargetConstraintEventComponent.new().CreateGrouped(_owner, [3], C.eiDamageable)
	golem.Blackboard.SetValue(C.eiDamageable, [], true)
	check(_valid(golem, [3]), "eiDamageable true")
	check(not _valid(spawned, [3]), "eiDamageable empty")

	TWelaTargetConstraintWelaPropertyComponent.new().CreateGrouped(_owner, [4]).MustNotHave([C.dtRanged])
	golem.Blackboard.SetValue(C.eiDamageType, [C.GROUP_MAINWEAPON], [C.dtMelee])
	spawned.Blackboard.SetValue(C.eiDamageType, [C.GROUP_MAINWEAPON], [C.dtRanged])
	check(_valid(golem, [4]) and not _valid(spawned, [4]), "main weapon damage types")
	check(_valid(Vector2.ZERO, [4]), "no entity: possible")


func test_compare_unit_property_and_blacklist() -> void:
	_setup()
	_owner.Blackboard.SetValue(C.eiUnitProperties, [], [C.upGround])
	TWelaTargetConstraintCompareUnitPropertyComponent.new().CreateGrouped(_owner, [1]).BothMustHaveAny([C.upGround, C.upFlying])
	check(_valid(_unit(2, [C.upGround])), "both ground")
	check(not _valid(_unit(2, [C.upFlying])), "ground vs flying share nothing")

	var saved := _unit(2)
	TWelaTargetConstraintBlacklistComponent.new().CreateGrouped(_owner, [2])
	_owner.Blackboard.SetValue(C.eiWelaSavedTargets, [2], ATarget.Make(saved))
	check(not _valid(saved, [2]), "saved target")
	check(_valid(_unit(2), [2]), "other target")


## Quirk kept: the check only compares empty targets, so far apart targets stay valid.
func test_max_target_distance() -> void:
	_setup()
	_owner.Blackboard.SetValue(C.eiAbilityTargetRange, [1], 5.0)
	TWelaTargetConstraintMaxTargetDistanceComponent.new().CreateGrouped(_owner, [1])
	check(RTargetValidity.FromRParam(_validity([RTarget.Create(Vector2.ZERO), RTarget.Create(Vector2(100, 0))])).IsValid(),
			"100 apart, range 5: still valid")


func test_trigger_checks() -> void:
	_setup()
	TWelaTriggerCheckNotSelfComponent.new().CreateGrouped(_owner, [1])
	var threshold: TWelaTriggerCheckTakeDamageThresholdComponent = TWelaTriggerCheckTakeDamageThresholdComponent.new().CreateGrouped(_owner, [1])
	_owner.Blackboard.SetValue(C.eiWelaDamage, [1], 20.0)
	var check_ := func(amount: float, inflictor: int): return _owner.Eventbus.Read(C.eiWelaTriggerCheck, [amount, [], inflictor], [1])
	check_eq(check_.call(25.0, 99), true, "25 >= 20 from someone else")
	check_eq(check_.call(15.0, 99), false, "below the threshold")
	check_eq(check_.call(25.0, _owner.ID), false, "own damage")
	threshold.LesserEqual()
	check_eq(check_.call(15.0, 99), true, "LesserEqual")


## Real script: two server SmallMeleeGolems (Event eiDamageable, CompareUnitProperty ground/flying, UnitProperty
## not invisible/banished on groups [0, 1]). Golem 1 may attack golem 2 until golem 2 turns invisible.
func test_real_golem_targets() -> void:
	_setup()
	var golems: Array = []
	for team in [1, 2]:
		var init := func(x):
			x.ID = _manager.GenerateUniqueID()
			x.Blackboard.SetValue(C.eiTeamID, [], team)
		var g := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus, init)
		check(g != null, "created: " + TEntity.LastScriptError)
		if g == null:
			return
		g.Deploy()
		golems.append(g)
	_owner = golems[0]
	check(_manager.HasEntityByID(golems[1].ID), "deployed into the entity manager")
	check(_valid(golems[1]), "an enemy golem is a valid target")
	golems[1].Blackboard.SetValue(C.eiUnitProperties, [], DSet.Union(golems[1].UnitProperties(), [C.upInvisible]))
	check(not _valid(golems[1]), "invisible: not a target")
