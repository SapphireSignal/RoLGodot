extends "res://tests/test_case.gd"
## The spotty warheads TWarhead{,Spotty,SpottyHealth,SpottyDamage,SpottyHeal,SpottyKill,SpottyRemoveBuff,
## SpottyResource,SpottyWelaStop}Component (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:29-215,
## implementations :303-1229), and the real server SmallMeleeGolem hitting another one through its
## TWelaEffectInstantComponent (Scripts\Units\Colorless\SmallMeleeGolem.ets: damage 10 melee, light armor 0.85,
## health 68). The game has the real entity manager; the owner (team 1) fires warheads of group 1.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent
var _owner: TEntity
var _probe: WarheadProbe


class FakeMap:
	extends RefCounted
	var MapBoundaries := Rect2(-150, -150, 300, 300)
	var Lanes := TLaneManager.new().Create()

	func ClampToZone(_Zone: String, Position: Vector2) -> Vector2:
		return Position


class FakeGame:
	extends RefCounted
	var Statistics := TGameStatisticManager.new().Create()
	var Commanders: Array = []
	var InGameStatus: int = BC.gsLoading
	var Map := FakeMap.new()
	var EntityManager = null
	var ServerEntityManager = null
	var CollisionManager = null

	func IsShuttingDown() -> bool:
		return false

	func IsSandbox() -> bool:
		return false

	func League() -> int:
		return 1


## Records [name, parameters..., called-to group] of the events the warheads send.
class WarheadProbe:
	extends TGDEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnHealDone", C.eiHealDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnKillDone", C.eiKillDone, C.epFirst, C.etTrigger))
		e.append(XEvent("OnKill", C.eiKill, C.epFirst, C.etTrigger))
		e.append(XEvent("OnSacrifice", C.eiSacrifice, C.epFirst, C.etTrigger))
		e.append(XEvent("OnExiled", C.eiExiled, C.epFirst, C.etWrite))
		e.append(XEvent("OnRemoveBuffs", C.eiRemoveBuffs, C.epFirst, C.etTrigger))
		e.append(XEvent("OnWelaStop", C.eiWelaStop, C.epFirst, C.etTrigger))
		e.append(XEvent("OnTransaction", C.eiResourceTransaction, C.epFirst, C.etTrigger))
		e.append(XEvent("OnCapTransaction", C.eiResourceCapTransaction, C.epFirst, C.etTrigger))
		e.append(XEvent("OnReset", C.eiResourceReset, C.epFirst, C.etTrigger))
		e.append(XEvent("OnWriteBalance", C.eiResourceBalance, C.epFirst, C.etWrite))
		e.append(XEvent("OnWriteCap", C.eiResourceCap, C.epFirst, C.etWrite))
		e.append(XEvent("OnWriteCost", C.eiResourceCost, C.epFirst, C.etWrite))
		e.append(XEvent("OnDelayedKill", C.eiDelayedKillEntity, C.epFirst, C.etTrigger, C.esGlobal))

	func _group() -> Array:
		return TEventbus.GetCurrentEvent_CalledToGroup().duplicate()

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func OnDamageDone(Amount, DamageType, Target) -> bool:
		Log.append(["DamageDone", Amount, DamageType, Target.ID])
		return true

	func OnHealDone(Amount, DamageType, Target) -> bool:
		Log.append(["HealDone", Amount, DamageType, Target.ID])
		return true

	func OnKillDone(EntityID) -> bool:
		Log.append(["KillDone", EntityID, _group()])
		return true

	func OnKill(KillerID, KillerCommanderID) -> bool:
		Log.append(["Kill", KillerID, KillerCommanderID])
		return true

	func OnSacrifice(KillerID, KillerCommanderID) -> bool:
		Log.append(["Sacrifice", KillerID, KillerCommanderID])
		return true

	func OnExiled(Exiled) -> bool:
		Log.append(["Exiled", Exiled])
		return true

	func OnRemoveBuffs(MustHaveAny, MustNotHave) -> bool:
		Log.append(["RemoveBuffs", MustHaveAny, MustNotHave])
		return true

	func OnWelaStop() -> bool:
		Log.append(["WelaStop"])
		return true

	func OnTransaction(Res, Amount) -> bool:
		Log.append(["Transaction", Res, Amount, _group()])
		return true

	func OnCapTransaction(Res, Amount, DontFill) -> bool:
		Log.append(["CapTransaction", Res, Amount, DontFill, _group()])
		return true

	func OnReset(Res) -> bool:
		Log.append(["Reset", Res, _group()])
		return true

	func OnWriteBalance(Res, Amount) -> bool:
		Log.append(["WriteBalance", Res, Amount, _group()])
		return true

	func OnWriteCap(Res, Amount) -> bool:
		Log.append(["WriteCap", Res, Amount, _group()])
		return true

	func OnWriteCost(Res, Amount) -> bool:
		Log.append(["WriteCost", Res, Amount, _group()])
		return true

	func OnDelayedKill(EntityID) -> bool:
		Log.append(["DelayedKill", EntityID])
		return true


