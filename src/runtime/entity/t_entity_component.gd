class_name TEntityComponent
extends TObject
## Port of TEntityComponent (BaseConflict.Entity.pas:211, implementation :1230). A component lives in its owner
## entity, belongs to component groups and handles events.
##
## Event handlers: the original marks published methods with [XEvent(Event, Priority, EventType, Scope)] and
## finds them by RTTI. Here a class lists them in _DeclareEvents, calling super first:
##     func _DeclareEvents(e: Array) -> void:
##         super(e)
##         e.append(XEvent("OnFoo", C.eiFoo, C.epLast, C.etTrigger))
## A later entry for the same event and event type replaces the earlier one (the derived class wins, as the
## original's "prevent double subscription by inheritance" does). The parameter count comes from the method.
## Handlers: etTrigger / etWrite return bool (false stops the event), etRead returns the value and may take the
## previous result as an extra last parameter.
##
## Constructors are instance methods returning self: `TFoo.new().CreateGrouped(Owner, Group, ...)`. A subclass
## may add parameters with default values (GDScript override rule).

const C = preload("res://src/runtime/dws/dws_const.gd")

## TEntityComponent.TSubscribedEvent
class TSubscribedEvent:
	var Eventname := 0
	var EventType := 0
	var EventPriority := 0
	var EventHandler := ""  # method name
	var ParameterCount := 0
	var TargetEventbus = null

	func _init(eventname: int, event_handler: String, parameter_count: int, target_eventbus, event_priority: int, event_type: int) -> void:
		Eventname = eventname
		EventHandler = event_handler
		ParameterCount = parameter_count
		TargetEventbus = target_eventbus
		EventPriority = event_priority
		EventType = event_type


## class var FComponentSubscriptionPatterns: [script, IsServerSide] -> Array of [Event, EventType, Priority, Scope, Method, ParameterCount]
static var FComponentSubscriptionPatterns := {}

var FComponentGroup: Array = []
var FOwner = null  # TEntity
## Unique ID for component related to owner entity NOT global.
var FUniqueID := 0
## [Event * 3 + EventType] -> Array of TSubscribedEvent
var FSubscribedEvents := {}
var FRemoteSubscription: Array = []

var Owner:
	get:
		return FOwner
var UniqueID: int:
	get:
		return FUniqueID
var ComponentGroup: Array:
	get:
		return FComponentGroup
	set(value):
		SetSetComponentGroup(value)


## [XEvent(Event, EventPriotity, EventType, EventScope = esLocal)] on method MethodName.
static func XEvent(MethodName: String, Event: int, EventPriotity: int, EventType: int, EventScope: int = C.esLocal) -> Array:
	return [MethodName, Event, EventPriotity, EventType, EventScope]


## Lists the handlers of this class. Overrides call super(e) first, then append.
func _DeclareEvents(e: Array) -> void:
	e.append(XEvent("OnEnumerate", C.eiEnumerateComponents, C.epLast, C.etTrigger))
	e.append(XEvent("OnBeforeComponentFree", C.eiBeforeFree, C.epLast, C.etTrigger))
	e.append(XEvent("OnComponentFree", C.eiFree, C.epLast, C.etTrigger))


func Create(Owner = null) -> TEntityComponent:
	return CreateGrouped(Owner, [])


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	FOwner = Owner
	FRemoteSubscription = []
	FUniqueID = Owner.GetNewComponentID()
	FComponentGroup = DSet.Make(Group)
	RegisterInOwner()
	SubscribeEvents()
	return self


func CreateGroupedAll(Owner = null) -> TEntityComponent:
	return CreateGrouped(Owner, [C.ALLGROUP_INDEX])


func Destroy() -> void:
	DeregisterInOwner()
	UnSubscribeEvents()
	FRemoteSubscription = []
	FOwner = null  # port: break the reference cycle (Delphi frees memory by hand)
	super()


static func _key(Event: int, EventType: int) -> int:
	return Event * 3 + EventType


