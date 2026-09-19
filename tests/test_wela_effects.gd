extends "res://tests/test_case.gd"
## The wela effects TWelaEffect{,Instant,OnlyByChance,Redirecter,PayCost,ActivationAbility,Suicide,
## TriggerSpellCast,RemoveAfterUse,IncreaseResource,GameEvent,Fire,ResetCooldown,RemoveBeacon}Component,
## TWelaEfficiencyEffectComponent and TWelaHelper{Beacon,InitActiveAfterGameStart,ActivateTimer}Component
## (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:253-537, :781-826, implementations :945-3262).
## The game has the real entity manager; the owner (team 1) stands at (1, 2), its wela is group 1. A probe in
## ALLGROUP records the events the effects send, with the groups they were called to.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent
var _owner: TEntity
var _probe: EffectProbe


class FakeGame:
	extends RefCounted
	var InGameStatus: int = BC.gsLoading
	var Map = null

	func IsShuttingDown() -> bool:
		return false

	var EntityManager = null


## Records [name, parameters..., called-to group] of the events around the effects.
class EffectProbe:
	extends TGDEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnFire", C.eiFire, C.epLower, C.etTrigger))
		e.append(XEvent("OnFireWarhead", C.eiFireWarhead, C.epFirst, C.etTrigger))
		e.append(XEvent("OnSubtraction", C.eiResourceSubtraction, C.epFirst, C.etTrigger))
		e.append(XEvent("OnTransaction", C.eiResourceTransaction, C.epFirst, C.etTrigger))
		e.append(XEvent("OnWelaActive", C.eiWelaActive, C.epFirst, C.etWrite))
		e.append(XEvent("OnDie", C.eiDie, C.epFirst, C.etTrigger))
		e.append(XEvent("OnCooldownReset", C.eiWelaCooldownReset, C.epFirst, C.etTrigger))
		e.append(XEvent("OnDelayedKill", C.eiDelayedKillEntity, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnSpellCast", C.eiCommanderAbilityUsed, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnRemoveGroup", C.eiRemoveComponentGroup, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epFirst, C.etTrigger, C.esGlobal))

	func _group() -> Array:
		return TEventbus.GetCurrentEvent_CalledToGroup().duplicate()

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry)
		return Result

	func OnFire(Targets) -> bool:
		Log.append(["Fire", _Describe(Targets), _group()])
		return true

	func OnFireWarhead(Targets) -> bool:
		Log.append(["FireWarhead", _Describe(Targets), _group()])
		return true

	func OnSubtraction(Res, Amount) -> bool:
		Log.append(["Subtraction", Res, Amount, _group()])
		return true

	func OnTransaction(Res, Amount) -> bool:
		Log.append(["Transaction", Res, Amount, _group()])
		return true

	func OnWelaActive(Active) -> bool:
		Log.append(["WelaActive", Active, _group()])
		return true

	func OnDie(KillerID, KillerCommanderID) -> bool:
		Log.append(["Die", KillerID, KillerCommanderID])
		return true

	func OnCooldownReset(Expire) -> bool:
		Log.append(["CooldownReset", Expire, _group()])
		return true

	func OnDelayedKill(EntityID) -> bool:
		Log.append(["DelayedKill", EntityID])
		return true

	func OnSpellCast(TeamID, Targets) -> bool:
		Log.append(["SpellCast", TeamID, _Describe(Targets)])
		return true

	func OnRemoveGroup(EntityID, Groups) -> bool:
		Log.append(["RemoveGroup", EntityID, Groups])
		return true

	func OnGameEvent(Name) -> bool:
		Log.append(["GameEvent", Name])
		return true

	## Entity targets as their IDs, ground targets as their Vector2.
	static func _Describe(Targets) -> Array:
		var Result: Array = []
		for t in ATarget.FromRParam(Targets):
			Result.append(t.EntityID if t.IsEntity() else t.GetTargetPosition(null))
		return Result


## Answers the global eiGameTickTimeToFirstTick like the game's tick component.
class TimeToFirstTick:
	extends TGDEntityComponent
	var Value := 0

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnTimeToFirstTick", C.eiGameTickTimeToFirstTick, C.epFirst, C.etRead, C.esGlobal))

	func OnTimeToFirstTick():
		return Value