## Doubles the owner's damage through eiWillDealDamage (like a life-leech or crit modifier would read it).
class DoubleDamage:
	extends TGDEntityComponent

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnWillDealDamage", C.eiWillDealDamage, C.epMiddle, C.etRead))

	func OnWillDealDamage(Amount, _DamageTypes, _Target, _Previous):
		return RParam.ToSingle(RParam.AsSingle(Amount) * 2)


func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TServerEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_bus.Game.ServerEntityManager = _manager
	_bus.Game.CollisionManager = TServerCollisionManagerComponent.new().Create(_game_entity)
	_owner = _unit(1)
	_owner.Blackboard.SetValue(C.eiWelaDamage, [1], 10.0)
	_owner.Blackboard.SetValue(C.eiDamageType, [1], [C.dtMelee])
	_probe = WarheadProbe.new().CreateGroupedAll(_owner)


func after_each() -> void:
	if _game_entity != null:
		_bus.Game.CollisionManager = null
		_bus.Game.ServerEntityManager = null
		_game_entity.Free()  # frees the manager and every deployed entity
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	_owner = null
	_probe = null
	TEntity.SetLastScriptError("")
	super()


## A unit with THealthComponent (health / cap as given) and a probe; deployed.
func _unit(team: int, health: float = 68.0, max_health: float = 68.0) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reHealth, max_health)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, health)
	THealthComponent.new().Create(e)
	e.Deploy()
	return e


func _target(health: float = 68.0, max_health: float = 68.0) -> Array:
	var e := _unit(2, health, max_health)
	return [e, WarheadProbe.new().CreateGroupedAll(e)]


func _hit(targets: Array, group: Array = [1]) -> void:
	var list: Array = []
	for t in targets:
		list.append(RTarget.Create(t))
	_owner.Eventbus.Trigger(C.eiFireWarhead, [list], group)


func _health(e: TEntity) -> float:
	return RParam.AsSingle(e.Balance(C.reHealth))


# --- damage / heal (:588-640) ---

func test_damage() -> void:
	_setup()
	var t: TEntity = _target()[0]
	TWarheadSpottyDamageComponent.new().CreateGrouped(_owner, [1])
	_hit([t, Vector2(5, 5)], [1])
	check_eq(_health(t), 58.0, "68 - eiWelaDamage 10; ground targets are skipped")
	check_eq(_probe.Named("DamageDone"), [[10.0, [C.dtMelee], t.ID]], "eiDamageDone [dealt, damage type, target] on the owner")
	check_eq(_probe.Named("KillDone"), [], "still alive")
	_hit([t], [2])
	check_eq(_health(t), 58.0, "a warhead in another group does not fire")


func test_damage_modifiers() -> void:
	_setup()
	var t: TEntity = _target()[0]
	TWarheadSpottyDamageComponent.new().CreateGrouped(_owner, [1])
	_owner.Blackboard.SetValue(C.eiWelaModifier, [1], 1.5)
	_hit([t])
	check_eq(_health(t), 53.0, "× eiWelaModifier 1.5")
	DoubleDamage.new().Create(_owner)
	_hit([t])
	check_eq(_health(t), 23.0, "eiWillDealDamage replaces the amount: 2 × 15")


