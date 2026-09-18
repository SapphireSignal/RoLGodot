extends "res://tests/test_case.gd"
## TEntityDataCache (BaseConflict.Classes.Shared.pas:27, implementation :465), TWelaEventRedirecter and
## TWelaReadySpawnedComponent (BaseConflict.EntityComponents.Shared.Wela.pas:832, :661; implementation :2210-2316).
## Real server scripts: VoidSkeletonDrop / TyrusDrop / Freeze data, Commander\CommanderMethods AddDrop.
## VoidSkeletonDrop at league 4, level 2 (CardTemplate InitCardData, tier 1): 100.0 gold, 4 charges,
## cooldown ii(..., 4, 2) = 27250; at league 1, level 1: 1 charge, cooldown 37000.

const C = preload("res://src/runtime/dws/dws_const.gd")
const DROP = "Units\\Black\\VoidSkeletonDrop"

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent


class FakeGame:
	extends RefCounted
	var IsShuttingDown := false
	var EntityManager = null


## Stands in for the TCardInfo the game passes to Commander\CommanderMethods.
class FakeCardInfo:
	extends RefCounted
	var Filename := ""
	var League := 1
	var Level := 1
	var SkinID := ""


func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.Game = FakeGame.new()
	_bus.EntityDataCache = TEntityDataCache.new().Create(_bus)
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager


func after_each() -> void:
	if _game_entity != null:
		_game_entity.Free()  # frees the manager and every deployed entity
		_bus.Game = null
		_bus.Free()  # frees the data cache
	_bus = null
	_game_entity = null
	_manager = null
	super()


func _unit() -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Deploy()
	return e


## A wela in group 3 of an entity producing Pattern at a card league / level.
func _wela(Pattern: String, League: int, Level: int) -> TEntity:
	var e := _unit()
	e.Blackboard.SetValue(C.eiWelaUnitPattern, [3], Pattern)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [3], C.reCardLeague, League)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [3], C.reCardLevel, Level)
	return e


func test_cache() -> void:
	_setup()
	var cache: TEntityDataCache = _bus.EntityDataCache
	check_eq(cache.Read(DROP, 4, 2, C.eiCooldown), 27250, "charge cooldown (eventbus read)")
	check_eq(TEntity.LastScriptError, "", "no script error")
	check_eq(cache.Read(DROP, 4, 2, C.eiResourceCap, [], C.reCharge), 4, "charge cap (indexed)")
	check_eq(cache.Read(DROP, 1, 1, C.eiResourceCap, [], C.reCharge), 1, "league 1: its own entity")
	check_eq(cache.Read(DROP, 1, 1, C.eiCooldown), 37000, "league 1 cooldown")
	check(cache.GetEntity(DROP, 4, 2) == cache.GetEntity(DROP, 4, 2), "one entity per file / league / level")
	check(cache.GetEntity(DROP, 4, 2).IsAbstract, "a data entity is abstract")
	check_eq(_manager.GetDeployedEntityCount(), 0, "data entities are not deployed")
	cache.Write(DROP, 4, 2, C.eiCooldown, [1])
	check_eq(cache.Read(DROP, 4, 2, C.eiCooldown), 27250, "cached")
	check_eq(cache.Read(DROP, 4, 2, C.eiCooldown, [], -1, true), 1, "ByPassCache")
	check_eq(cache.Read(DROP, 4, 2, C.eiCooldown), 1, "the bypassed read refreshed the cache")
	check_eq(cache.Read("", 4, 2, C.eiCooldown), null, "no script: empty")


## Spells: CreateData(Entity, 0, 1) on a bare entity; every group but [1] reads group 0.
func test_cache_spell() -> void:
	_setup()
	var cache: TEntityDataCache = _bus.EntityDataCache
	check_eq(cache.Read("Spells\\Black\\Freeze.sps", 1, 1, C.eiWelaUnitPattern, [5]), "Spells\\Black\\Freeze", "group 5 reads 0")
	check_eq(TEntity.LastScriptError, "", "no script error")
	check_eq(cache.Read("Spells\\Black\\Freeze.sps", 1, 1, C.eiWelaUnitPattern, [1]), null, "group 1 stays 1")


