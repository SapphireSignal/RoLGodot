extends "res://tests/test_case.gd"
## TUnitPropertyComponent (BaseConflict.EntityComponents.Shared.pas:2299-2366).

const C = preload("res://src/runtime/dws/dws_const.gd")
const F = preload("res://tests/component_fakes.gd")

var _free: Array = []
var _buses: Array = []


func after_each() -> void:
	for bus in _buses:
		bus.Game = null
	_buses.clear()
	for o in _free:
		o.Free()
	_free.clear()


func _bus(side: int = C.nsServer) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	_free.append(bus)
	_buses.append(bus)
	return bus


func _entity(bus: TEventbus, id: int = 0) -> TEntity:
	var e := TEntity.new().Create(bus, id)
	_free.push_front(e)
	return e


func _props(e: TEntity, group: Array = []) -> Array:
	return RParam.AsSet(e.Eventbus.Read(C.eiUnitProperties, [], group))


## OnUnitProperties adds the set to the blackboard value; Remove takes it away instead.
func test_add_and_remove() -> void:
	var e := _entity(_bus())
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upUnit, C.upGround])
	TUnitPropertyComponent.new().CreateGrouped(e, [], [C.upInvincible, C.upUntargetable])
	check_eq(_props(e), DSet.Make([C.upUnit, C.upGround, C.upInvincible, C.upUntargetable]), "added")
	TUnitPropertyComponent.new().CreateGrouped(e, [], [C.upGround, C.upInvincible]).Remove()
	check_eq(_props(e), DSet.Make([C.upUnit, C.upUntargetable]), "the later component removes")
	check(e.HasUnitProperty(C.upUntargetable) and not e.HasUnitProperty(C.upInvincible), "HasUnitProperty")


## A grouped component only answers reads to no group or to its own group.
func test_grouped() -> void:
	var e := _entity(_bus())
	TUnitPropertyComponent.new().CreateGrouped(e, [3], [C.upImmobilized])
	check_eq(_props(e), [C.upImmobilized], "ungrouped read reaches it")
	check_eq(_props(e, [3]), [C.upImmobilized], "its group")
	check_eq(_props(e, [4]), [], "other group")


## CreateGrouped triggers eiUnitPropertyChanged [Props, False], Destroy [Props, True]; freeing ends the effect.
func test_changed_events_and_free() -> void:
	var e := _entity(_bus())
	var probe: F.Probe = F.Probe.new().Create(e)
	var comp: TUnitPropertyComponent = TUnitPropertyComponent.new().CreateGrouped(e, [], [C.upSummoningSickness, C.upImmobilized])
	var props := DSet.Make([C.upSummoningSickness, C.upImmobilized])
	check_eq(probe.Log, [["UnitPropertyChanged", props, false]], "on create")
	comp.Free()
	check_eq(probe.Log.back(), ["UnitPropertyChanged", props, true], "on destroy")
	check_eq(_props(e), [], "gone")


## GivePropertyOwner: OnAfterCreate subscribes GetCommanderUnitProperties on the owning commander's bus; the
## unit itself no longer gets the property. Freeing the component drops the remote subscription.
func test_give_property_owner() -> void:
	var bus := _bus()
	var game := F.FakeGame.new()
	bus.Game = game
	var commander := _entity(bus, 5)
	game.EntityManager.Commander = commander
	var unit := _entity(bus, 6)
	var comp: TUnitPropertyComponent = TUnitPropertyComponent.new().CreateGrouped(unit, [], [C.upHasLegendaryUnit]).GivePropertyOwner()
	check_eq(_props(commander), [], "nothing before eiAfterCreate")
	unit.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(_props(commander), [C.upHasLegendaryUnit], "commander has it")
	check_eq(_props(unit), [], "unit does not")
	comp.Free()
	check_eq(_props(commander), [], "removed with the component")


## No Game (assigned(Game) fails) or no commander: nothing is subscribed.
func test_give_property_owner_without_game() -> void:
	var bus := _bus()
	var unit := _entity(bus)
	TUnitPropertyComponent.new().CreateGrouped(unit, [], [C.upHasLegendaryUnit]).GivePropertyOwner()
	unit.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(_props(unit), [], "unit does not get it either")
	bus.Game = F.FakeGame.new()
	unit.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(_props(unit), [], "no commander found")
