extends "res://tests/test_case.gd"
## TWelaHelperResolveComponent, TWarheadApplyScriptComponent and TWarheadLinkApplyScriptComponent
## (BaseConflict.EntityComponents.Shared.Wela.pas:855-990, implementation :2317-2758).
## The game uses the real TEntityManagerComponent; applied scripts are real server scripts.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent


class FakeBuildZones:
	extends RefCounted

	func UpdateEntityIDInBuildZones(_OldID, _NewID) -> void:
		pass


class FakeMap:
	extends RefCounted
	var BuildZones := FakeBuildZones.new()
	var Lanes := TLaneManager.new().Create()


class FakeGame:
	extends RefCounted
	var Statistics := TGameStatisticManager.new().Create()

	func IsShuttingDown() -> bool:
		return false

	var Commanders: Array = []
	var EntityManager = null
	var Map := FakeMap.new()


## Answers the global eiGameEventTimeTo read [Name] like the game's event timers.
class GameEventClock:
	extends TGDEntityComponent
	var TimeTo := {}

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnGameEventTimeTo", C.eiGameEventTimeTo, C.epMiddle, C.etRead, C.esGlobal))

	func OnGameEventTimeTo(Name, _Previous):
		return TimeTo.get(Name, 0)


func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager


func after_each() -> void:
	if _game_entity != null:
		_game_entity.Free()  # frees the manager and every deployed entity
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	super()


func _unit(team: int, pos := Vector2.ZERO) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Position = pos
	e.Deploy()
	return e


func _golem(team: int) -> TEntity:
	var init := func(x):
		x.ID = _manager.GenerateUniqueID()
		x.Blackboard.SetValue(C.eiTeamID, [], team)
	var g := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus, init)
	check(g != null, "golem created: " + TEntity.GetLastScriptError())
	if g != null:
		g.Deploy()
	return g


# ---- TWelaHelperResolveComponent -----------------------------------------------------------------------------

func test_resolve_team_id_and_level() -> void:
	_setup()
	var e := _unit(2)
	e.Blackboard.SetValue(C.eiWelaDamage, [2], 5.0)
	e.Blackboard.SetIndexedValue(C.eiWelaDamage, [2], 2, 9.0)
	var r: TWelaHelperResolveComponent = TWelaHelperResolveComponent.new().CreateGrouped(e, [2]).ResolveTeamID()
	check_eq(e.Eventbus.Read(C.eiWelaDamage, [], [2]), 9.0, "team 2: index 2")
	e.Blackboard.SetValue(C.eiTeamID, [], 1)
	check_eq(e.Eventbus.Read(C.eiWelaDamage, [], [2]), 5.0, "nothing at index 1: the plain value")
	check_eq(e.Eventbus.Read(C.eiWelaRange, [], [2]), null, "nothing saved at all: empty")
	e.Blackboard.SetIndexedValue(C.eiWelaUnitPattern, [2], 1, "Units\\A")
	check_eq(e.Eventbus.Read(C.eiWelaUnitPattern, [], [2]), "Units\\A", "strings too")
	r.ResolveLevel([3])
	e.Eventbus.Write(C.eiResourceBalance, [C.reLevel, 2], [3])
	check_eq(e.Eventbus.Read(C.eiWelaDamage, [], [2]), 9.0, "level 2 of group 3")
	r.ResolveResource(C.reLevel, [4])
	check_eq(e.Eventbus.Read(C.eiWelaDamage, [], [2]), 5.0, "no level in group 4: index 0, the plain value")


func test_resolve_tiers() -> void:
	_setup()
	var clock: GameEventClock = GameEventClock.new().Create(_game_entity)
	var e := _unit(1)
	for i in 4:
		e.Blackboard.SetIndexedValue(C.eiCooldown, [2], i, 100 * i)
	var r: TWelaHelperResolveComponent = TWelaHelperResolveComponent.new().CreateGrouped(e, [2]).ResolveCurrentTier()
	clock.TimeTo = {C.GAME_EVENT_TECH_LEVEL_2: 500, C.GAME_EVENT_TECH_LEVEL_3: 900}
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 0, "before tech 2: tier index 0")
	clock.TimeTo = {C.GAME_EVENT_TECH_LEVEL_3: 400}
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 100, "tech 2 reached: 1")
	clock.TimeTo = {}
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 200, "tech 3 reached: 2")
	r.ResolveTier()
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 300, "owner without tier: 3")
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upTier2])
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 200, "tier 2 gives 2")
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upTier1])
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 100, "tier 1 gives 1")


# ---- TWarheadApplyScriptComponent ----------------------------------------------------------------------------

