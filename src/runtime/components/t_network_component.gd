class_name TNetworkComponent
extends TEntityComponent
## Port of TNetworkComponent (BaseConflict.EntityComponents.Shared.pas:257, implementation :1191): handles all
## network tasks of a side. eiNetworkSend (fired by TEventbus.Trigger for the events EventIdentifierToNetworkSend
## gives to this side) becomes a NET_EVENT packet: entity ID, event, group, component ID, write flag and the raw
## parameters; NewData invokes a received NET_EVENT on the addressed entity (EntityManager.InvokeEventOnEntity).
## Subclasses send (TServerNetworkComponent: to every player, TClientNetworkComponent: to the server).
## Port notes: the original copies each parameter's raw bytes (a Word size, then the data; size 0 arrives as an
## empty RParam) and the receiver reads them by memory cast, which the port's RParam accessors do as well. The port
## copies the values instead (RawParameters): empty strings and arrays arrive empty, records the port keeps as
## objects are cloned, objects that are no records (the original asserts against ptTObject / ptPointer) arrive
## empty. Non-empty strings arrive as they were sent: in the original their UTF-16 bytes arrive untyped and AsString
## casts them (see docs/game-loop.md, "Network").

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FNetworkDelay := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnNetworkSend", C.eiNetworkSend, C.epLast, C.etTrigger, C.esGlobal))


## Send an event via the network.
func OnNetworkSend(EntityID, Event, Group, ComponentID, Parameters, Write) -> bool:
	if not HasReceivers():
		return true
	var SendData := TCommandSequence.new().Create(BC.NET_EVENT)
	SendData.AddData(RParam.AsInteger(EntityID))
	SendData.AddData(RParam.AsEnumType(Event))
	SendData.AddData(RParam.AsSet(Group).duplicate())
	SendData.AddData(RParam.AsInteger(ComponentID))
	SendData.AddData(RParam.AsBoolean(Write))
	SendData.AddData(RawParameters(RParam.AsArray(Parameters)))
	# finally send
	Send(SendData)
	return true


## The parameters as they come off the wire (see the class notes).
static func RawParameters(ParameterArray: Array) -> Array:
	var Result: Array = []
	for Parameter in ParameterArray:
		Result.append(_RawValue(Parameter))
	return Result


static func _RawValue(Value):
	if Value is String and Value == "":
		return null
	if Value is Array:
		if Value.is_empty():
			return null
		var Result: Array = []
		for Element in Value:
			Result.append(_RawElement(Element))
		return Result
	return _RawElement(Value)


static func _RawElement(Value):
	if Value is Array:
		var Result: Array = []
		for Element in Value:
			Result.append(_RawElement(Element))
		return Result
	if Value is Dictionary:
		return Value.duplicate(true)
	if Value is Object:
		if Value.has_method("Clone"):
			return Value.Clone()
		if Value.has_method("Copy"):
			return Value.Copy()
		push_error("TNetworkComponent: parameter type %s for networksend not supported!" % Value.get_class())
		return null
	return Value


## Port: whether a send reaches anybody (a server without connected players skips building the packet).
func HasReceivers() -> bool:
	return true


## Send a packet (abstract).
func Send(_Data: TCommandSequence) -> void:
	pass


func NewData(Data: TCommandSequence) -> void:
	assert(Data.Command == BC.NET_EVENT)
	var EntityID: int = Data.Read()
	var Eventname: int = Data.Read()
	var GroupID: Array = Data.Read()
	var ComponentID: int = Data.Read()
	var Write: bool = Data.Read()
	var RawData: Array = Data.Read()
	var Game = GlobalEventbus().Game
	assert(Game != null, "TNetworkComponent.NewData: New data received, but no active game!")
	Game.EntityManager.InvokeEventOnEntity(EntityID, Eventname, GroupID, ComponentID, RawData, Write)