func Eventbus() -> TEventbus:
	assert(FOwner != null)
	return FOwner.FEventbus


func GlobalEventbus() -> TEventbus:
	assert(FOwner != null)
	return FOwner.FGlobalEventbus


## Port: assigns a `var` parameter of the executing event (see TEventbus). Index is the parameter position.
func SetVarParam(Index: int, Value) -> void:
	TEventbus.CurrentParameters[Index] = Value


func BuildExceptionMessage(ExceptionMessage: String) -> String:
	return "%s.%s Group|Called: %s|%s Entity: %s" % [ClassName(), ExceptionMessage, str(ComponentGroup),
		str(TEventbus.CurrentEvent_CalledToGroup), Owner.ScriptFile if Owner != null else ""]


func MakeException(ExceptionMessage: String) -> void:
	push_error(BuildExceptionMessage(ExceptionMessage))


func CardLeague() -> int:
	return RParam.AsInteger(Eventbus().ReadHierarchic(C.eiResourceBalance, [C.reCardLeague], ComponentGroup))


func CardLevel() -> int:
	return RParam.AsInteger(Eventbus().ReadHierarchic(C.eiResourceBalance, [C.reCardLevel], ComponentGroup))


func ChangeEventPriority(Eventname: int, EventType: int, Priority: int, Scope: int = C.esLocal) -> void:
	var TargetEventbus: TEventbus = GlobalEventbus() if Scope == C.esGlobal else Eventbus()
	var SubscribedEvent: TSubscribedEvent = LookUpSubscribedEvent(TargetEventbus, Eventname, EventType)
	assert(SubscribedEvent != null, "TEntityComponent.ChangeEventPriority: Could not find event to change!")
	ExtractSubscribedEvent(SubscribedEvent)
	TargetEventbus.Unsubscribe(SubscribedEvent.Eventname, SubscribedEvent.EventType, SubscribedEvent.EventPriority, self)
	SubscribedEvent.EventPriority = Priority
	DeploySubscribedEvent(SubscribedEvent)
	TargetEventbus.Subscribe(SubscribedEvent.Eventname, SubscribedEvent.EventType, SubscribedEvent.EventPriority, self, SubscribedEvent.ParameterCount, SubscribedEvent.EventHandler)


func BeforeComponentFree() -> void:
	pass


func ComponentFree() -> void:
	Free()


## ProcEnumerateEntityComponentCallback: a Callable taking the component.
func EnumerateComponents(Callback: Callable) -> void:
	Callback.call(self)


## Use to free component in an event stack.
func DeferFree() -> void:
	var game = GlobalEventbus().Game if FOwner != null and GlobalEventbus() != null else null
	if game != null:
		game.EntityManager.FreeComponent(self)


## Returns whether the caller belongs to my own group. Prevents execution of groupless events in local groups.
## IsLocalCall() uses the own ComponentGroup, IsLocalCall(TargetGroup) the given one.
func IsLocalCall(TargetGroup = null) -> bool:
	var target: Array = ComponentGroup if TargetGroup == null else DSet.Make(TargetGroup)
	return DSet.Intersects(TEventbus.CurrentEvent_CalledToGroup, target) or target.is_empty()


func OnEnumerate(Callback) -> bool:
	EnumerateComponents(Callback)
	return true


func OnBeforeComponentFree() -> bool:
	# only free with whole entity
	if not TEventbus.CurrentEvent_CalledToGroup.is_empty() and FComponentGroup == [C.ALLGROUP_INDEX]:
		return true
	BeforeComponentFree()
	return true


func OnComponentFree() -> bool:
	# only free with whole entity
	if not TEventbus.CurrentEvent_CalledToGroup.is_empty() and FComponentGroup == [C.ALLGROUP_INDEX]:
		return true
	ComponentFree()
	return true


func LookUpSubscribedEvent(Caller, ei: int, et: int) -> TSubscribedEvent:
	for e in FSubscribedEvents.get(_key(ei, et), []):
		if e.TargetEventbus == Caller:
			return e
	return null