## Real script: Modifiers\BlessingHealth fired at a server SmallMeleeGolem (68 health) raises its cap by 70.4.
func test_apply_on_fire_warhead() -> void:
	_setup()
	var caster := _unit(1)
	var golem := _golem(2)
	if golem == null:
		return
	TWarheadApplyScriptComponent.new().CreateGrouped(caster, [0], "Modifiers\\BlessingHealth.dws")
	caster.Eventbus.Trigger(C.eiFireWarhead, [ATarget.ToRParam(ATarget.Make(golem))], [1])
	check(not golem.HasUnitProperty(C.upBlessedHealth), "fired in another group: nothing")
	caster.Eventbus.Trigger(C.eiFireWarhead, [ATarget.ToRParam([RTarget.Create(Vector2(3, 3)), RTarget.Create(golem)])], [0])
	check(golem.HasUnitProperty(C.upBlessedHealth), "applied to the entity target")
	check(absf(RParam.AsSingle(golem.Cap(C.reHealth)) - 138.4) < 0.001, "cap 68 + 70.4, got %s" % golem.Cap(C.reHealth))


## Real script: Modifiers\SummoningSickness(Entity, Duration) on produced units, like the 79 drop spawners.
func test_apply_to_produced_units() -> void:
	_setup()
	var spawner := _unit(1)
	var golem := _golem(1)
	if golem == null:
		return
	TWarheadApplyScriptComponent.new().CreateGrouped(spawner, [C.GROUP_DROP_SPAWNER], "Modifiers\\SummoningSickness.dws").ApplyToProducedUnits().PassIntValue(1000)
	spawner.Eventbus.Trigger(C.eiFireWarhead, [ATarget.ToRParam(ATarget.Make(golem))], [C.GROUP_DROP_SPAWNER])
	check(not golem.HasUnitProperty(C.upSummoningSickness), "ApplyToProducedUnits: not at fire")
	spawner.Eventbus.Trigger(C.eiWelaUnitProduced, [golem.ID], [C.GROUP_DROP_SPAWNER])
	check(golem.HasUnitProperty(C.upSummoningSickness), "applied to the produced unit")
	var found := false
	for group in range(TEntity.RESERVED_GROUPS - 1, 40):
		if golem.Blackboard.GetValue(C.eiCooldown, [group]) == 1000:
			found = true
	check(found, "Duration 1000 passed after the entity")


## ApplyToSelfAtCreate applies at eiAfterCreate and frees itself at the next Idle; ApplyToSelfAfterDelay waits for
## the first global eiIdle after the delay.
func test_apply_to_self() -> void:
	_setup()
	TTimeManager.SetFakeTime(1000.0)
	var golem := _golem(1)
	if golem == null:
		TTimeManager.SetFakeTime(null)
		return
	var at_create: TWarheadApplyScriptComponent = TWarheadApplyScriptComponent.new().CreateGrouped(golem, [], "Modifiers\\SummoningSickness.dws").PassIntValue(2200).ApplyToSelfAtCreate()
	var delayed: TWarheadApplyScriptComponent = TWarheadApplyScriptComponent.new().CreateGrouped(golem, [], "Modifiers\\BlessingHealth.dws").ApplyToSelfAfterDelay(500)
	golem.Eventbus.Trigger(C.eiAfterCreate)
	check(golem.HasUnitProperty(C.upSummoningSickness), "applied at create")
	_manager.Idle()
	check(at_create.Owner == null, "freed after applying")
	_bus.Trigger(C.eiIdle)
	check(not golem.HasUnitProperty(C.upBlessedHealth), "delay not over")
	TTimeManager.SetFakeTime(1500.0)
	_bus.Trigger(C.eiIdle)
	check(golem.HasUnitProperty(C.upBlessedHealth), "applied after the delay")
	_manager.Idle()
	check(delayed.Owner == null, "freed after applying")
	TTimeManager.SetFakeTime(null)