func test_redirecter() -> void:
	_setup()
	var e := _wela(DROP, 4, 2)
	e.Blackboard.SetValue(C.eiWelaUnitPattern, [4], "Units\\Colorless\\SmallMeleeGolem")
	TWelaEventRedirecter.new().CreateGrouped(e, [3, 4])
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [3]), 27250, "empty: redirected")
	e.Blackboard.SetValue(C.eiCooldown, [3], 500)
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [3]), 500, "own value wins")
	var cost: Array = RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, [], [3]))
	check_eq(RResourceCost.GetValue(cost, C.reGold), 100.0, "cost of the drop")
	check_eq(e.Eventbus.Read(C.eiWelaDamage, [], [3]), null, "the drop has no damage: empty")
	check_eq(e.Eventbus.Read(C.eiColorIdentity, [], [4]), C.ecColorless, "pattern of the group the read was called to")
	check(absf(RParam.AsSingle(e.Eventbus.Read(C.eiCollisionRadius, [], [4])) - 0.55) < 0.0001, "collision radius of the data entity")
	check_eq(e.Eventbus.Read(C.eiWelaDamage, [], [5]), null, "other groups: not redirected")


## Real script: Commander\CommanderMethods AddDrop builds a commander's drop card (group G, charge group H); the
## redirecter copies the drop's charges and charge cooldown at setup and answers its cost.
func test_real_add_drop() -> void:
	_setup()
	var commander := _unit()
	var info := FakeCardInfo.new()
	info.Filename = DROP
	info.League = 4
	info.Level = 2
	commander.ApplyScript("Commander\\CommanderMethods.dws", "AddDrop", [commander, info, 0])
	check_eq(TEntity.LastScriptError, "", "no script error")
	var group := -1
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == DROP:
			group = g
	check(group >= 0, "card group found")
	if group < 0:
		return
	check_eq(commander.Blackboard.GetIndexedValue(C.eiResourceCap, [group], C.reCharge), 4, "charge cap copied")
	check_eq(commander.Blackboard.GetIndexedValue(C.eiResourceBalance, [group], C.reCharge), 4, "charges copied")
	var cooldown_found := false
	for g in range(0, 64):
		if g != group and commander.Blackboard.GetValue(C.eiCooldown, [g]) == 27250:
			cooldown_found = true
	check(cooldown_found, "charge cooldown copied into the charge group")
	var cost: Array = RParam.AsArray(commander.Eventbus.Read(C.eiResourceCost, [], [group]))
	check_eq(RResourceCost.GetValue(cost, C.reGold), 100.0, "gold cost redirected")
	check_eq(RResourceCost.GetValue(cost, C.reCharge), 1, "charge cost redirected")


## Real script: TyrusDrop is legendary; its data entity checks the owning commander for upHasLegendaryUnit.
func test_ready_spawned_legendary() -> void:
	_setup()
	var commander := _wela("Units\\Black\\TyrusDrop", 1, 1)
	commander.Blackboard.SetValue(C.eiOwnerCommander, [], commander.ID)
	TWelaReadySpawnedComponent.new().CreateGrouped(commander, [3])
	check_eq(commander.Eventbus.Read(C.eiIsReady, [], [3]), true, "no legendary unit yet: ready")
	check_eq(TEntity.LastScriptError, "", "no script error")
	var data := _bus.EntityDataCache.GetEntity("Units\\Black\\TyrusDrop", 1, 1)
	check_eq(data.Eventbus.Read(C.eiOwnerCommander, []), commander.ID, "owner commander written into the data entity")
	commander.Blackboard.SetValue(C.eiUnitProperties, [], [C.upHasLegendaryUnit])
	check_eq(commander.Eventbus.Read(C.eiIsReady, [], [3]), false, "a legendary unit alive: not ready")
	var common := _wela(DROP, 1, 1)
	common.Blackboard.SetValue(C.eiUnitProperties, [], [C.upHasLegendaryUnit])
	TWelaReadySpawnedComponent.new().CreateGrouped(common, [3])
	check_eq(common.Eventbus.Read(C.eiIsReady, [], [3]), true, "a common drop has no such check")
