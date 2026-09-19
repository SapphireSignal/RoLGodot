class_name TSerializableEntityComponent
extends TGDEntityComponent
## Port of TSerializableEntityComponent (BaseConflict.Entity.pas:304, implementation :2117): a component the server
## sends with its entity. On eiSerialize (TEntity.Serialize, server) it writes its class (GetBaseType: the first class
## up the hierarchy marked XNetworkBasetype, else its own), its UniqueID and ComponentGroup, then its fields;
## TEntity.Deserialize (client) creates a component of that class on the client's entity, and Deserialize reads the
## same back into it.
## Which fields: the original walks the class's field RTTI, skipping those declared in TObject / TEntityComponent /
## TEntityScriptComponent / TSerializableEntityComponent. The components' RTTI carries their public and protected
## fields, not the private ones (TMovementComponent's private FSyncTimer, a TTimer, would make Serialize raise on
## every unit sent, and TCommanderAbilityComponent's protected card fields must reach the client for its Init; see
## docs/game-loop.md, "Network"). Each class lists them in NetworkFields (declaration order, own class first like
## TRttiType.GetFields); NetworkSerializeEvents gives the fields marked XNetworkSerialize(Event): after deserializing,
## the entity Writes Event with the field's value.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("Serialize", C.eiSerialize, C.epLast, C.etTrigger))


## GetBaseType: the class the client creates (XNetworkBasetype on the class or an ancestor, else the class itself).
func NetworkBaseType() -> String:
	return ClassName()


## The public and protected fields of the base type (see the class notes).
func NetworkFields() -> Array:
	return []


## Field -> event of the fields marked XNetworkSerialize.
func NetworkSerializeEvents() -> Dictionary:
	return {}


## Save all data to the stream. Only called on server.
func Serialize(Stream) -> bool:
	var AStream: TEntityStream = Stream
	AStream.Write(NetworkBaseType())
	# has to serialized manually because all fields from TEntityComponent will skipped
	AStream.Write(FUniqueID)
	AStream.Write(ComponentGroup.duplicate())
	for Field: String in NetworkFields():
		AStream.Write(_CopyValue(get(Field)))
	return true


## Load all data from the stream. Only called on clients.
func Deserialize(Stream: TEntityStream) -> void:
	FUniqueID = Stream.Read()
	ComponentGroup = Stream.Read()
	for Field: String in NetworkFields():
		set(Field, _CopyValue(Stream.Read()))


## Fields are records and arrays of records by value.
static func _CopyValue(Value):
	if Value is Array:
		return Value.map(func(Element): return _CopyValue(Element))
	if Value is Object and Value.has_method("Clone"):
		return Value.Clone()
	return Value