## Pass* parameters in call order after the entity; values as GetValue computes them.
func test_parameter_values() -> void:
	_setup()
	var caster := _unit(1, Vector2(0, 0))
	var target := _unit(2, Vector2(3, 4))
	caster.Blackboard.SetValue(C.eiWelaDamage, [5], 12.5)
	caster.Blackboard.SetValue(C.eiFront, [], Vector2(0, 1))
	caster.Blackboard.SetValue(C.eiWelaSavedTargets, [5], [RTarget.Create(Vector2(7, 8)), RTarget.Create(target)])
	caster.Eventbus.Write(C.eiResourceBalance, [C.reCardLeague, 3], [5])
	var w: TWarheadApplyScriptComponent = TWarheadApplyScriptComponent.new().CreateGrouped(caster, [5], "x")
	w.PassValueFromEvent(C.eiTeamID).PassValueFromEvent(C.eiWelaDamage).PassValueFromEvent(C.eiFront)
	w.PassSavedTargetPosition(1).PassResource(C.reCardLeague).PassIntValue(7).PassSingleValue(0.5).PassBooleanValue(true)
	w.PassSameTeam().PassDirectionToTarget().PassOffsetToOwner()
	w.FCurrentTarget = target
	var values: Array = []
	for p in w.FParameters:
		values.append(p.GetValue(w, caster.Eventbus, w.ComponentGroup))
	w.FCurrentTarget = null
	check_eq(values, [1, 12.5, Vector2(0, 1), Vector2(3, 4), 3, 7, 0.5, true, false, Vector2(0.6, 0.8), Vector2(3, 4)], "values")
	check_eq(w.FParameters[2].PublicEvent, true, "eiFront is read without a group")
	w.OverrideLastParameterGroup([6])
	caster.Blackboard.SetValue(C.eiWelaDamage, [6], 2.0)
	check_eq(w.FParameters.back().UsesGroupOverride, true, "override flag")
	w.PassValueFromEvent(C.eiWelaDamage).OverrideLastParameterGroup([6])
	check_eq(w.FParameters.back().GetValue(w, caster.Eventbus, w.ComponentGroup), 2.0, "read from the override group")


# ---- TWarheadLinkApplyScriptComponent ------------------------------------------------------------------------

## Real script: Links\Invisible on the link's destination; removed again when the link component goes.
func test_link_apply_and_remove() -> void:
	_setup()
	var golem := _golem(2)
	var other := _golem(2)
	if golem == null or other == null:
		return
	var link := _unit(1)
	link.Blackboard.SetValue(C.eiLinkDest, [], ATarget.Make(golem))
	link.Blackboard.SetValue(C.eiCreator, [], 77)
	link.Blackboard.SetValue(C.eiCreatorGroup, [], [3])
	var c: TWarheadLinkApplyScriptComponent = TWarheadLinkApplyScriptComponent.new().CreateGrouped(link, [], "Links\\Invisible.dws")
	link.Eventbus.Trigger(C.eiAfterCreate)
	check(golem.HasUnitProperty(C.upInvisible), "applied to the link destination")
	check(not c.FSavedScriptGroup.is_empty(), "groups saved")
	check_eq(golem.Eventbus.Read(C.eiCreator, [], c.FSavedScriptGroup), 77, "creator copied")
	check_eq(golem.Eventbus.Read(C.eiCreatorGroup, [], c.FSavedScriptGroup), [3], "creator group copied")
	link.Eventbus.Trigger(C.eiFireWarhead, [ATarget.ToRParam(ATarget.Make(other))])
	check(not other.HasUnitProperty(C.upInvisible), "links never apply at fire")
	c.DeferFree()
	_manager.Idle()  # frees the component, which asks to remove the groups
	check(golem.HasUnitProperty(C.upInvisible), "group removal deferred")
	_manager.Idle()
	check(not golem.HasUnitProperty(C.upInvisible), "removed with the link")


func test_link_constraint_and_replace() -> void:
	_setup()
	var golem := _golem(2)
	if golem == null:
		return
	var link := _unit(1)
	link.Blackboard.SetValue(C.eiLinkDest, [], ATarget.Make(golem))
	TWelaTargetConstraintAlliesComponent.new().CreateGrouped(link, [1])
	var blocked: TWarheadLinkApplyScriptComponent = TWarheadLinkApplyScriptComponent.new().CreateGrouped(link, [1], "Links\\Invisible.dws")
	link.Eventbus.Trigger(C.eiAfterCreate)
	check(not golem.HasUnitProperty(C.upInvisible), "an enemy fails the constraint of its group")
	check(blocked.FSavedScriptGroup.is_empty(), "nothing saved")
	blocked.Free()
	var c: TWarheadLinkApplyScriptComponent = TWarheadLinkApplyScriptComponent.new().CreateGrouped(link, [], "Links\\Invisible.dws")
	c.OnAfterCreate()
	check(golem.HasUnitProperty(C.upInvisible), "applied")
	var old_id := golem.ID
	var new_id := _manager.GenerateUniqueID()
	_bus.Trigger(C.eiReplaceEntity, [old_id, new_id, true])
	_manager.Idle()
	check(not golem.HasUnitProperty(C.upInvisible), "replaced as the same entity: script removed")
