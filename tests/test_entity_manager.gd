extends "res://tests/test_case.gd"
## TEntityManagerComponent (BaseConflict.EntityComponents.Shared.pas:1282): registry, deferred freeing, lookups,
## nexus queries.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent


## Records its destruction.
class Tracked:
	extends TEntityComponent
	var Freed := false

	func Destroy() -> void:
		Freed = true
		super()


## Answers eiEnumerateNexus like the nexus entities do: adds its owner to the list.
class NexusMarker:
	extends TEntityComponent

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnEnumerateNexus", C.eiEnumerateNexus, C.epMiddle, C.etRead, C.esGlobal))

	func OnEnumerateNexus(Previous):
		var List: Array = Previous if Previous is Array else []
		List.append(Owner)
		return List


## Stands in for Game.Map.BuildZones.
class FakeBuildZones:
	extends RefCounted
	var Log: Array = []

	func UpdateEntityIDInBuildZones(OldID: int, NewID: int) -> void:
		Log.append([OldID, NewID])


class FakeMap:
	extends RefCounted
	var BuildZones := FakeBuildZones.new()


class FakeGame:
	extends RefCounted
	var Map := FakeMap.new()


func _setup() -> void:
	_bus = TEventbus.new().Create(null)
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)


func after_each() -> void:
	_game_entity.Free()  # frees the manager, which frees every registered entity
	_bus.Game = null
	_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	super()


func _deployed(team: int = 0, pos := Vector2.ZERO, props: Array = []) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Position = pos
	e.Deploy()
	return e


func test_ids_and_registry() -> void:
	_setup()
	var a := _deployed()
	var b := _deployed()
	check_eq(a.ID, 2, "first ID is 2 (1 = game entity)")
	check_eq(b.ID, 3, "IDs count up")
	check_eq(_manager.DeployedEntityCount, 2, "eiNewEntity registers")
	check(_manager.GetEntityByID(3) == b, "lookup by ID")
	check(_manager.TryGetEntityByID(99) == null, "unknown ID")
	check(_manager.HasEntityByID(2), "HasEntityByID")
	check_eq(_manager.GetDeployedEntityList().size(), 2, "deployed list")


func test_uid() -> void:
	_setup()
	var a := _deployed()
	a.FUID = "abc"
	check(_manager.GetEntityByUID("abc") == a, "by UID")
	check(_manager.GetEntityByUID("") == null, "empty UID finds nothing")


func test_kill_entity_is_deferred() -> void:
	_setup()
	var a := _deployed()
	var t: Tracked = Tracked.new().Create(a)
	_bus.Trigger(C.eiKillEntity, [a.ID])
	check(not _manager.HasEntityByID(a.ID), "unregistered at once")
	check(not t.Freed, "freed only at the next Idle")
	_manager.Idle()
	check(t.Freed, "freed at Idle")


func test_free_entity_once() -> void:
	_setup()
	var a := _deployed()
	_manager.FreeEntity(a)
	_manager.FreeEntity(a)
	check_eq(_manager.FEntitiesToFree.size(), 1, "FreeEntity ignores duplicates")
	_manager.Idle()
	check_eq(_manager.DeployedEntityCount, 0, "removed at Idle")


func test_free_component_and_group() -> void:
	_setup()
	var a := _deployed()
	var keep: Tracked = Tracked.new().Create(a)
	var single: Tracked = Tracked.new().Create(a)
	var group := a.ReserveFreeGroup()
	var grouped: Tracked = Tracked.new().CreateGrouped(a, [group])
	_bus.Trigger(C.eiRemoveComponent, [a.ID, single.UniqueID])
	_bus.Trigger(C.eiRemoveComponentGroup, [a.ID, [group]])
	check(not single.Freed and not grouped.Freed, "deferred")
	_manager.Idle()
	check(single.Freed, "component freed")
	check(grouped.Freed, "group freed")
	check(not keep.Freed, "others stay")


func test_replace_entity() -> void:
	_setup()
	var a := _deployed()
	var old_id := a.ID
	var t: Tracked = Tracked.new().Create(a)
	_manager.FreeComponent(t)
	_bus.Trigger(C.eiReplaceEntity, [old_id, 50, true])
	check_eq(a.ID, 50, "entity gets the new ID")
	check(_manager.GetEntityByID(50) == a and not _manager.HasEntityByID(old_id), "re-keyed")
	check_eq(_bus.Game.Map.BuildZones.Log, [[old_id, 50]], "build zones updated")
	_manager.Idle()
	check(t.Freed, "pending component kill follows the new ID")


func test_count_and_filter_by_unit_property() -> void:
	_setup()
	_deployed(1, Vector2.ZERO, DSet.Make([C.upUnit, C.upGround]))
	_deployed(2, Vector2.ZERO, DSet.Make([C.upUnit]))
	_deployed(2, Vector2.ZERO, DSet.Make([C.upBuilding]))
	check_eq(_manager.EntityCountByUnitProperty([C.upUnit]), 2, "all with upUnit")
	check_eq(_manager.EntityCountByUnitProperty(DSet.Make([C.upUnit, C.upGround])), 1, "must have all")
	check_eq(_manager.EntityCountByUnitProperty([C.upUnit], C.tcEnemies, 1), 1, "enemies of team 1")
	check_eq(_manager.EntityCountByUnitProperty([C.upUnit], C.tcAllies, 1), 1, "allies of team 1")
	check_eq(_manager.FilterEntities([C.upUnit], [C.upGround]).size(), 1, "has any of, has none of")
	check_eq(_manager.FilterEntities([], [C.upBuilding]).size(), 2, "empty MustHave takes all")


func test_owning_commander() -> void:
	_setup()
	var commander := _deployed()
	var unit := _deployed()
	unit.Blackboard.SetValue(C.eiOwnerCommander, [], commander.ID)
	check(_manager.TryGetOwningCommander(unit) == commander, "via eiOwnerCommander")


## NexusNext / NexusNextEnemy keep the farthest nexus: `bestDistance < distance` in the original.
func test_nexus_queries() -> void:
	_setup()
	var n1 := _deployed(1, Vector2(0, 0))
	var n2 := _deployed(2, Vector2(10, 0))
	var n3 := _deployed(3, Vector2(100, 0))
	for n in [n1, n2, n3]:
		NexusMarker.new().Create(n)
	check_eq(_manager.NexusList().size(), 3, "enumerated")
	check(_manager.NexusByTeamID(2) == n2, "by team")
	check(_manager.NexusByTeamID(4) == null, "no nexus of that team")
	check(_manager.NexusNext(Vector2(1, 0)) == n3, "farthest, as in the original")
	check(_manager.NexusNextEnemy(Vector2(1, 0), 3) == n2, "farthest enemy")
	check(_manager.TryGetNexusNextEnemy(n1) == n3, "overload with a reference entity")