## Sees eiDie after the suicide effect's epLow handler.
class DieLastProbe:
	extends TGDEntityComponent
	var Died := false

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))

	func OnDie(_KillerID, _KillerCommanderID) -> bool:
		Died = true
		return true


func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_owner = _unit(1, Vector2(1, 2))
	_probe = EffectProbe.new().CreateGroupedAll(_owner)


func after_each() -> void:
	TTimeManager.SetFakeTime(null)
	TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES.duplicate()
	if _game_entity != null:
		_game_entity.Free()  # frees the manager and every deployed entity
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	_owner = null
	_probe = null
	super()


func _unit(team: int, pos: Vector2, props: Array = []) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Position = pos
	e.Deploy()
	return e


func _fire(targets: Array, group: Array = [1], e: TEntity = null) -> void:
	var list: Array = []
	for t in targets:
		list.append(RTarget.Create(t))
	(e if e != null else _owner).Eventbus.Trigger(C.eiFire, [list], group)


## The logged entries of that name without the name.
func _log(name: String) -> Array:
	var Result: Array = []
	for entry in _probe.Named(name):
		Result.append(entry.slice(1))
	return Result


# --- base, instant, efficiency (:1095-1108, :963-994) ---

func test_instant_fires_warheads_in_its_group() -> void:
	_setup()
	var enemy := _unit(2, Vector2(3, 2))
	TWelaEffectInstantComponent.new().CreateGrouped(_owner, [1])
	_fire([enemy], [1])
	check_eq(_log("FireWarhead"), [[[enemy.ID], [1]]], "eiFireWarhead [targets] in its group")
	_probe.Log.clear()
	_fire([enemy], [])
	check_eq(_log("FireWarhead"), [], "a groupless eiFire is no local call for a grouped effect")
	_fire([enemy], [2])
	check_eq(_log("FireWarhead"), [], "nor a fire to another group")


func test_instant_checks_warhead_target_and_target_group() -> void:
	_setup()
	var ally := _unit(1, Vector2(3, 2))
	var enemy := _unit(2, Vector2(4, 2))
	TWelaEffectInstantComponent.new().CreateGrouped(_owner, [1]).TargetGroup([4, 3])
	TWelaTargetConstraintEnemiesComponent.new().CreateGrouped(_owner, [1]).ConstraintsWarhead()
	_fire([ally], [1])
	check_eq(_log("FireWarhead"), [], "eiWarheadTargetPossible of [1] rules the ally out")
	_fire([enemy], [1])
	check_eq(_log("FireWarhead"), [[[enemy.ID], [3, 4]]], "fired to the target group instead of its own")


func test_instant_efficiency() -> void:
	_setup()
	var enemy := _unit(2, Vector2(3, 2))
	var hidden := _unit(2, Vector2(3, 2), [C.upUntargetable])
	var effect := TWelaEffectInstantComponent.new().CreateGrouped(_owner, [1])
	check_eq(_owner.Eventbus.Read(C.eiEfficiency, [enemy], [1]), 1.0, "1 against a targetable unit")
	check_eq(_owner.Eventbus.Read(C.eiEfficiency, [hidden], [1]), -1.0, "-1 against an untargetable one")
	check_eq(_owner.Eventbus.Read(C.eiEfficiency, [enemy], [2]), null, "other groups: nothing answers")
	_owner.Blackboard.SetValue(C.eiWelaDamage, [1], 12.5)
	TEventbus.SetCurrentEvent_CalledToGroup([1])  # as during an event called to [1]
	check_eq(effect.GetEfficiency([]), 12.5, "GetEfficiency: eiWelaDamage of the called-to group")
	TEventbus.SetCurrentEvent_CalledToGroup([])


func test_efficiency_effect_ignores_previous_and_efficiency_components_add() -> void:
	TTimeManager.SetFakeTime(1000.0)
	_setup()
	var enemy := _unit(2, Vector2(3, 2))
	_owner.Blackboard.SetValue(C.eiEfficiency, [1], 50.0)
	TWelaEfficiencyEffectComponent.new().CreateGrouped(_owner, [1])
	check_eq(_owner.Eventbus.Read(C.eiEfficiency, [enemy], [1]), -1.0, "the abstract effect: -1, the blackboard value is dropped")
	TWelaEfficiencyCreatedComponent.new().CreateGrouped(_owner, [1])
	TTimeManager.SetFakeTime(1005.0)
	check_eq(_owner.Eventbus.Read(C.eiEfficiency, [enemy], [1]), 4.0, "the efficiency components add after it (epMiddle)")