func test_damage_percentage() -> void:
	_setup()
	var t: TEntity = _target(40.0, 80.0)[0]
	_owner.Blackboard.SetValue(C.eiWelaDamage, [1], 0.25)
	_owner.Blackboard.SetValue(C.eiWelaDamage, [2], 0.25)
	TWarheadSpottyDamageComponent.new().CreateGrouped(_owner, [1]).PercentageOfMaxHealth()
	TWarheadSpottyDamageComponent.new().CreateGrouped(_owner, [2]).PercentageOfCurrentHealth()
	_hit([t], [1])
	check_eq(_health(t), 20.0, "0.25 × cap 80")
	_hit([t], [2])
	check_eq(_health(t), 15.0, "0.25 × current 20")


func test_damage_kill_done() -> void:
	_setup()
	var t: TEntity = _target(5.0)[0]
	TWarheadSpottyDamageComponent.new().CreateGrouped(_owner, [1])
	_hit([t])
	check_eq(_probe.Named("DamageDone"), [[5.0, [C.dtMelee], t.ID]], "dealt: the remaining health")
	check_eq(_probe.Named("KillDone"), [[t.ID, [1]]], "dead: eiKillDone [target] in its group")


func test_heal() -> void:
	_setup()
	var t: TEntity = _target(50.0)[0]
	t.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reOverheal, 136.0)
	_owner.Blackboard.SetValue(C.eiDamageType, [1], [C.dtOverheal])
	TWarheadSpottyHealComponent.new().CreateGrouped(_owner, [1])
	_hit([t])
	check_eq(_health(t), 60.0, "healed eiWelaDamage 10")
	check_eq(_probe.Named("HealDone"), [[10.0, [C.dtOverheal], t.ID]], "eiHealDone [healed, damage type, target]")
	_hit([t])
	check_eq(_health(t), 68.0, "up to the cap")
	check_eq(RParam.AsSingle(t.Balance(C.reOverheal)), 2.0, "dtOverheal: the rest as overheal")
	var full: TEntity = _target(68.0)[0]
	_owner.Blackboard.SetValue(C.eiDamageType, [1], [])
	_hit([full])
	check_eq(_probe.Named("HealDone").size(), 2, "nothing healed: no eiHealDone")


func test_redirect_to_self() -> void:
	_setup()
	var t: TEntity = _target()[0]
	TWarheadSpottyDamageComponent.new().CreateGrouped(_owner, [1]).RedirectToSelf()
	_hit([t])
	check_eq(_health(t), 68.0, "the target is spared")
	check_eq(_health(_owner), 58.0, "the owner is hit")


# --- kill (:328), remove buff (:1068), wela stop (:1226) ---

func test_kill() -> void:
	_setup()
	_owner.Blackboard.SetValue(C.eiOwnerCommander, [], 77)
	var pair := _target()
	var t: TEntity = pair[0]
	TWarheadSpottyKillComponent.new().CreateGrouped(_owner, [1])
	_hit([t])
	check_eq(pair[1].Named("Kill"), [[_owner.ID, 77]], "eiKill [owner, owner's commander]")
	check_eq(RParam.AsBoolean(t.Eventbus.Read(C.eiIsAlive, [])), false, "dead")
	check_eq(_probe.Named("KillDone"), [[t.ID, [1]]], "eiKillDone")


func test_kill_variants() -> void:
	_setup()
	var a := _target()
	var b := _target()
	TWarheadSpottyKillComponent.new().CreateGrouped(_owner, [1]).Remove()
	TWarheadSpottyKillComponent.new().CreateGrouped(_owner, [2]).Exile().Sacrifice()
	_hit([a[0]], [1])
	check_eq(_probe.Named("DelayedKill"), [[a[0].ID]], "Remove: global eiDelayedKillEntity")
	check_eq(a[1].Named("Kill"), [], "and no death")
	_hit([b[0]], [2])
	var names: Array = []
	for entry in b[1].Log:
		if entry[0] != "DelayedKill":  # global: a's removal and b's death
			names.append(entry[0])
	check_eq(names.slice(0, 3), ["Exiled", "Sacrifice", "Kill"], "Exile, then Sacrifice, then Kill")


