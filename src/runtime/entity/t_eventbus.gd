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

## TEventbus.RSubscriber. Port: it also carries the handler and its parameter count, and calls it (the original's
## TEntityComponent.OnRead / OnTrigger, which look the handler up per call).
class RSubscriber:
	var EntityComponent = null  # TEntityComponent
	var Priority: int = 0
	var Method: Callable
	var ParameterCount := 0

	func _init(entity_component, priority: int, method_name: String = "", parameter_count: int = 0) -> void:
		EntityComponent = entity_component
		Priority = priority
		if method_name != "":
			Method = Callable(entity_component, method_name)
		ParameterCount = parameter_count

	## TEntityComponent.OnRead: the previous result is an optional extra last parameter.
	func CallRead(Event: int, Parameters: Array, ResultFromAncestor):
		var n := Parameters.size()
		if n + 1 == ParameterCount:
			match n:
				0:
					return Method.call(ResultFromAncestor)
				1:
					return Method.call(Parameters[0], ResultFromAncestor)
				2:
					return Method.call(Parameters[0], Parameters[1], ResultFromAncestor)
				3:
					return Method.call(Parameters[0], Parameters[1], Parameters[2], ResultFromAncestor)
			return Method.callv(Parameters + [ResultFromAncestor])
		if n == ParameterCount:
			return TEventbus._Invoke(Method, Parameters)
		push_error("Parametercount for read event %d in component %s does not match - expected %d[+1], found %d." % [
			Event, EntityComponent.ClassName(), ParameterCount, n])
		return ResultFromAncestor

	## TEntityComponent.OnTrigger
	func CallTrigger(Event: int, Parameters: Array) -> bool:
		if Parameters.size() != ParameterCount:
			push_error("Parametercount for trigger event %d in component %s does not match - expected %d, found %d." % [
				Event, EntityComponent.ClassName(), ParameterCount, Parameters.size()])
			return true
		return TEventbus._Invoke(Method, Parameters)


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
	## Port, a speed-up: bumped by every insert / removal.
	var Version := 0
	## Port, a speed-up: group -> the indices of the subscribers an event called to that single group reaches
	## (in the group or in ALLGROUP), for this Version and TEventbus.GroupsVersion.
	var FMatchCache := {}
	var FMatchCacheGroupsVersion := -1

	func _init(parameter_count: int) -> void:
		ParameterCount = parameter_count
		FEnumerators.append(TEventEnumerator.new(self))

	## GroupsVersion: the calling thread's (a handler lives on one side, so one thread).
	func MatchingIndices(Group: int, GroupsVersion_: int) -> PackedInt32Array:
		if FMatchCacheGroupsVersion != GroupsVersion_:
			FMatchCache.clear()
			FMatchCacheGroupsVersion = GroupsVersion_
		if FMatchCache.has(Group):
			return FMatchCache[Group]
		var Result := PackedInt32Array()
		for i in Subscribers.size():
			var cg: Array = Subscribers[i].EntityComponent.FComponentGroup
			if cg.has(Group) or cg.has(C.ALLGROUP_INDEX):
				Result.append(i)
		FMatchCache[Group] = Result
		return Result

	func AddSubscriber(Subscriber: RSubscriber) -> void:
		Version += 1
		FMatchCache.clear()
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
		Version += 1
		FMatchCache.clear()
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


## threadvar CurrentEvent : REventInformation (the event being executed); the Eventstack see StartEvent. Per thread:
## the calling thread's TThreadContext (the bus itself uses its Ctx, the same object).
static var CurrentEvent_EventIdentifier: int:
	get:
		return TThreadContext.Current().CurrentEvent_EventIdentifier
	set(value):
		TThreadContext.Current().CurrentEvent_EventIdentifier = value
static var CurrentEvent_CalledToGroup: Array:
	get:
		return TThreadContext.Current().CurrentEvent_CalledToGroup
	set(value):
		TThreadContext.Current().CurrentEvent_CalledToGroup = value
## Port: the parameter array of the executing event (see SetVarParam).
static var CurrentParameters: Array:
	get:
		return TThreadContext.Current().CurrentParameters
	set(value):
		TThreadContext.Current().CurrentParameters = value
## Port, a speed-up: bumped whenever a component changes its group (invalidates every TEventhandler.FMatchCache).
static var GroupsVersion: int:
	get:
		return TThreadContext.Current().GroupsVersion
	set(value):
		TThreadContext.Current().GroupsVersion = value

var FOwner = null  # TEntity
## [EnumEventIdentifier * 3 + EnumEventType] -> TEventhandler
var FEventhandler := {}
var FRemoteSubscriptions: Array = []  # of TRemoteSubscription
## Port: nsServer or nsClient, the side this bus lives on (APPLICATIONTYPE of the original process).
var ApplicationType: int = C.nsServer
## Port: the TGame of this side (the original's Game global); set on the global eventbus by the game.
var Game = null
## Port: the original's EntityDataCache global (per game thread, the client's per process); set on the global
## eventbus by the game. The bus frees it (its data entities hang on this bus).
var EntityDataCache: TEntityDataCache = null