# --- chance (:2803), redirecter (:3162) ---

func test_only_by_chance() -> void:
	_setup()
	TWelaEffectOnlyByChanceComponent.new().CreateGrouped(_owner, [1])
	_owner.Blackboard.SetValue(C.eiWelaChance, [1], 1.0)
	_fire([_owner], [1])
	check_eq(_log("Fire").size(), 1, "chance 1: every fire passes")
	_owner.Blackboard.SetValue(C.eiWelaChance, [1], -1.0)
	_fire([_owner], [1])
	check_eq(_log("Fire").size(), 1, "chance below 0: stopped before epLower")


func test_redirecter_to_ground() -> void:
	_setup()
	var enemy := _unit(2, Vector2(3, 2))
	TWelaEffectRedirecterComponent.new().CreateGrouped(_owner, [1])
	_fire([enemy], [1])
	check_eq(_log("Fire"), [[[enemy.ID], [1]]], "without RedirectToGround the targets stay")
	_probe.Log.clear()
	TWelaEffectRedirecterComponent.new().CreateGrouped(_owner, [1]).RedirectToGround()
	_fire([enemy], [1])
	check_eq(_log("Fire"), [[[Vector2(1, 2)], [1]]], "the later handlers see the ground at the owner")


# --- pay cost (:1949) ---

func _set_cost(e: TEntity, group: Array, res: int, amount) -> void:
	e.Blackboard.SetIndexedValue(C.eiResourceCost, group, res, amount)


func test_pay_cost() -> void:
	_setup()
	_set_cost(_owner, [1], C.reGold, 50.0)
	_set_cost(_owner, [1], C.reLevel, 2)
	_set_cost(_owner, [1], C.reCharge, 1)
	TWelaEffectPayCostComponent.new().CreateGrouped(_owner, [1]).ConvertResource(C.reCharge, C.reMana)
	_fire([], [1])
	check_eq(_log("Subtraction"), [[C.reGold, 50.0, [1]], [C.reCharge, 1, [1]]], "gold and charge paid in its group, level never")
	check_eq(_log("Transaction"), [[C.reMana, 1, [1]]], "the charge refunded as mana")


func test_pay_cost_groups_and_consume_all() -> void:
	_setup()
	_set_cost(_owner, [1], C.reGold, 50.0)
	_set_cost(_owner, [1], C.reWood, 5.0)
	_owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [2], C.reGold, 80.0)
	_owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reWood, 7.0)
	TWelaEffectPayCostComponent.new().CreateGrouped(_owner, [1]).SetPayingGroup([2]).SetPayingGroupForType(C.reWood, []).ConsumesAll()
	_fire([], [1])
	check_eq(_log("Subtraction"), [[C.reGold, 80.0, [2]], [C.reWood, 7.0, []]], "whole balances, in the paying groups")


func test_pay_cost_commander_pays_and_not_payed_resources() -> void:
	_setup()
	var commander := _unit(1, Vector2.ZERO)
	var commander_probe: EffectProbe = EffectProbe.new().CreateGroupedAll(commander)
	_owner.Blackboard.SetValue(C.eiOwnerCommander, [], commander.ID)
	_set_cost(_owner, [1], C.reGold, 50.0)
	_set_cost(_owner, [1], C.reWood, 5.0)
	TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = DSet.Union(TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES, [C.reWood])
	TWelaEffectPayCostComponent.new().CreateGrouped(_owner, [1]).CommanderPays()
	_fire([], [1])
	check_eq(_log("Subtraction"), [], "the owner pays nothing")
	var paid: Array = []
	for entry in commander_probe.Named("Subtraction"):
		paid.append(entry.slice(1))
	check_eq(paid, [[C.reGold, 50.0, []]], "the commander pays groupless, wood is not paid")


# --- activation (:2675), helpers (:2742, :3006) ---