func test_remove_buff_and_wela_stop() -> void:
	_setup()
	var pair := _target()
	TWarheadSpottyRemoveBuffComponent.new().CreateGrouped(_owner, [1]).All().MustNotHave([C.btState])
	TWarheadSpottyRemoveBuffComponent.new().CreateGrouped(_owner, [2]).MustHaveAny([C.btNegative, C.btPositive])
	TWarheadSpottyWelaStopComponent.new().CreateGrouped(_owner, [3])
	_hit([pair[0]], [1])
	_hit([pair[0]], [2])
	_hit([pair[0]], [3])
	check_eq(pair[1].Named("RemoveBuffs"), [[BC.ALL_BUFF_TYPES, [C.btState]], [[C.btPositive, C.btNegative], []]], "eiRemoveBuffs [must have any, must not have]")
	check_eq(pair[1].Named("WelaStop"), [[]], "eiWelaStop")


# --- resource (:383-470) ---

func test_resource_default_gold_from_damage() -> void:
	_setup()
	var pair := _target()
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [1])
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [2]).SetResourceType(C.reCharge).SetFactor(0.25).TargetGroup([4])
	_owner.Blackboard.SetValue(C.eiWelaDamage, [2], 10.0)
	_hit([pair[0]], [1])
	_hit([pair[0]], [2])
	check_eq(pair[1].Named("Transaction"), [[C.reGold, 10.0, []], [C.reCharge, 2, [4]]], "gold 10.0; charge Round(10 × 0.25) = 2 (banker's)")
	check_eq(typeof(pair[1].Named("Transaction")[1][1]), TYPE_INT, "int resource: an int")


func test_resource_sources_and_percentage() -> void:
	_setup()
	var pair := _target()
	var t: TEntity = pair[0]
	t.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reCharge, 7)
	_owner.Blackboard.SetIndexedValue(C.eiResourceCost, [], C.reWood, 3.0)
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [1]).SetResourceSource(C.eiNone).SetResourceType(C.reCharge)
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [2]).SetResourceSource(C.eiResourceCost).SetResourceType(C.reWood)
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [3]).SetResourceSource(C.eiNone).SetResourceType(C.reCharge).AmountIsPercentage().SetFactor(0.5)
	_hit([t], [1])
	_hit([t], [2])
	_hit([t], [3])
	check_eq(pair[1].Named("Transaction"), [[C.reCharge, 1, []], [C.reWood, 3.0, []], [C.reCharge, 4, []]], "eiNone: 1; the owner's cost; 50 % of cap 7 = Round(3.5) = 4")


func test_resource_set_reset_max_cost() -> void:
	_setup()
	var pair := _target()
	var t: TEntity = pair[0]
	t.Blackboard.SetIndexedValue(C.eiResourceCost, [5], C.reGold, 20.0)
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [1]).SetsResourceToValue()
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [2]).ResetResource()
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [3]).ChangesMax().DontFillCap()
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [4]).ChangesMax().SetsResourceToValue()
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [5]).ChangesCost().TargetGroup([5])
	for g in [1, 2, 3, 4, 5]:
		_owner.Blackboard.SetValue(C.eiWelaDamage, [g], 10.0)
		_hit([t], [g])
	var log: Array = []
	for entry in pair[1].Log:
		if entry[0] != "WriteCap" or entry[1] == C.reGold:  # skip the health component's overheal cap writes
			log.append(entry)
	# the resource manager's own writes follow its transactions (marked "manager")
	check_eq(log, [
		["WriteBalance", C.reGold, 0.0, []], ["Transaction", C.reGold, 10.0, []],
		["WriteBalance", C.reGold, 10.0, []],  # manager
		["Reset", C.reGold, []],
		["CapTransaction", C.reGold, 10.0, true, []],
		["WriteCap", C.reGold, 10.0, []], ["WriteBalance", C.reGold, 10.0, []],  # manager
		["WriteCap", C.reGold, 10.0, []],
		["WriteBalance", C.reGold, 10.0, []],  # manager
		["WriteCost", C.reGold, 30.0, [5]],
	], "set: balance 0 then add; reset; cap add / set; cost 20 + 10")


