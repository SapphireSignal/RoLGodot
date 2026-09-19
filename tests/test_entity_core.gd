extends "res://tests/test_case.gd"
## Entity core (src/runtime/entity): TEntity, TBlackboard, TEventbus, TEntityComponent. Each expectation is
## derived from BaseConflict.Entity.pas; the method named in the comment is where it comes from.

const C = preload("res://src/runtime/dws/dws_const.gd")


## Logs every event it gets into a shared Array; Stop = false makes its trigger handler stop the event.
class TraceComp extends TGDEntityComponent:
	var trace: Array = []
	var tag := ""
	var stop := false
	var on_stop := Callable()

	func Setup(owner, group: Array, tag_: String, trace_: Array) -> TraceComp:
		tag = tag_
		trace = trace_
		CreateGrouped(owner, group)
		return self

	func _Priority() -> int:
		return C.epMiddle

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnWelaStop", C.eiWelaStop, _Priority(), C.etTrigger))
		e.append(XEvent("OnSpeedWrite", C.eiSpeed, _Priority(), C.etWrite))
		e.append(XEvent("OnSpeedRead", C.eiSpeed, _Priority(), C.etRead))

	func OnWelaStop() -> bool:
		trace.append(tag)
		if on_stop.is_valid():
			on_stop.call(self)
		return not stop

	func OnSpeedWrite(Speed) -> bool:
		trace.append("%s:%s" % [tag, str(Speed)])
		if on_stop.is_valid():
			on_stop.call(self)
		return true

	## Read with the previous result as the last parameter: adds 1 to it.
	func OnSpeedRead(Previous):
		trace.append(tag)
		return RParam.AsInteger(Previous) + 1


class TraceFirst extends TraceComp:
	func _Priority() -> int:
		return C.epFirst


class TraceLast extends TraceComp:
	func _Priority() -> int:
		return C.epLast


## Listens on the global eventbus (XEvent scope esGlobal).
class GlobalListener extends TGDEntityComponent:
	var trace: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnNetworkSend", C.eiNetworkSend, C.epMiddle, C.etTrigger, C.esGlobal))

	func OnNetworkSend(EntityID, Event, Group, ComponentID, Values, Write) -> bool:
		trace.append([EntityID, Event, Group, ComponentID, Values, Write])
		return true


var _worlds: Array = []


func _world(side: int = C.nsServer) -> Array:
	var global_bus := TEventbus.new().Create(null)
	global_bus.ApplicationType = side
	var w := [global_bus, TEntity.new().Create(global_bus, 7)]
	_worlds.append(w)
	return w


## Frees every entity and global bus a test made (skips entities the test already freed).
func after_each() -> void:
	for w in _worlds:
		if w[1].FEventbus.FOwner != null:
			w[1].Free()
		w[0].Free()
	_worlds.clear()


func test_priority_then_subscription_order() -> void:
	# TEventhandler.AddSubscriber inserts before the first subscriber with a greater priority, so equal
	# priorities keep their subscription order
	var e: TEntity = _world()[1]
	var trace := []
	TraceLast.new().Setup(e, [], "A", trace)
	TraceFirst.new().Setup(e, [], "B", trace)
	TraceComp.new().Setup(e, [], "C", trace)
	TraceFirst.new().Setup(e, [], "D", trace)
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["B", "D", "C", "A"], "trigger order")


func test_false_stops_the_event() -> void:
	var e: TEntity = _world()[1]
	var trace := []
	TraceComp.new().Setup(e, [], "A", trace)
	var b := TraceComp.new().Setup(e, [], "B", trace)
	TraceComp.new().Setup(e, [], "C", trace)
	b.stop = true
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["A", "B"], "handlers after the false one are skipped")


func test_group_filter() -> void:
	# TEventbus.Trigger: Group = [] reaches everyone, else the component's group must intersect, or the
	# component is in ALLGROUP
	var e: TEntity = _world()[1]
	var trace := []
	TraceComp.new().Setup(e, [1], "g1", trace)
	TraceComp.new().Setup(e, [2, 3], "g23", trace)
	TraceComp.new().Setup(e, [], "none", trace)
	TraceComp.new().Setup(e, [C.ALLGROUP_INDEX], "all", trace)
	e.Eventbus.Trigger(C.eiWelaStop, [], [3])
	check_eq(trace, ["g23", "all"], "group 3")
	trace.clear()
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["g1", "g23", "none", "all"], "no group")


