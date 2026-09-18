class_name TEventbus
extends TObject
## Port of TEventbus (BaseConflict.Entity.pas:141, implementation :990). Every entity has one; the game has a
## global one (Owner = null). Subscribers are TEntityComponents, ordered by priority, then by subscription order.
## The script side (TEventbusScriptSideHelper, :2034) is folded in: Trigger / Write take the script's value
## array (floats become singles), TriggerGrouped / WriteGrouped add the group.
## Port notes:
## - `var` event parameters: Delphi hands every handler the same parameter array by reference, so a handler
##   that assigns a `var` parameter changes what later handlers (and the blackboard write) see. GDScript passes
##   copies; such handlers call TEntityComponent.SetVarParam, which writes into CurrentParameters.
## - ApplicationType replaces the per-process APPLICATIONTYPE; Game replaces the per-process Game global.
## Not ported yet: InvokeWithRawData (network receive, phase 3).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

## TEventbus.RSubscriber
class RSubscriber:
	var EntityComponent = null  # TEntityComponent
	var Priority: int = 0

	func _init(entity_component, priority: int) -> void:
		EntityComponent = entity_component
		Priority = priority


## TEventbus.TEventEnumerator: one per nesting level of the same event, kept in step with inserts/removals.
class TEventEnumerator:
	var FOwner = null  # TEventhandler
	var FCurrentlyActive := false
	var FActiveIndex := 0

	func _init(owner) -> void:
		FOwner = owner

	func CurrentSubscriber() -> RSubscriber:
		assert(FCurrentlyActive)
		return FOwner.Subscribers[FActiveIndex]

	func HasNext() -> bool:
		return FActiveIndex < FOwner.Subscribers.size()

	func Increment() -> void:
		FActiveIndex += 1

	func Decrement() -> void:
		FActiveIndex -= 1

	func BeginEvent() -> void:
		assert(not FCurrentlyActive, "TEventbus.TEventhandler.BeginEvent: Eventhandler has been entered twice!")
		FCurrentlyActive = true
		FActiveIndex = 0

	func EndEvent() -> void:
		assert(FCurrentlyActive, "TEventbus.TEventhandler.EndEvent: Eventhandler has been entered twice!")
		FCurrentlyActive = false


## TEventbus.TEventhandler: the subscriber list of one event and event type.
class TEventhandler:
	var ParameterCount := 0
	var FEnumerators: Array = []
	var FEnumeratorIndex := 0
	var Subscribers: Array = []  # of RSubscriber

	func _init(parameter_count: int) -> void:
		ParameterCount = parameter_count
		FEnumerators.append(TEventEnumerator.new(self))

	func AddSubscriber(Subscriber: RSubscriber) -> void:
		var Inserted := false
		for i in Subscribers.size():
			if Subscribers[i].Priority > Subscriber.Priority:
				Subscribers.insert(i, Subscriber)
				Inserted = true
				# if a subscriber get added before or at current position, the position has to increment as stack grows
				for e in FEnumerators:
					if e.FCurrentlyActive and i <= e.FActiveIndex:
						e.Increment()
				break
		if not Inserted:
			Subscribers.append(Subscriber)

	func IndexOf(Subscriber: RSubscriber) -> int:
		for i in Subscribers.size():
			if Subscribers[i].EntityComponent == Subscriber.EntityComponent and Subscribers[i].Priority == Subscriber.Priority:
				return i
		return -1

	func RemoveSubscriber(Subscriber: RSubscriber) -> void:
		var i := IndexOf(Subscriber)
		assert(i >= 0, "TEventbus.TEventhandler.RemoveSubscriber: Trying to remove subscriber of event, but isn't present!")
		if i < 0:
			return
		Subscribers.remove_at(i)
		# if a subscriber get removed before current position, the position has to decrement as stack shrinks
		for e in FEnumerators:
			if e.FCurrentlyActive and i <= e.FActiveIndex:
				e.Decrement()

	func GetEnumerator() -> TEventEnumerator:
		while FEnumeratorIndex >= FEnumerators.size():
			FEnumerators.append(TEventEnumerator.new(self))
		assert(not FEnumerators[FEnumeratorIndex].FCurrentlyActive, "TEventbus.TEventhandler.GetEnumerator: Last enumerator is active, should not happen.")
		var Result: TEventEnumerator = FEnumerators[FEnumeratorIndex]
		FEnumeratorIndex += 1
		return Result

	func ReleaseEnumerator() -> void:
		assert(FEnumeratorIndex > 0)
		FEnumeratorIndex -= 1
		assert(not FEnumerators[FEnumeratorIndex].FCurrentlyActive)