var Owner:
	get:
		return FOwner


func Create(Owner = null) -> TEventbus:
	FOwner = Owner
	return self


func Destroy() -> void:
	if EntityDataCache != null:
		EntityDataCache.Free()
		EntityDataCache = null
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


## Port: the Eventstack only restores the outer event when one ends, so Read / Trigger keep the outer event in
## locals and hand it to EndEvent (no stack object per event). The outermost event restores 0 / [] / [].
## Ctx is the calling thread's TThreadContext (looked up once per event by Read / Trigger).
static func StartEvent(Ctx: TThreadContext, Event: int, Group: Array, Parameters: Array) -> void:
	Ctx.CurrentEvent_EventIdentifier = Event
	Ctx.CurrentEvent_CalledToGroup = Group
	Ctx.CurrentParameters = Parameters


static func EndEvent(Ctx: TThreadContext, OuterEvent: int, OuterGroup: Array, OuterParameters: Array) -> void:
	Ctx.CurrentEvent_EventIdentifier = OuterEvent
	Ctx.CurrentEvent_CalledToGroup = OuterGroup
	Ctx.CurrentParameters = OuterParameters


static func _Matches(EntityComponent, Group: Array, ComponentID: int) -> bool:
	var cg: Array = EntityComponent.FComponentGroup
	return (Group.is_empty() or DSet.Intersects(Group, cg) or cg.has(C.ALLGROUP_INDEX)) \
		and (ComponentID == 0 or EntityComponent.FUniqueID == ComponentID)


## Port, a speed-up of the original's walk (every subscriber in order, _Matches each): the state of one walk,
## [matching indices of a single-group event or null, position in them, handler Version, GroupsVersion].
static func _StartWalk(EventHandler: TEventhandler, Group: Array, Ctx: TThreadContext) -> Array:
	var Indices = EventHandler.MatchingIndices(Group[0], Ctx.GroupsVersion) if Group.size() == 1 else null
	return [Indices, 0, EventHandler.Version, Ctx.GroupsVersion, Ctx]


## Moves the enumerator to the next subscriber the event reaches and returns it, null at the end. Uses the
## matching indices while the subscriber list and the groups stay as they were, else walks as the original.
static func _NextSubscriber(EventHandler: TEventhandler, EventEnumerator: TEventEnumerator, Group: Array, ComponentID: int, Walk: Array) -> RSubscriber:
	var Subscribers: Array = EventHandler.Subscribers
	if Walk[0] != null and (EventHandler.Version != Walk[2] or Walk[4].GroupsVersion != Walk[3]):
		Walk[0] = null
	if Walk[0] != null:
		var Indices: PackedInt32Array = Walk[0]
		var k: int = Walk[1]
		while k < Indices.size():
			var i := Indices[k]
			k += 1
			if i >= EventEnumerator.FActiveIndex:
				var Subscriber: RSubscriber = Subscribers[i]
				if ComponentID == 0 or Subscriber.EntityComponent.FUniqueID == ComponentID:
					Walk[1] = k
					EventEnumerator.FActiveIndex = i
					return Subscriber
		Walk[1] = k
		EventEnumerator.FActiveIndex = Subscribers.size()
		return null
	while EventEnumerator.FActiveIndex < Subscribers.size():
		var Subscriber: RSubscriber = Subscribers[EventEnumerator.FActiveIndex]
		if _Matches(Subscriber.EntityComponent, Group, ComponentID):
			return Subscriber
		EventEnumerator.FActiveIndex += 1
	return null


func Read(Eventname: int, Parameters: Array = [], Group: Array = [], ComponentID: int = 0):
	if not Parameters.is_empty():
		Parameters = Parameters.duplicate()  # open array parameter passed by value
	Group = DSet.Make(Group)
	var Ctx := TThreadContext.Current()
	var OuterEvent := Ctx.CurrentEvent_EventIdentifier
	var OuterGroup := Ctx.CurrentEvent_CalledToGroup
	var OuterParameters := Ctx.CurrentParameters
	StartEvent(Ctx, Eventname, Group, Parameters)
	var Result = null  # RPARAMEMPTY
	if FOwner != null:
		Result = FOwner.FBlackboard.GetValue(Eventname, Group)
	var EventHandler: TEventhandler = FEventhandler.get(_key(Eventname, C.etRead))
	if EventHandler != null:
		var EventEnumerator := EventHandler.GetEnumerator()
		EventEnumerator.BeginEvent()
		var Walk := _StartWalk(EventHandler, Group, Ctx)
		while true:
			var Subscriber := _NextSubscriber(EventHandler, EventEnumerator, Group, ComponentID, Walk)
			if Subscriber == null:
				break
			if Ctx.Prof != null:
				var t := _ProfEnter(Ctx)
				Result = Subscriber.CallRead(Eventname, Parameters, Result)
				_ProfLeave(Ctx, Subscriber, t)
			else:
				Result = Subscriber.CallRead(Eventname, Parameters, Result)
			EventEnumerator.FActiveIndex += 1
		EventEnumerator.EndEvent()
		EventHandler.ReleaseEnumerator()
	EndEvent(Ctx, OuterEvent, OuterGroup, OuterParameters)
	return Result