func test_blackboard_groups() -> void:
	var e: TEntity = _world()[1]
	var bb := e.Blackboard
	bb.SetValue(C.eiSpeed, [], 5)
	bb.SetValue(C.eiSpeed, [4, 1], 9)
	bb.SetValue(C.eiSpeed, [4], 11)
	check_eq(bb.GetValue(C.eiSpeed, []), 5, "no group")
	# GetIndexedValue walks the group members ascending and takes the first non-empty value
	check_eq(bb.GetValue(C.eiSpeed, [4, 1]), 9, "group 1 before 4")
	check_eq(bb.GetValue(C.eiSpeed, [4]), 11, "group 4 overwritten")
	check_eq(bb.GetValue(C.eiSpeed, [2]), null, "empty group is not the global value")
	bb.SetIndexedValue(C.eiResourceCost, [], C.reGold, 300)
	bb.SetIndexedValues(C.eiCardStats, [3], [10, 20])
	check_eq(bb.GetIndexedValue(C.eiResourceCost, [], C.reGold), 300, "indexed")
	check_eq(bb.GetIndexedValue(C.eiResourceCost, [], C.reWood), null, "other index empty")
	check_eq(bb.GetIndexMap(C.eiCardStats, [3]), {0: 10, 1: 20}, "index map")
	bb.DeleteValues([4])
	check_eq(bb.GetValue(C.eiSpeed, [4]), null, "deleted group")
	check_eq(bb.GetValue(C.eiSpeed, [1]), 9, "other group kept")


func test_script_side_blackboard_values() -> void:
	var bb := (_world()[1] as TEntity).Blackboard
	# VarToRParam: a script float becomes a single
	bb.SetValue(C.eiSpeed, [], 0.004)
	check_eq(bb.GetValue(C.eiSpeed, []), RParam.ToSingle(0.004), "float stored as single")
	check(bb.GetValue(C.eiSpeed, []) != 0.004, "single differs from the double")
	# SetValueByteArrayInvoker: eiUnitProperties becomes a set (normalised), others a byte array
	bb.SetValue(C.eiUnitProperties, [], [C.upSpawner, C.upDrop, C.upSpawner])
	check_eq(bb.GetValue(C.eiUnitProperties, []), DSet.Make([C.upDrop, C.upSpawner]), "set")
	bb.SetValue(C.eiWelaNeededGridSize, [], Vector2i(1, 2))
	check_eq(bb.GetValue(C.eiWelaNeededGridSize, []), Vector2i(1, 2), "RIntVector2 overload")


func test_write_read_and_blackboard() -> void:
	var e: TEntity = _world()[1]
	var trace := []
	TraceComp.new().Setup(e, [], "A", trace)
	TraceLast.new().Setup(e, [], "B", trace)
	# Trigger with Write: handlers first, then Values[0] into the blackboard
	e.Eventbus.Write(C.eiSpeed, [3])
	check_eq(trace, ["A:3", "B:3"], "write handlers")
	check_eq(e.Blackboard.GetValue(C.eiSpeed, []), 3, "written value")
	# Read: starts with the blackboard value, each read handler gets the previous result
	trace.clear()
	check_eq(e.Eventbus.Read(C.eiSpeed, []), 5, "3 + 1 + 1")
	check_eq(trace, ["A", "B"], "read order")


func test_var_parameter() -> void:
	# a handler assigning its `var` parameter changes what later handlers and the blackboard see
	var e: TEntity = _world()[1]
	var trace := []
	var a := TraceComp.new().Setup(e, [], "A", trace)
	TraceComp.new().Setup(e, [], "B", trace)
	a.on_stop = func(c): c.SetVarParam(0, 42)
	e.Eventbus.Write(C.eiSpeed, [1])
	check_eq(trace, ["A:1", "B:42"], "later handler sees the new value")
	check_eq(e.Blackboard.GetValue(C.eiSpeed, []), 42, "blackboard gets the new value")


func test_subscribe_during_event() -> void:
	# AddSubscriber during an event: inserted before or at the current position -> enumerator steps over it
	var e: TEntity = _world()[1]
	var trace := []
	var a := TraceComp.new().Setup(e, [], "A", trace)
	var created := []
	a.on_stop = func(c):
		if created.is_empty():
			created.append(TraceFirst.new().Setup(e, [], "early", trace))
			created.append(TraceLast.new().Setup(e, [], "late", trace))
	TraceLast.new().Setup(e, [], "Z", trace)
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["A", "Z", "late"], "only the later one runs in the same event")
	trace.clear()
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["early", "A", "Z", "late"], "next event")