func test_resource_owning_commander_and_beacon() -> void:
	_setup()
	var pair := _target()
	var commander: TEntity = _unit(2)
	var commander_probe: WarheadProbe = WarheadProbe.new().CreateGroupedAll(commander)
	pair[0].Blackboard.SetValue(C.eiOwnerCommander, [], commander.ID)
	TWelaHelperBeaconComponent.new().CreateGrouped(commander, [6]).TriggerAt([C.upGolem])
	TWarheadSpottyResourceComponent.new().CreateGrouped(_owner, [1]).TargetsOwningCommander().TargetGroup([2]).SearchForWelaBeacon([C.upGolem])
	var orphan: Array = _target()
	_hit([pair[0], orphan[0]])
	check_eq(pair[1].Named("Transaction"), [], "not the target")
	check_eq(commander_probe.Named("Transaction"), [[C.reGold, 10.0, [2, 6]]], "its commander, target group + beacon group")
	check_eq(orphan[1].Named("Transaction"), [], "no commander: skipped")


# --- real script (SmallMeleeGolem.ets) ---

## Golem 1 fires its group 1 wela at golem 2: TWelaEffectInstantComponent -> eiFireWarhead ->
## TWarheadSpottyDamageComponent: 10 melee damage, light armor 0.85 -> 8.5.
func test_real_golem_hits_golem() -> void:
	_setup()
	var golems: Array = []
	for i in 2:
		var team: int = i + 1
		var init := func(x):
			x.ID = _manager.GenerateUniqueID()
			x.Blackboard.SetValue(C.eiTeamID, [], team)
			x.Position = Vector2(2.0 * team, 10)
		var g := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus, init)
		check(g != null, "created: " + TEntity.GetLastScriptError())
		if g == null:
			return
		g.Deploy()
		golems.append(g)
	var attacker: TEntity = golems[0]
	var victim: TEntity = golems[1]
	var probe: WarheadProbe = WarheadProbe.new().CreateGroupedAll(attacker)
	check_eq(attacker.Eventbus.Read(C.eiEfficiency, [victim], [1]), 1.0, "the instant effect rates the victim 1")
	attacker.Eventbus.Trigger(C.eiFire, [[RTarget.Create(victim)]], [1])
	check_eq(_health(victim), 59.5, "68 - 0.85 × 10")
	check_eq(probe.Named("DamageDone"), [[8.5, [C.dtMelee], victim.ID]], "eiDamageDone with the armored amount")
	victim.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, 4.0)
	attacker.Eventbus.Trigger(C.eiFire, [[RTarget.Create(victim)]], [1])
	check_eq(probe.Named("KillDone"), [[victim.ID, [1]]], "the killing blow: eiKillDone in group 1")
	check_eq(RParam.AsBoolean(victim.Eventbus.Read(C.eiIsAlive, [])), false, "the victim is dead")
	# TStatisticsUnitComponent (UnitTemplate); both golems belong to commander 0, built without eiAfterCreate
	var stats: TGameStatisticManager = _bus.Game.Statistics
	check_eq(stats.GetCount(0, "wela_spawns_Melee"), 0, "no spawn counts without eiAfterCreate")
	check_eq(stats.GetCount(0, "wela_gain_damage_max"), 17, "the victim took 8.5 + 8.5 in total")
	check_eq(stats.GetCount(0, "global_gain_damage"), 25, "the running sum each hit: round(8.5) = 8, then 17")
	check_eq(stats.GetCount(0, "unit_kills_SmallMeleeGolem"), 1, "the attacker's kill")
	check_eq(stats.GetCount(0, "unit_deaths_SmallMeleeGolem"), 1, "the victim's death")
	check_eq(stats.GetCount(0, "global_kills"), 2, "counted by the killer's UnitKills and the victim's OnDie")
	check_eq(stats.GetCount(0, "global_deaths"), 1, "one death")
