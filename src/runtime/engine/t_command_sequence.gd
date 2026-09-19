class_name TCommandSequence
extends RefCounted
## Stand-in for the network packets of Engine.Network.pas: TCommandSequence (what a sender builds: a command, then
## data appended with AddData / AddDataArray / AddStream) and TDatapacket (what the receiver reads in the same order:
## Read / ReadArray / ReadString / ReadList / ReadStream). The port's client and server run in one process and pass
## packets over a TLoopbackSocket, so a packet is its values in write order, not bytes. What the bytes would have
## lost is dropped where the values are written (TNetworkComponent.OnNetworkSend copies the event parameters).

var Command := 0
var Data: Array = []
var Position := 0


func Create(Command_: int) -> TCommandSequence:
	Command = Command_
	return self


func AddData(Value) -> void:
	Data.append(Value)


## AddDataArray<T>, AddStream: one value each.
func AddDataArray(Value: Array) -> void:
	Data.append(Value.duplicate())


func AddStream(Stream: TEntityStream) -> void:
	Data.append(Stream)


func Read():
	var Value = Data[Position]
	Position += 1
	return Value


func ReadArray() -> Array:
	return Read()


func ReadList() -> Array:
	return Read()


func ReadString() -> String:
	return Read()


## ReadStream: a reader of the stream from its start (every receiver of a packet reads its own).
func ReadStream() -> TEntityStream:
	var Stream := TEntityStream.new()
	Stream.Data = (Read() as TEntityStream).Data
	return Stream


## GetCopy: the packet as it goes over the wire; the receiver reads it from the start.
func GetCopy() -> TCommandSequence:
	var Result := TCommandSequence.new().Create(Command)
	Result.Data = Data.duplicate()
	return Result