## threadvar CurrentEvent : REventInformation (the event being executed) and the Eventstack.
static var CurrentEvent_EventIdentifier := 0
static var CurrentEvent_CalledToGroup: Array = []
## Port: the parameter array of the executing event (see SetVarParam).
static var CurrentParameters: Array = []
static var Eventstack: Array = []

var FOwner = null  # TEntity
## [EnumEventIdentifier * 3 + EnumEventType] -> TEventhandler
var FEventhandler := {}
var FRemoteSubscriptions: Array = []  # of TRemoteSubscription
## Port: nsServer or nsClient, the side this bus lives on (APPLICATIONTYPE of the original process).
var ApplicationType: int = C.nsServer
## Port: the TGame of this side (the original's Game global); set on the global eventbus by the game.
var Game = null

var Owner:
	get:
		return FOwner


func Create(Owner = null) -> TEventbus:
	FOwner = Owner
	return self


func Destroy() -> void:
	for sub in FRemoteSubscriptions.duplicate():
		sub.FreeEventbus()
	FRemoteSubscriptions.clear()
	# port: break the reference cycles (enumerator <-> handler, bus <-> owner); Delphi frees memory by hand
	for handler in FEventhandler.values():
		handler.FEnumerators.clear()
	FEventhandler.clear()
	FOwner = null
	Game = null
	super()


static func _key(Event: int, EventType: int) -> int:
	return Event * 3 + EventType


func StartEvent(Event: int, Group: Array, Parameters: Array) -> void:
	CurrentEvent_EventIdentifier = Event
	CurrentEvent_CalledToGroup = Group
	CurrentParameters = Parameters
	Eventstack.push_back([Event, Group, Parameters])


func EndEvent() -> void:
	Eventstack.pop_back()
	if Eventstack.size() > 0:
		var top: Array = Eventstack.back()
		CurrentEvent_EventIdentifier = top[0]
		CurrentEvent_CalledToGroup = top[1]
		CurrentParameters = top[2]
	else:
		CurrentEvent_EventIdentifier = 0
		CurrentEvent_CalledToGroup = []
		CurrentParameters = []


static func _Matches(EntityComponent, Group: Array, ComponentID: int) -> bool:
	var cg: Array = EntityComponent.FComponentGroup
	return (Group.is_empty() or DSet.Intersects(Group, cg) or cg.has(C.ALLGROUP_INDEX)) \
		and (ComponentID == 0 or EntityComponent.FUniqueID == ComponentID)


func Read(Eventname: int, Parameters: Array = [], Group: Array = [], ComponentID: int = 0):
	Parameters = Parameters.duplicate()  # open array parameter passed by value
	Group = DSet.Make(Group)
	StartEvent(Eventname, Group, Parameters)
	var Result = RParam.RPARAMEMPTY
	if FOwner != null:
		Result = FOwner.FBlackboard.GetValue(Eventname, Group)
	var EventHandler: TEventhandler = FEventhandler.get(_key(Eventname, C.etRead))
	if EventHandler != null:
		var EventEnumerator := EventHandler.GetEnumerator()
		EventEnumerator.BeginEvent()
		while EventEnumerator.HasNext():
			var EntityComponent = EventEnumerator.CurrentSubscriber().EntityComponent
			if _Matches(EntityComponent, Group, ComponentID):
				Result = EntityComponent.OnRead(self, Eventname, Parameters, Result)
			EventEnumerator.Increment()
		EventEnumerator.EndEvent()
		EventHandler.ReleaseEnumerator()
	EndEvent()
	return Result


## Reads a value in the local group and if empty is returned, read in the global group.
func ReadHierarchic(Eventname: int, Values: Array, Group: Array):
	var Result = Read(Eventname, Values, Group)
	if not Group.is_empty() and Result == null:
		Result = Read(Eventname, Values, [])
	return Result


