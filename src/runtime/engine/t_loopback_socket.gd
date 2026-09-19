class_name TLoopbackSocket
extends RefCounted
## Stand-in for TTCPClientSocketDeluxe (Engine.Network.pas), one end of a game server <-> client connection. The
## port runs both in one process: CreatePair makes the two ends of an in-memory channel; SendData queues a copy of
## the packet at the other end, which takes it with IsDataPacketAvailable / ReceiveDataPacket in send order.
## CloseConnection closes both ends (the peer sees TCPStDisconnected). No latency, loss or ping.

enum { TCPStConnected, TCPStDisconnected }  # EnumTCPStatus, as far as the game asks


class TChannel:
	extends RefCounted
	var Queues: Array = [[], []]
	var Closed := false


var FChannel: TChannel
var FSide := 0


## The two ends of a new connection: [server side, client side].
static func CreatePair() -> Array:
	var Channel := TChannel.new()
	var A := TLoopbackSocket.new()
	A.FChannel = Channel
	A.FSide = 0
	var B := TLoopbackSocket.new()
	B.FChannel = Channel
	B.FSide = 1
	return [A, B]


var Status: int:
	get:
		return TCPStDisconnected if FChannel.Closed else TCPStConnected


func SendData(Data: TCommandSequence) -> void:
	if not FChannel.Closed:
		FChannel.Queues[1 - FSide].append(Data.GetCopy())


func SendCommand(Command: int) -> void:
	SendData(TCommandSequence.new().Create(Command))


## Packets already sent stay readable after a close, like the socket's receive buffer.
func IsDataPacketAvailable() -> bool:
	return not FChannel.Queues[FSide].is_empty()


func ReceiveDataPacket() -> TCommandSequence:
	return FChannel.Queues[FSide].pop_front()


func CloseConnection() -> void:
	FChannel.Closed = true


func IsConnected() -> bool:
	return not FChannel.Closed


func IsDisconnected() -> bool:
	return FChannel.Closed


## GetCurrentPeerTime: the peer's clock; both ends share the process clock.
func GetCurrentPeerTime() -> int:
	return TTimeManager.GetTimeStamp()


func Ping() -> int:
	return 0