func test_activation_ability_only_on_change() -> void:
	_setup()
	TWelaEffectActivationAbilityComponent.new().CreateGrouped(_owner, [1])
	_fire([], [1])
	check_eq(_log("WelaActive"), [[false, [1]]], "empty counts as active: deactivated")
	_fire([], [1])
	check_eq(_log("WelaActive").size(), 1, "already inactive: no write")
	TWelaEffectActivationAbilityComponent.new().CreateGrouped(_owner, [2]).SetsActive().SetActivationGroup([3])
	_fire([], [2])
	check_eq(_log("WelaActive").size(), 1, "SetsActive on an unset group: nothing changes")
	_owner.Blackboard.SetValue(C.eiWelaActive, [3], false)
	_fire([], [2])
	check_eq(_log("WelaActive")[-1], [true, [3]], "activates the activation group")


func test_activation_ability_conditions() -> void:
	_setup()
	_owner.Blackboard.SetIndexedValue(C.eiResourceCap, [4], C.reCharge, 3)
	_owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [4], C.reCharge, 2)
	TWelaEffectActivationAbilityComponent.new().CreateGrouped(_owner, [1]).TriggerOnReachResourceCap(C.reCharge).SetCheckGroup([4])
	TWelaEffectActivationAbilityComponent.new().CreateGrouped(_owner, [2]).CheckNotFull(C.reCharge).SetCheckGroup([4])
	_fire([], [1])
	check_eq(_log("WelaActive"), [], "not at cap: no deactivation")
	_fire([], [2])
	check_eq(_log("WelaActive"), [[false, [2]]], "CheckNotFull: 2 <> 3")
	_owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [4], C.reCharge, 3)
	_fire([], [1])
	check_eq(_log("WelaActive")[-1], [false, [1]], "at cap: deactivated")
	TWelaEffectActivationAbilityComponent.new().CreateGrouped(_owner, [5]).OnlyAfterGameStart()
	var ticks := TimeToFirstTick.new().Create(_game_entity)
	ticks.Value = 1000
	_fire([], [5])
	check_eq(_log("WelaActive").size(), 2, "before the first game tick: nothing")
	ticks.Value = 0
	_fire([], [5])
	check_eq(_log("WelaActive")[-1], [false, [5]], "after it: deactivated")


func test_helper_init_active_after_game_start() -> void:
	_setup()
	var helper = TWelaHelperInitActiveAfterGameStartComponent.new().CreateGrouped(_owner, [1])
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [1]), false, "before the game: inactive")
	_owner.Blackboard.SetIndexedValue(C.eiResourceCap, [2], C.reCharge, 3)
	_owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [2], C.reCharge, 3)
	TWelaHelperInitActiveAfterGameStartComponent.new().CreateGrouped(_owner, [3]).DisableOnReachResourceCap(C.reCharge, [2])
	_bus.Game.InGameStatus = BC.gsPlaying
	TWelaHelperInitActiveAfterGameStartComponent.new().CreateGrouped(_owner, [4])
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [4]), null, "created while playing: untouched")
	_bus.Trigger(C.eiGameTick, [])
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [1]), true, "first game tick: active")
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [3]), false, "resource at cap: stays inactive")
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [4]), null, "disabled: still untouched")
	check(helper.Owner == null, "freed itself")
	_owner.Blackboard.SetValue(C.eiWelaActive, [1], false)
	_bus.Trigger(C.eiGameTick, [])
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [1]), false, "only once")


func test_helper_activate_timer() -> void:
	_setup()
	TTimeManager.SetFakeTime(1000.0)
	_owner.Blackboard.SetValue(C.eiWelaActive, [1], false)
	var helper = TWelaHelperActivateTimerComponent.new().CreateGrouped(_owner, [1]).Delay(100)
	TTimeManager.SetFakeTime(1099.0)
	_bus.Trigger(C.eiIdle, [])
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [1]), false, "99 ms: not yet")
	TTimeManager.SetFakeTime(1100.0)
	_bus.Trigger(C.eiIdle, [])
	check_eq(_owner.Blackboard.GetValue(C.eiWelaActive, [1]), true, "100 ms: active")
	check(helper.Owner == null, "freed itself")


# --- suicide (:2037), spell cast (:3184), remove after use (:945), resource (:3242), game event (:3131) ---