func Subscribe(Eventname: int, EventType: int, Priority: int, EntityCompononent, ParameterCount: int) -> void:
	var Subscriber := RSubscriber.new(EntityCompononent, Priority)
	var key := _key(Eventname, EventType)
	var EventHandler: TEventhandler = FEventhandler.get(key)
	if EventHandler == null:
		EventHandler = TEventhandler.new(ParameterCount)
		FEventhandler[key] = EventHandler
	EventHandler.AddSubscriber(Subscriber)


## Subscribe one remote eventbus (a component listening on another entity's or the global bus).
func SubscribeRemote(Eventname: int, EventType: int, Priority: int, EntityCompononent, MethodName: String, ParameterCount: int, _NetworkSender: int = C.nsNone) -> void:
	assert(EntityCompononent.Eventbus() != self, "Wrong method for selfregistration, but technically should work.")
	if not EntityCompononent.has_method(MethodName):
		push_error("TEventbus.SubscribeRemote: Could not find %s in class %s" % [MethodName, EntityCompononent.ClassName()])
		return
	var Subscribtion := TRemoteSubscription.new().Create(EntityCompononent, self, Eventname, EventType, Priority)
	EntityCompononent.FRemoteSubscription.append(Subscribtion)
	FRemoteSubscriptions.append(Subscribtion)
	EntityCompononent.SubscribeEvent(Eventname, EventType, Priority, MethodName, ParameterCount, self)


## Values: `array of RParam`. Script side Trigger(Eventname, Values) goes here too.
func Trigger(Eventname: int, Values: Array = [], Group: Array = [], ComponentID: int = 0, Write: bool = false) -> void:
	Values = _ScriptValues(Values)  # open array parameter passed by value
	Group = DSet.Make(Group)
	StartEvent(Eventname, Group, Values)
	var EventHandler: TEventhandler = FEventhandler.get(_key(Eventname, C.etWrite if Write else C.etTrigger))
	if EventHandler != null:
		var EventEnumerator := EventHandler.GetEnumerator()
		EventEnumerator.BeginEvent()
		while EventEnumerator.HasNext():
			var Subscriber := EventEnumerator.CurrentSubscriber()
			if _Matches(Subscriber.EntityComponent, Group, ComponentID):
				if not Subscriber.EntityComponent.OnTrigger(self, Eventname, Values, Write):
					EventEnumerator.EndEvent()
					EventHandler.ReleaseEnumerator()
					EndEvent()
					return
			EventEnumerator.Increment()
		EventEnumerator.EndEvent()
		EventHandler.ReleaseEnumerator()
	if BC.EventIdentifierToNetworkSend(Eventname) == ApplicationType:
		var Parameters := Values.duplicate()
		# only the globaleventbus has no owner
		var GlobalEventbus: TEventbus = FOwner.FGlobalEventbus if FOwner != null else self
		var SendID: int = FOwner.ID if FOwner != null else 0
		if GlobalEventbus != null:
			GlobalEventbus.Trigger(C.eiNetworkSend, [SendID, Eventname, Group, ComponentID, Parameters, Write])
	if FOwner != null and Write and Values.size() > 0:
		FOwner.FBlackboard.SetValue(Eventname, Group, Values[0])
	EndEvent()


func Write(Eventname: int, Values: Array = [], Group: Array = [], ComponentID: int = 0) -> void:
	Trigger(Eventname, Values, Group, ComponentID, true)


## Script side TriggerGrouped(Eventname, Values, Group)
func TriggerGrouped(Eventname: int, Values: Array, Group: Array) -> void:
	Trigger(Eventname, Values, Group)


## Script side WriteGrouped(Eventname, Values, Group)
func WriteGrouped(Eventname: int, Values: Array, Group: Array) -> void:
	Write(Eventname, Values, Group)


func Unsubscribe(Eventname: int, EventType: int, Priority: int, EntityComponent) -> void:
	var EventHandler: TEventhandler = FEventhandler.get(_key(Eventname, EventType))
	assert(EventHandler != null)
	if EventHandler != null:
		EventHandler.RemoveSubscriber(RSubscriber.new(EntityComponent, Priority))


## The copy of the value array every call makes; script floats become singles (TEventbusScriptSideHelper).
static func _ScriptValues(Values: Array) -> Array:
	var copy := Values.duplicate()
	for i in copy.size():
		if copy[i] is float:
			copy[i] = RParam.ToSingle(copy[i])
	return copy
