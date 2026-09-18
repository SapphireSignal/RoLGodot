class_name TRingBuffer
extends RefCounted
## Port of TRingBuffer<T> (Engine\Engine.Helferlein.DataStructures.pas:615, implementation :1304): Size cells,
## index i lives in cell i mod Size and remembers which index set it. Reading an index whose cell was set by
## another index returns DefaultValue (with EnableDefaultValue). Every cell starts as index 0 with the zero
## value of T (the original FillChars the buffer), so index 0 counts as set from the start.

var FIndices := PackedInt64Array()
var FValues: Array = []
var FLastIndex := -1
var DefaultValue = null
var EnableDefaultValue := true

var LastIndex: int:
	get:
		return FLastIndex
var Size: int:
	get:
		return FIndices.size()


## Create(Size); ZeroValue is default(T) (false for booleans), also the initial DefaultValue.
func _init(Size_: int, ZeroValue = null) -> void:
	assert(Size_ > 0)
	FIndices.resize(Size_)
	FValues.resize(Size_)
	FValues.fill(ZeroValue)
	DefaultValue = ZeroValue


func GetCellIndex(Index: int) -> int:
	assert(Index >= 0)
	return Index % FIndices.size()


func GetItem(Index: int):
	var cellIndex := GetCellIndex(Index)
	if not EnableDefaultValue or FIndices[cellIndex] == Index:
		return FValues[cellIndex]
	return DefaultValue


func SetItem(Index: int, Value) -> void:
	var cellIndex := GetCellIndex(Index)
	FIndices[cellIndex] = Index
	FValues[cellIndex] = Value
	FLastIndex = Index


## Returns True is the cell that the index points is set by the index, else false.
func IsIndexSet(Index: int) -> bool:
	return FIndices[GetCellIndex(Index)] == Index


## Add value to end of ringbuffer using last index + 1.
func Append(Value) -> void:
	SetItem(LastIndex + 1, Value)