func test_free_during_event() -> void:
	# RemoveSubscriber during an event: removed before or at the current position -> enumerator steps back
	var e: TEntity = _world()[1]
	var trace := []
	var a := TraceComp.new().Setup(e, [], "A", trace)
	var b := TraceComp.new().Setup(e, [], "B", trace)
	TraceComp.new().Setup(e, [], "C", trace)
	a.on_stop = func(_c): b.Free()
	b.on_stop = func(c): c.Free()
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["A", "C"], "freed later subscriber is skipped")
	trace.clear()
	a.on_stop = func(c): c.Free()
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["A", "C"], "self-free keeps the next one")
	trace.clear()
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["C"], "freed ones are gone")


func test_component_ids_per_side() -> void:
	# {$IFDEF SERVER} low(integer), counting up; {$IFDEF CLIENT} high(integer), counting down
	var server: TEntity = _world(C.nsServer)[1]
	var client: TEntity = _world(C.nsClient)[1]
	var first := server.GetNewComponentID()
	check_eq(server.GetNewComponentID(), first + 1, "server counts up")
	var cfirst := client.GetNewComponentID()
	check_eq(client.GetNewComponentID(), cfirst - 1, "client counts down")
	# TEntity.Create took the first ID for its TResourceManagerComponent
	check_eq(first, -2147483648 + 1, "server start")
	check_eq(cfirst, 2147483647 - 1, "client start")


func test_groups_reserve_and_free() -> void:
	var e: TEntity = _world()[1]
	var trace := []
	# ReserveFreeGroup starts at RESERVED_GROUPS - 1
	check_eq(e.ReserveFreeGroup(), 19, "first free group")
	check_eq(e.ReserveFreeGroup(), 20, "reserved one is skipped")
	var g19 := TraceComp.new().Setup(e, [19], "g19", trace)
	check_eq(e.FGroupsInUse[19], 1, "first component de-reserves the group")
	TraceComp.new().Setup(e, [C.ALLGROUP_INDEX], "all", trace)
	e.Blackboard.SetValue(C.eiSpeed, [19], 4)
	# FreeGroups: eiFree to the group frees its components but not the ALLGROUP ones (OnComponentFree)
	e.FreeGroups([19])
	check_eq(e.FGroupsInUse[19], 0, "group free again")
	check_eq(e.Blackboard.GetValue(C.eiSpeed, [19]), null, "group values deleted")
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["all"], "group component gone, ALLGROUP component alive")
	check(g19.FSubscribedEvents.is_empty(), "freed component unsubscribed")
	check_eq(e.ReserveFreeGroup(), 19, "group 19 reusable")


func test_global_listener_and_network_send() -> void:
	var w := _world(C.nsServer)
	var global_bus: TEventbus = w[0]
	var e: TEntity = w[1]
	var listener := GlobalListener.new().Create(e)
	# TEventbus.Trigger: an nsServer event triggered on the server is forwarded as eiNetworkSend
	e.Eventbus.Write(C.eiTeamID, [2], [5])
	check_eq(listener.trace, [[7, C.eiTeamID, [5], 0, [2], true]], "network send")
	listener.trace.clear()
	e.Eventbus.Trigger(C.eiUseAbility, [])
	check_eq(listener.trace, [], "client event not sent by the server")
	listener.Free()
	global_bus.Trigger(C.eiNetworkSend, [0, 0, [], 0, [], false])
	check_eq(listener.trace, [], "freed listener unsubscribed from the global bus")


func test_entity_free_and_change_priority() -> void:
	var e: TEntity = _world()[1]
	var trace := []
	var a := TraceComp.new().Setup(e, [], "A", trace)
	TraceComp.new().Setup(e, [], "B", trace)
	# ChangeEventPriority unsubscribes and subscribes again with the new priority
	a.ChangeEventPriority(C.eiWelaStop, C.etTrigger, C.epLast)
	e.Eventbus.Trigger(C.eiWelaStop, [])
	check_eq(trace, ["B", "A"], "A moved last")
	# TEntity.Destroy: eiBeforeFree + eiFree to everyone frees all components
	e.Free()
	check(a.FSubscribedEvents.is_empty(), "components freed with the entity")


func test_rparam_memory_casts() -> void:
	# RParam reads by memory cast: an integer read as single is its bit pattern, and vice versa
	check_eq(RParam.AsInteger(1.0), 1065353216, "single 1.0 as integer")
	check_eq(RParam.AsSingle(1065353216), 1.0, "integer as single")
	check_eq(RParam.AsBoolean(256), false, "boolean is the first byte")
	check_eq(RParam.AsIntegerDefault(null, 12), 12, "default on empty")
	check_eq(RParam.AsBooleanDefaultTrue(null), true, "empty is true")
