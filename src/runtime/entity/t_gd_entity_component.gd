class_name TGDEntityComponent
extends TEntityComponent
## The base of the components still written in GDScript while the game moves to C++ (docs/native.md, "GDScript
## subclasses of C++ classes"). TEntityComponent (BaseConflict.Entity.pas:211, implementation :1230) is C++; GDScript
## cannot override a method a C++ class binds, so what the components override lives here: the constructors, Destroy,
## the XEvent list and the base handlers. It goes when the last GDScript component has moved.
##
## Event handlers: the original marks published methods with [XEvent(Event, Priority, EventType, Scope)] and finds
## them by RTTI. Here a class lists them in _DeclareEvents, calling super first:
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
	_CreateGrouped(Owner, Group)
	return self


func CreateGroupedAll(Owner = null) -> TEntityComponent:
	return CreateGrouped(Owner, [C.ALLGROUP_INDEX])


## Destructor. Overrides call super() at the end, where the Delphi code says `inherited`.
func Destroy() -> void:
	_Destroy()


func Free() -> void:
	Destroy()


func ClassName() -> String:
	var script: Script = get_script()
	while script != null:
		var name := script.get_global_name()
		if name != &"":
			return name
		script = script.get_base_script()
	return "TEntityComponent"


func BeforeComponentFree() -> void:
	pass


func ComponentFree() -> void:
	Free()


## ProcEnumerateEntityComponentCallback: a Callable taking the component.
func EnumerateComponents(Callback: Callable) -> void:
	Callback.call(self)


func OnEnumerate(Callback) -> bool:
	EnumerateComponents(Callback)
	return true


func OnBeforeComponentFree() -> bool:
	# only free with whole entity
	if not TEventbus.GetCurrentEvent_CalledToGroup().is_empty() and FComponentGroup == [C.ALLGROUP_INDEX]:
		return true
	BeforeComponentFree()
	return true


func OnComponentFree() -> bool:
	# only free with whole entity
	if not TEventbus.GetCurrentEvent_CalledToGroup().is_empty() and FComponentGroup == [C.ALLGROUP_INDEX]:
		return true
	ComponentFree()
	return true