func test_suicide() -> void:
	_setup()
	var last := DieLastProbe.new().Create(_owner)
	TWelaEffectSuicideComponent.new().CreateGrouped(_owner, [1])
	_fire([], [1])
	check_eq(_log("Die"), [[-1, -1]], "eiDie [-1, -1]")
	check(last.Died, "reaches the later handlers")
	check_eq(_log("DelayedKill"), [[_owner.ID]], "not alive (no health): killed")


func test_suicide_prevent_death() -> void:
	_setup()
	var last := DieLastProbe.new().Create(_owner)
	TWelaEffectSuicideComponent.new().CreateGrouped(_owner, [1]).PreventDeath()
	_owner.Eventbus.Trigger(C.eiDie, [5, 6])
	check(not last.Died, "every eiDie stops at epLow")
	_owner.Blackboard.SetValue(C.eiIsAlive, [], true)
	_fire([], [1])
	check_eq(_log("DelayedKill"), [], "still alive: not killed")


func test_trigger_spell_cast() -> void:
	_setup()
	var enemy := _unit(2, Vector2(3, 2))
	TWelaEffectTriggerSpellCastComponent.new().CreateGrouped(_owner, [1])
	_fire([enemy], [1])
	check_eq(_log("SpellCast"), [[1, [enemy.ID]]], "global eiCommanderAbilityUsed [TeamID, targets]")


func test_remove_after_use() -> void:
	_setup()
	TWelaEffectRemoveAfterUseComponent.new().CreateGrouped(_owner, [1])
	TWelaEffectRemoveAfterUseComponent.new().CreateGrouped(_owner, [2]).TargetGroup([6, 5])
	_fire([], [1])
	_fire([], [2])
	check_eq(_log("RemoveGroup"), [[_owner.ID, [1]], [_owner.ID, [5, 6]]], "its group, or the target group")


func test_increase_resource() -> void:
	_setup()
	TWelaEffectIncreaseResourceComponent.new().CreateGrouped(_owner, [1]).SetResourceType(C.reCharge)
	TWelaEffectIncreaseResourceComponent.new().CreateGrouped(_owner, [2]).SetResourceType(C.reGold)
	_fire([], [1])
	_fire([], [2])
	check_eq(_log("Transaction"), [[C.reCharge, 1, [1]], [C.reGold, 1.0, [2]]], "+1 (int) / +1.0 (float) in its group")
	check_eq(typeof(_log("Transaction")[0][1]), TYPE_INT, "int resource: an int")


func test_game_event() -> void:
	_setup()
	TWelaEffectGameEventComponent.new().CreateGrouped(_owner, [1]).Event("first").Event("second")
	_fire([], [1])
	check_eq(_log("GameEvent"), [["first"], ["second"]], "global eiGameEvent per event, in order")


# --- fire (:2814) ---

func test_fire_in_target_group() -> void:
	_setup()
	var ally := _unit(1, Vector2(3, 2))
	var enemy := _unit(2, Vector2(4, 2))
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [1]).TargetGroup([2])
	TWelaTargetConstraintEnemiesComponent.new().CreateGrouped(_owner, [2])
	_owner.Blackboard.SetValue(C.eiIsReady, [2], false)
	_fire([ally, enemy], [1])
	check_eq(_log("Fire"), [[[ally.ID, enemy.ID], [1]]], "group 2 not ready: nothing fired")
	_probe.Log.clear()
	_owner.Blackboard.SetValue(C.eiIsReady, [2], true)
	_fire([ally, enemy], [1])
	check_eq(_log("Fire").slice(1), [[[enemy.ID], [2]]], "one fire per possible target")


func test_fire_multi_target_group() -> void:
	_setup()
	var enemy := _unit(2, Vector2(4, 2))
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [1]).MultiTargetGroup([2]).MultiTargetGroup([3]).MultiTargetGroup([4])
	_owner.Blackboard.SetValue(C.eiIsReady, [2], false)
	_fire([enemy], [1])
	check_eq(_log("Fire").slice(1), [[[enemy.ID], [3]]], "the first ready group, then stops")


