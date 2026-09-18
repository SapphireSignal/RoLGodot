extends "res://tests/test_case.gd"
## TDynamicZone*EmitterComponent (BaseConflict.EntityComponents.Shared.pas:2226-2297) and
## TGameEventEnumeratorComponent (:2455). Both answer global reads.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _free: Array = []


func after_each() -> void:
	for o in _free:
		o.Free()
	_free.clear()


func _bus() -> TEventbus:
	var bus := TEventbus.new().Create(null)
	_free.append(bus)
	return bus


func _entity(bus: TEventbus, team: int, pos: Vector2) -> TEntity:
	var e := TEntity.new().Create(bus)
	_free.push_front(e)
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Position = pos
	return e


## A radial emitter (group 3, range) on a new entity of that team, like Nexus.ets / Lanetower.ets.
func _radial(bus: TEventbus, team: int, pos: Vector2, range_: float, zones: Array) -> TDynamicZoneRadialEmitterComponent:
	var e := _entity(bus, team, pos)
	e.Blackboard.SetValue(C.eiWelaRange, [3], range_)
	return TDynamicZoneRadialEmitterComponent.new().CreateGrouped(e, [3]).SetZone(zones)


func _in_zone(bus: TEventbus, pos: Vector2, team: int, zones: Array):
	return bus.Read(C.eiInDynamicZone, [pos, team, zones])


func test_radial() -> void:
	var bus := _bus()
	_radial(bus, 1, Vector2(10, 10), 5.0, [C.dzDrop, C.dzNexus])
	check_eq(_in_zone(bus, Vector2(13, 14), 1, [C.dzDrop]), true, "distance 5 <= range 5")
	check_eq(_in_zone(bus, Vector2(13, 14.1), 1, [C.dzDrop]), null, "outside: drNone keeps Previous (empty)")
	check_eq(_in_zone(bus, Vector2(10, 10), 2, [C.dzDrop]), null, "other team")
	check_eq(_in_zone(bus, Vector2(10, 10), -1, [C.dzDrop]), true, "TeamID -1: any team")
	check_eq(_in_zone(bus, Vector2(10, 10), 1, [C.dzNexus]), true, "second zone of the set")


func test_zone_must_intersect() -> void:
	var bus := _bus()
	_radial(bus, 1, Vector2.ZERO, 5.0, [C.dzDrop])
	check_eq(_in_zone(bus, Vector2.ZERO, 1, [C.dzNexus]), null, "no common zone")


## Exclude turns drTrue into drFalse, and once false nothing turns it true again.
func test_exclude_wins() -> void:
	var bus := _bus()
	_radial(bus, 1, Vector2.ZERO, 5.0, [C.dzDrop]).Exclude()
	_radial(bus, 1, Vector2.ZERO, 50.0, [C.dzDrop])
	check_eq(_in_zone(bus, Vector2(1, 0), 1, [C.dzDrop]), false, "excluded first, the later true is ignored")
	check_eq(_in_zone(bus, Vector2(20, 0), 1, [C.dzDrop]), true, "outside the exclusion")


## Axis: default normal (0, 1) at (0, -3); SetPosition normalizes the position as in the original.
func test_axis() -> void:
	var bus := _bus()
	var e := _entity(bus, 1, Vector2.ZERO)
	var axis: TDynamicZoneAxisEmitterComponent = TDynamicZoneAxisEmitterComponent.new().CreateGrouped(e, []).SetZone([C.dzDrop])
	check_eq(_in_zone(bus, Vector2(0, 0), 5, [C.dzDrop]), true, "in front of (0, -3)")
	check_eq(_in_zone(bus, Vector2(0, -3), 5, [C.dzDrop]), true, "on the point: zero direction, dot 0")
	check_eq(_in_zone(bus, Vector2(0, -5), 5, [C.dzDrop]), null, "behind")
	axis.SetPosition(4, 0).SetNormal(2, 0)
	check_eq(axis.FPosition, Vector2(1, 0), "position normalized")
	check_eq(_in_zone(bus, Vector2(1.5, -9), 5, [C.dzDrop]), true, "x >= 1")
	check_eq(_in_zone(bus, Vector2(0.5, 9), 5, [C.dzDrop]), null, "x < 1")


func test_game_event_enumerator() -> void:
	var bus := _bus()
	var a := _entity(bus, 1, Vector2.ZERO)
	var b := _entity(bus, 1, Vector2.ZERO)
	TGameEventEnumeratorComponent.new().CreateGrouped(a, [3]).Event("Other").Event("GolemTower_Destroyed")
	TGameEventEnumeratorComponent.new().CreateGrouped(b, [3]).Event("GolemTower_Destroyed")
	var r = bus.Read(C.eiGameEvent, ["GolemTower_Destroyed"])
	check(r is Array and r.size() == 2 and r[0] == a and r[1] == b, "both owners, in subscription order")
	r = bus.Read(C.eiGameEvent, ["Other"])
	check(r is Array and r.size() == 1 and r[0] == a, "only a")
	check_eq(bus.Read(C.eiGameEvent, ["Nothing"]), null, "nobody: empty")