## Reads a value in the local group and if empty is returned, read in the global group.
func ReadHierarchic(Eventname: int, Values: Array, Group: Array):
	var Result = Read(Eventname, Values, Group)
	if not Group.is_empty() and Result == null:
		Result = Read(Eventname, Values, [])
	return Result


## Port: MethodName and ParameterCount are the handler the subscriber calls (see RSubscriber).
func Subscribe(Eventname: int, EventType: int, Priority: int, EntityCompononent, ParameterCount: int, MethodName: String) -> void:
	var Subscriber := RSubscriber.new(EntityCompononent, Priority, MethodName, ParameterCount)
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
	var Ctx := TThreadContext.Current()
	var OuterEvent := Ctx.CurrentEvent_EventIdentifier
	var OuterGroup := Ctx.CurrentEvent_CalledToGroup
	var OuterParameters := Ctx.CurrentParameters
	StartEvent(Ctx, Eventname, Group, Values)
	var EventHandler: TEventhandler = FEventhandler.get(_key(Eventname, C.etWrite if Write else C.etTrigger))
	if EventHandler != null:
		var EventEnumerator := EventHandler.GetEnumerator()
		EventEnumerator.BeginEvent()
		var Walk := _StartWalk(EventHandler, Group, Ctx)
		while true:
			var Subscriber := _NextSubscriber(EventHandler, EventEnumerator, Group, ComponentID, Walk)
			if Subscriber == null:
				break
			var Continue: bool
			if Ctx.Prof != null:
				var t := _ProfEnter(Ctx)
				Continue = Subscriber.CallTrigger(Eventname, Values)
				_ProfLeave(Ctx, Subscriber, t)
			else:
				Continue = Subscriber.CallTrigger(Eventname, Values)
			if not Continue:
				EventEnumerator.EndEvent()
				EventHandler.ReleaseEnumerator()
				EndEvent(Ctx, OuterEvent, OuterGroup, OuterParameters)
				return
			EventEnumerator.FActiveIndex += 1
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
	EndEvent(Ctx, OuterEvent, OuterGroup, OuterParameters)


func Write(Eventname: int, Values: Array = [], Group: Array = [], ComponentID: int = 0) -> void:
	Trigger(Eventname, Values, Group, ComponentID, true)


## An event received over the network (TNetworkComponent.NewData): Values are the sender's parameters as they came
## off the wire (TNetworkComponent.OnNetworkSend: empty ones are null). Write or Trigger here.
func InvokeWithRawData(Eventname: int, Group: Array, ComponentID: int, Values: Array, WriteEvent: bool) -> void:
	if WriteEvent:
		Write(Eventname, Values, Group, ComponentID)
	else:
		Trigger(Eventname, Values, Group, ComponentID)


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
	if Values.is_empty():
		return Values
	var copy := Values.duplicate()
	for i in copy.size():
		if copy[i] is float:
			copy[i] = RParam.ToSingle(copy[i])
	return copy


## Calls a handler with the parameter array spread out (Object.callv, without its array for the usual counts).
static func _Invoke(Method: Callable, Parameters: Array):
	match Parameters.size():
		0:
			return Method.call()
		1:
			return Method.call(Parameters[0])
		2:
			return Method.call(Parameters[0], Parameters[1])
		3:
			return Method.call(Parameters[0], Parameters[1], Parameters[2])
		4:
			return Method.call(Parameters[0], Parameters[1], Parameters[2], Parameters[3])
	return Method.callv(Parameters)


## Port, a development aid: set Prof = {} to time every handler call ("Class.Method" -> [calls, self us,
## inclusive us]; self time leaves out the handlers it calls through the buses). tests/profile_sandbox.gd uses it.
## Per thread (TThreadContext.Prof): profile the client and the server game separately.
static var Prof:
	get:
		return TThreadContext.Current().Prof
	set(value):
		TThreadContext.Current().Prof = value


static func _ProfEnter(Ctx: TThreadContext) -> int:
	Ctx.ProfChildTime.append(0)
	return Time.get_ticks_usec()


static func _ProfLeave(Ctx: TThreadContext, Subscriber: RSubscriber, Start: int) -> void:
	var Total: int = Time.get_ticks_usec() - Start
	var Children: int = Ctx.ProfChildTime.pop_back()
	if not Ctx.ProfChildTime.is_empty():
		Ctx.ProfChildTime[-1] += Total
	var Key: String = Subscriber.EntityComponent.ClassName() + "." + Subscriber.Method.get_method()
	var Entry: Array = Ctx.Prof.get(Key, [0, 0, 0])
	Entry[0] += 1
	Entry[1] += Total - Children
	Entry[2] += Total
	Ctx.Prof[Key] = Entry