func test_fire_redirects() -> void:
	_setup()
	var enemy := _unit(2, Vector2(4, 2))
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [1]).TargetGroup([2]).RedirectToSelf()
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [3]).TargetGroup([4]).RedirectToGround()
	TWelaTargetConstraintEnemiesComponent.new().CreateGrouped(_owner, [4])
	_fire([enemy], [1])
	check_eq(_log("Fire").slice(1), [[[_owner.ID], [2]]], "RedirectToSelf")
	_probe.Log.clear()
	_fire([enemy], [3])
	check_eq(_log("Fire").slice(1), [[[Vector2(4, 2)], [4]]], "RedirectToGround: at the target, no target checks")
	# a link's source / destination
	var source := _unit(1, Vector2(1, 1))
	var dest := _unit(1, Vector2(2, 2))
	_owner.Blackboard.SetValue(C.eiLinkSource, [], ATarget.ToRParam(ATarget.Make(source)))
	_owner.Blackboard.SetValue(C.eiLinkDest, [], ATarget.ToRParam(ATarget.Make(dest)))
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [5]).TargetGroup([6]).RedirectToLinkSource()
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [7]).TargetGroup([8]).RedirectToLinkDestination()
	_probe.Log.clear()
	_fire([enemy], [5])
	check_eq(_log("Fire").slice(1), [[[source.ID], [6]]], "RedirectToLinkSource")
	_probe.Log.clear()
	_fire([enemy], [7])
	check_eq(_log("Fire").slice(1), [[[dest.ID], [8]]], "RedirectToLinkDestination")


func test_fire_in_creator() -> void:
	_setup()
	var creator := _unit(1, Vector2.ZERO)
	var creator_probe: EffectProbe = EffectProbe.new().CreateGroupedAll(creator)
	var enemy := _unit(2, Vector2(4, 2))
	TWelaEffectFireComponent.new().CreateGrouped(_owner, [1]).FireInCreator().TargetGroup([2])
	_owner.Blackboard.SetValue(C.eiCreator, [1], creator.ID)
	_fire([enemy, _owner], [1])
	check_eq(creator_probe.Named("Fire"), [], "no creator group: never a global fire")
	_owner.Blackboard.SetValue(C.eiCreatorGroup, [1], [7])
	_fire([enemy, _owner], [1])
	check_eq(creator_probe.Named("Fire"), [["Fire", [enemy.ID, _owner.ID], [7]]], "all targets at once in the creator group")
	check_eq(_log("Fire").size(), 2, "nothing fired on the owner itself")


# --- beacons (:2928), reset cooldown (:2945), remove beacon (:2982) ---

func test_beacons() -> void:
	_setup()
	var target := _unit(2, Vector2(4, 2))
	var target_probe: EffectProbe = EffectProbe.new().CreateGroupedAll(target)
	TWelaHelperBeaconComponent.new().CreateGrouped(target, [3]).TriggerAt([C.upGolem, C.upUnit])
	TWelaHelperBeaconComponent.new().CreateGrouped(target, [5]).TriggerAt([C.upUnit])
	check_eq(target.Eventbus.Read(C.eiWelaSearch, [[C.upGolem]]), [3], "eiWelaSearch: the groups whose beacon matches")
	check_eq(target.Eventbus.Read(C.eiWelaSearch, [[C.upUnit]]), [3, 5], "several")
	check_eq(target.Eventbus.Read(C.eiWelaSearch, [[C.upMelee]]), null, "none")
	TWelaEffectResetCooldownComponent.new().CreateGrouped(_owner, [1]).TargetGroup([2]).SearchForWelaBeacon([C.upGolem])
	TWelaEffectResetCooldownComponent.new().CreateGrouped(_owner, [2]).SearchForWelaBeacon([C.upMelee]).Expire()
	TWelaEffectRemoveBeaconComponent.new().CreateGrouped(_owner, [4]).SearchForWelaBeacon([C.upUnit])
	_fire([target, Vector2(9, 9)], [1])
	_fire([target], [2])
	var resets: Array = []
	for entry in target_probe.Named("CooldownReset"):
		resets.append(entry.slice(1))
	check_eq(resets, [[false, [2, 3]]], "target group + the beacon's group; nothing to reset: no event")
	_fire([target], [4])
	check_eq(_log("RemoveGroup"), [[target.ID, [3, 5]]], "RemoveGroups on the target")
