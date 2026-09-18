class_name TEntityStream
extends RefCounted
## Port stand-in for the TStream an entity is serialized into (TEntity.Serialize, TBlackboard.SaveToStream) and read
## back from on the client (TEntity.Deserialize): the values in write order, read back with a cursor. The byte
## format of the network comes with the network port.

var Data: Array = []
var Position := 0


func Write(Value) -> void:
	Data.append(Value)


func Read():
	var value = Data[Position]
	Position += 1
	return value


func Size() -> int:
	return Data.size()