func DeploySubscribedEvent(Event: TSubscribedEvent) -> void:
	assert(LookUpSubscribedEvent(Event.TargetEventbus, Event.Eventname, Event.EventType) == null, "TEntityComponent.DeploySubscribedEvent: Double subscription!")
	var key := _key(Event.Eventname, Event.EventType)
	if not FSubscribedEvents.has(key):
		FSubscribedEvents[key] = []
	FSubscribedEvents[key].append(Event)


func DeleteSubscribedEvent(Event: TSubscribedEvent) -> void:
	var list: Array = FSubscribedEvents.get(_key(Event.Eventname, Event.EventType), [])
	list.erase(Event)


func ExtractSubscribedEvent(Event: TSubscribedEvent) -> void:
	DeleteSubscribedEvent(Event)


# TEntityComponent.OnRead / OnTrigger (the handler call and its parameter count check) are
# TEventbus.RSubscriber.CallRead / CallTrigger: the subscriber carries its handler, so no lookup per call.


func RegisterInOwner() -> void:
	if FOwner != null:
		FOwner.RegisterComponent(self)


func DeregisterInOwner() -> void:
	if FOwner != null:
		FOwner.DeregisterComponent(self)


func SetSetComponentGroup(Value) -> void:
	DeregisterInOwner()
	FComponentGroup = DSet.Make(Value)
	TEventbus.GroupsVersion += 1
	RegisterInOwner()


func SubscribeEvent(Event: int, EventType: int, EventPriority: int, EventHandler: String, ParameterCount: int, TargetEventbus: TEventbus) -> void:
	# subscribe event
	TargetEventbus.Subscribe(Event, EventType, EventPriority, self, ParameterCount, EventHandler)
	DeploySubscribedEvent(TSubscribedEvent.new(Event, EventHandler, ParameterCount, TargetEventbus, EventPriority, EventType))


## Port: the side the component is built for, so _DeclareEvents can list {$IFDEF SERVER} handlers only
## `if IsServerSide():`. The owner decides (FOwner is set before SubscribeEvents).
func IsServerSide() -> bool:
	return FOwner != null and FOwner.IsServer()


## The class's subscription patterns, built once per class and side from _DeclareEvents.
func _SubscriptionPatterns() -> Array:
	var key := [get_script(), IsServerSide()]
	if FComponentSubscriptionPatterns.has(key):
		return FComponentSubscriptionPatterns[key]
	var declared: Array = []
	_DeclareEvents(declared)
	var patterns: Array = []
	for d in declared:
		var method: String = d[0]
		assert(has_method(method), "TEntityComponent.SubscribeEvents: %s has no method %s" % [ClassName(), method])
		var pattern := [d[1], d[3], d[2], d[4], method, get_method_argument_count(method)]
		# prevent double subscription by inheritance: the later (derived) declaration wins
		var replaced := false
		for i in patterns.size():
			if patterns[i][0] == pattern[0] and patterns[i][1] == pattern[1]:
				patterns[i] = pattern
				replaced = true
				break
		if not replaced:
			patterns.append(pattern)
	FComponentSubscriptionPatterns[key] = patterns
	return patterns


func SubscribeEvents() -> void:
	for p in _SubscriptionPatterns():
		var TargetEventbus: TEventbus = FOwner.Eventbus if p[3] == C.esLocal else GlobalEventbus()
		SubscribeEvent(p[0], p[1], p[2], p[4], p[5], TargetEventbus)


func UnSubscribeEvents() -> void:
	for sub in FRemoteSubscription.duplicate():
		sub.FreeComponent()
	var keys := FSubscribedEvents.keys()
	keys.sort()
	for key in keys:
		for Event in FSubscribedEvents[key]:
			Event.TargetEventbus.Unsubscribe(Event.Eventname, Event.EventType, Event.EventPriority, self)
	FSubscribedEvents.clear()
