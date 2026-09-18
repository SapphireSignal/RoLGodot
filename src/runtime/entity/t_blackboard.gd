class_name TBlackboard
extends TObject
## Port of TBlackboard (BaseConflict.Entity.pas:100, implementation :2257). Holds a value for every event, the
## entity-local pool of values. The script side (TBlackboardScriptInvoker, :1871) calls the same methods: its
## overloads are folded into SetValue / SetIndexedValue / SetIndexedValues (the value's type picks the overload).
## SaveToStream / LoadFromStream carry the values in a TEntityStream (the network's byte stream in the original).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FOwner = null  # TEntity
## Values for [Event][GroupIndex][SubIndex]: Event -> Array of Arrays. GroupIndex 0 = no group, g + 1 = group g;
## SubIndex 0 = the plain value, i + 1 = indexed value i. A missing key / empty Array = not assigned.
var FValues := {}


func Create(Owner = null) -> TBlackboard:
	FOwner = Owner
	return self


func Destroy() -> void:
	# port: drop the values and the owner so no reference cycle keeps the entity alive
	FValues.clear()
	FOwner = null
	super()


func GetValueRaw(Event: int, GroupIndex: int, Index: int):
	var found = FValues.get(Event)
	if found == null:
		return RParam.RPARAMEMPTY
	var groups: Array = found
	if groups.size() > GroupIndex:
		var values: Array = groups[GroupIndex]
		if values.size() > Index:
			return values[Index]
	return RParam.RPARAMEMPTY


func SetValueRaw(Event: int, GroupIndex: int, Index: int, Value) -> void:
	if not FValues.has(Event):
		FValues[Event] = []
	var groups: Array = FValues[Event]
	while groups.size() <= GroupIndex:
		groups.append([])
	var values: Array = groups[GroupIndex]
	if values.size() <= Index:
		values.resize(Index + 1)
	values[Index] = Value


func DeleteValues(Group: Array) -> void:
	if Group.is_empty():
		return
	for Event in FValues:
		var groups: Array = FValues[Event]
		for i in DSet.Make(Group):
			if groups.size() > i + 1:
				groups[i + 1] = []


## The global group has index -1. Other indices as usual. If value is not present returns RPARAMEMPTY.
func GetIndexedValue(Event: int, Group: Array, Index: int):
	# index 0 is reserved for the default index
	Index += 1
	if Group.is_empty():
		return GetValueRaw(Event, 0, Index)
	if Group.size() == 1:
		return GetValueRaw(Event, int(Group[0]) + 1, Index)
	var Result = RParam.RPARAMEMPTY
	for i in DSet.Make(Group):
		Result = GetValueRaw(Event, i + 1, Index)
		if Result != null:
			break
	return Result


## Returns index -> value (TDictionary<integer, RParam>).
func GetIndexMap(Event: int, Group: Array) -> Dictionary:
	var Result := {}
	if not FValues.has(Event):
		return Result
	var groups: Array = FValues[Event]
	if Group.is_empty():
		if groups.size() >= 1:
			for i in range(1, groups[0].size()):
				var Value = GetValueRaw(Event, 0, i)
				if Value != null:
					Result[i - 1] = Value
	else:
		for i in DSet.Make(Group):
			if groups.size() > i + 1 and not groups[i + 1].is_empty():
				for j in range(1, groups[i + 1].size()):
					var Value = GetValueRaw(Event, i + 1, j)
					if Value != null:
						Result[j - 1] = Value
				if Result.is_empty():
					break
	return Result


func GetValue(Event: int, Group: Array):
	return GetIndexedValue(Event, Group, -1)


func SetIndexedValue(Event: int, Group: Array, Index: int, Value) -> void:
	Value = VarToRParam(Event, Value)
	Index += 1
	if Group.is_empty():
		SetValueRaw(Event, 0, Index, Value)
	else:
		for i in DSet.Make(Group):
			SetValueRaw(Event, i + 1, Index, Value)


func SetValue(Event: int, Group: Array, Value) -> void:
	SetIndexedValue(Event, Group, -1, Value)


## SaveToStream: the count of assigned values, then each as event, group slot, index slot, value, in event order.
## Port: the stream is an Array the entries are appended to (TEntityStream), values are deep copies (the original
## serializes the RParam).
func SaveToStream(Stream: TEntityStream) -> void:
	var entries: Array = []
	var events: Array = FValues.keys()
	events.sort()
	for i: int in events:
		var groups: Array = FValues[i]
		for j in groups.size():
			var values: Array = groups[j]
			for k in values.size():
				if values[k] != null:
					entries.append([i, j, k, values[k]])
	Stream.Write(entries.size())
	for entry: Array in entries:
		Stream.Write(entry[0])
		Stream.Write(entry[1])
		Stream.Write(entry[2])
		Stream.Write(RParam.Copy(entry[3]))


## LoadFromStream: blackboard events (EventIdentifierToBlackboardEvent) are written through the owner (position and
## front through its setters), the others go into the blackboard raw.
func LoadFromStream(Stream: TEntityStream) -> void:
	var Count: int = Stream.Read()
	for _n in Count:
		var i: int = Stream.Read()
		var j: int = Stream.Read()
		var k: int = Stream.Read()
		var Para = RParam.Copy(Stream.Read())
		if Para == null:
			continue
		if BC.EventIdentifierToBlackboardEvent(i):
			assert(k == 0, "TBlackboard.LoadFromStream: Blackboardevents cannot have indices!")
			var Group: Array = [] if j <= 0 else [j - 1]
			if i == C.eiPosition:
				FOwner.Position = RParam.AsVector2(Para)
			elif i == C.eiFront:
				FOwner.Front = RParam.AsVector2(Para)
			else:
				FOwner.Eventbus.Write(i, [Para], Group)
		else:
			SetValueRaw(i, j, k, Para)


## Script side SetIndexedValues(Event, Group, Values: TArray<integer|single|string>): value i at index i.
func SetIndexedValues(Event: int, Group: Array, Values: Array) -> void:
	for i in Values.size():
		SetIndexedValue(Event, Group, i, Values[i])


## TBlackboardScriptInvoker.VarToRParam and SetValueByteArrayInvoker (:2592, :2622). A script float becomes a
## single; an array is a byte array, or a set for eiUnitProperties / eiDamageType (sets are Arrays in the port
## too, so both keep the members; the set is normalised). Arrays are copied: RParam.FromArray copies the data.
static func VarToRParam(Event: int, Value):
	match typeof(Value):
		TYPE_FLOAT:
			return RParam.ToSingle(Value)
		TYPE_ARRAY:
			if Event == C.eiUnitProperties or Event == C.eiDamageType:
				return DSet.Make(Value)
			return Value.duplicate()
	return Value
