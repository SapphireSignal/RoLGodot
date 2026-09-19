class_name TServerNetworkComponent
extends TNetworkComponent
## Port of TServerNetworkComponent (GameServer/BaseConflict.EntityComponents.Server.pas:172, implementation :1087), on
## the server's game entity (made by TGameThread): the game server's side of the connections. It holds a
## TNetworkPlayer for every player of the game information that is no bot. A new connection (OnClientConnect) sends
## NET_HELLO_SERVER with its token and becomes that player's socket (psPreparing, NET_ASSIGNED_PLAYER with the
## token's commander IDs); the player's NET_CLIENT_ENTER_CORE gets it the world (SendWorld: every deployed entity
## with a script, then NET_SERVER_FINISHED_SEND_GAME_DATA), NET_CLIENT_READY makes it psPlaying, its NET_EVENTs are
## invoked on the server (NewData). Entities made later go to every player (eiSendEntities), events too (Send).
## Every packet to a player carries the player's send index last (piggybacked, for reconnects).
## Port notes: connections are TLoopbackSockets, OnClientConnect takes the server end; no TCP server socket, port,
## reconnect (NET_RECONNECT, the resend buffer), spectators beyond the token lookup, statistics for the master
## server, or the shutdown's wait for the send buffers to drain (in-process there is nothing to drain).
## SendEntities sends one NET_NEW_ENTITY packet (the original splits at MAX_PACKET_SIZE bytes; same order).

const MAX_CLIENTS = 16
const RECONNECT_TIME = 60000
const SPECTATOR_TOKEN = ""

enum { psNone, psPreparing, psPlaying, psReconnecting, psDisconnected }  # EnumNetworkPlayerState
enum { qrNone, qrNormal, qrSurrendered, qrDisconnectedWhilePreparing, qrDisconnectedWhilePlaying, qrRageQuit }  # EnumPlayerQuitReason


class TNetworkPlayer:
	extends RefCounted
	const C = preload("res://src/runtime/dws/dws_const.gd")
	const BC = preload("res://src/runtime/base_conflict_constants.gd")
	var FNetworkComponent: WeakRef
	var State: int = psNone
	var QuitReason: int = qrNone
	var FSendedCount := 0
	var Token := ""
	var PlayerID := 0
	var TeamID := 0
	var FSocket: TLoopbackSocket = null
	var FReconnectTimer: TTimer

	func _init(Token_: String, PlayerID_: int, TeamID_: int, NetworkComponent) -> void:
		FReconnectTimer = TTimer.new().Create(RECONNECT_TIME)
		FNetworkComponent = weakref(NetworkComponent)
		Token = Token_
		PlayerID = PlayerID_
		TeamID = TeamID_

	func _Component():
		return FNetworkComponent.get_ref()

	func IsSpectator() -> bool:
		return Token == SPECTATOR_TOKEN

	## Set socket for player.
	func AssignSocket(Socket: TLoopbackSocket) -> void:
		# if socket already assigned, other player already used token
		assert(FSocket == null)
		var CommanderList = _Component().GlobalEventbus().Read(C.eiTokenMapping, [Token])
		if CommanderList != null:
			FSocket = Socket
			QuitReason = qrNormal
			State = psPreparing
			# send mappings
			var Data := TCommandSequence.new().Create(BC.NET_ASSIGNED_PLAYER)
			Data.AddDataArray(CommanderList)
			SendData(Data)
		else:
			_Component().RefuseConnection(Socket, Token)

	## Close connection to client.
	func Disconnect() -> void:
		if FSocket != null:
			FSocket.CloseConnection()
		State = psDisconnected

	func Idle() -> void:
		while FSocket != null and FSocket.IsDataPacketAvailable():
			ProcessNewData(FSocket.ReceiveDataPacket())
		# update player connection state
		if FSocket != null and FSocket.IsDisconnected() and State in [psNone, psPreparing, psPlaying]:
			# try to reconnect if player lost connection -> reconnect state
			if _Component().AllowReconnect:
				FReconnectTimer.Start()
				State = psReconnecting
			else:
				# connection is permanently lost, can not be recovered
				State = psDisconnected
				QuitReason = qrDisconnectedWhilePreparing
		elif State == psReconnecting and FReconnectTimer.Expired:
			# reconnect failed -> connection is permanently lost, can not be recovered
			State = psDisconnected
			QuitReason = qrDisconnectedWhilePlaying

	## Player has connected to server and connection is healthy (reconnect is also a healthy state).
	func IsConnected() -> bool:
		return State in [psPreparing, psPlaying, psReconnecting]

	func IsDisconnected() -> bool:
		return State == psDisconnected

	func ProcessNewData(Data: TCommandSequence) -> void:
		match Data.Command:
			BC.NET_CLIENT_ENTER_CORE:
				_Component().SendWorld(self)
			BC.NET_CLIENT_READY:
				State = psPlaying
			BC.NET_EVENT:
				# spectators must not send anything game relevant
				if not IsSpectator():
					_Component().NewData(Data)
			BC.NET_CLIENT_RAGE_QUIT:
				State = psDisconnected
				QuitReason = qrRageQuit
			_:
				push_error("Server retrieved unknown command \"%d\"." % Data.Command)

	func SendData(Data: TCommandSequence) -> void:
		# Piggyback current sended data index
		Data.AddData(FSendedCount)
		FSendedCount += 1
		if FSocket != null:
			FSocket.SendData(Data)
		Data.Data.pop_back()


var FAllowReconnect := false
## New clients connected to server, but not yet sended any token to assign them to player.
var FConnectedClients: Array = []  # of TLoopbackSocket
## List of all players. Is filled with data on creation.
var FPlayers: Array = []  # of TNetworkPlayer

## If true, player can try to reconnect to server after disconnect else any disconnect will be permanent.
var AllowReconnect: bool:
	get:
		return FAllowReconnect
	set(value):
		FAllowReconnect = value


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnSendEntities", C.eiSendEntities, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnServerShutdown", C.eiServerShutdown, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnSurrender", C.eiSurrender, C.epLast, C.etTrigger, C.esGlobal))


func Create(Owner = null, GameInformation = null) -> TEntityComponent:
	super(Owner)
	FConnectedClients = []
	FPlayers = []
	# hold data for every player that should connect to server
	# but skip bots as bots will never connect to game server as they are emulated by gameserver themself
	for PlayerData: TGamePlayer in GameInformation.Player.values():
		if not PlayerData.IsBot:
			FPlayers.append(TNetworkPlayer.new(PlayerData.Token, PlayerData.PlayerID, PlayerData.TeamID, self))
	return self


func Destroy() -> void:
	for Player: TNetworkPlayer in FPlayers:
		if Player.FSocket != null:
			Player.FSocket.CloseConnection()
	FPlayers = []
	FConnectedClients = []
	super()


## Returns the number of players connected.
func ConnectedPlayerCount() -> int:
	var Result := 0
	for Player: TNetworkPlayer in FPlayers:
		if Player.IsConnected():
			Result += 1
	return Result


func DisconnectAllPlayers() -> void:
	for Player: TNetworkPlayer in FPlayers:
		Player.Disconnect()


func GetPlayerByToken(Token: String) -> TNetworkPlayer:
	if Token != SPECTATOR_TOKEN:
		for Player: TNetworkPlayer in FPlayers:
			if Player.Token == Token:
				return Player
		return null
	# create new player specator or reuse disconnected spectator
	for Player: TNetworkPlayer in FPlayers:
		if Player.Token == Token and Player.IsDisconnected():
			return Player
	# accept new spectator only if not all slots already in use
	if FPlayers.size() <= MAX_CLIENTS:
		var Result := TNetworkPlayer.new(Token, 0, 0, self)
		FPlayers.append(Result)
		return Result
	return null


## A new connection (the original's TCP server socket accepted it); port: the server end of a TLoopbackSocket pair.
func OnClientConnect(ClientSocket: TLoopbackSocket) -> void:
	FConnectedClients.append(ClientSocket)


func OnSurrender(TeamID) -> bool:
	for Player: TNetworkPlayer in FPlayers:
		if Player.TeamID == RParam.AsInteger(TeamID) and Player.QuitReason in [qrNone, qrNormal]:
			Player.QuitReason = qrSurrendered
	return true


## Returns true if all players ready for game (in state playing).
func AllPlayersInStatePlaying() -> bool:
	for Player: TNetworkPlayer in FPlayers:
		if Player.State != psPlaying and not Player.IsSpectator():
			return false
	return true


## Returns true if all players connected.
func AllPlayersConnected() -> bool:
	for Player: TNetworkPlayer in FPlayers:
		if not Player.IsConnected() and not Player.IsSpectator():
			return false
	return true


## Return true if all players are disconnected.
func AllPlayersDisconnected() -> bool:
	for Player: TNetworkPlayer in FPlayers:
		if not Player.IsDisconnected() and not Player.IsSpectator():
			return false
	return true


## Return true if any players is disconnected. A player never connected to server counts NOT as disconnected.
func AnyPlayerDisconnected() -> bool:
	for Player: TNetworkPlayer in FPlayers:
		if Player.IsDisconnected() and not Player.IsSpectator():
			return true
	return false


## Compute.Send.Receive.
func OnIdle() -> bool:
	for i in range(FConnectedClients.size() - 1, -1, -1):
		var Socket: TLoopbackSocket = FConnectedClients[i]
		if Socket.IsDisconnected():
			FConnectedClients.remove_at(i)
		else:
			while Socket.IsDataPacketAvailable():
				var Deleted := ProcessNewData(Socket.ReceiveDataPacket(), Socket)
				if Deleted:
					break
	for Player: TNetworkPlayer in FPlayers:
		Player.Idle()
	return true


## Returns whether the Sender has been deleted.
func ProcessNewData(Data: TCommandSequence, Sender: TLoopbackSocket) -> bool:
	match Data.Command:
		BC.NET_HELLO_SERVER:
			var Token: String = Data.ReadString()
			var Player := GetPlayerByToken(Token)
			# refuse too much spectators
			if Player == null and Token == SPECTATOR_TOKEN:
				RefuseConnection(Sender, Token, 408)
			elif Player != null and Player.State == psNone:
				Player.AssignSocket(Sender)
			else:
				RefuseConnection(Sender, Token, 409)
			FConnectedClients.erase(Sender)
		_:
			push_error("Server unexpected unknown command \"%d\"." % Data.Command)
			Sender.CloseConnection()
	return false


func RefuseConnection(Connection: TLoopbackSocket, Token: String, ErrorCode: int = 400) -> void:
	var Data := TCommandSequence.new().Create(BC.NET_SECURITY_ERROR)
	Data.AddData(ErrorCode)
	var ErrorMessage := ""
	match ErrorCode:
		400:
			ErrorMessage = "Wrong token mapping"
		408:
			ErrorMessage = "Too much spectators"
		409:
			ErrorMessage = "Token already in use"
	Data.AddData(ErrorMessage + " Token: " + Token)
	Connection.SendData(Data)
	Connection.CloseConnection()


## Send the list of entities to all clients.
func OnSendEntities(Entities) -> bool:
	SendEntities(RParam.AsArray(Entities))
	return true


func OnServerShutdown() -> bool:
	return true


## Send data to any connected player.
func Send(Data: TCommandSequence) -> void:
	for Player: TNetworkPlayer in FPlayers:
		Player.SendData(Data)


## Port: packets are only built when a player has a connection.
func HasReceivers() -> bool:
	for Player: TNetworkPlayer in FPlayers:
		if Player.FSocket != null:
			return true
	return false


## Broadcast to any player connected abort command.
func SendAbort() -> void:
	Send(TCommandSequence.new().Create(BC.NET_SERVER_GAME_ABORTED))


## Send data to player. If player is null, data is sended to every player.
func SendDirectly(Data: TCommandSequence, Player: TNetworkPlayer) -> void:
	if Player == null:
		Send(Data)
	else:
		Player.SendData(Data)


## SendEntities(Entities) to every player, SendEntities(Entities, Receiver) to one.
func SendEntities(Entities: Array, Receiver: TNetworkPlayer = null) -> void:
	assert(Entities.size() >= 1)
	if Receiver == null and not HasReceivers():
		return
	var Data := TCommandSequence.new().Create(BC.NET_NEW_ENTITY)
	Data.AddData(Entities.size())
	for Entity: TEntity in Entities:
		var Stream := TEntityStream.new()
		Entity.Serialize(Stream)
		Data.AddStream(Stream)
	SendDirectly(Data, Receiver)


func SendWorld(Player: TNetworkPlayer) -> void:
	# send world
	var FilteredEntities: Array = []
	for Entity: TEntity in GlobalEventbus().Game.EntityManager.GetDeployedEntityList():
		if Entity.ScriptFile != "":
			FilteredEntities.append(Entity)
	if not FilteredEntities.is_empty():
		SendEntities(FilteredEntities, Player)
	Player.SendData(TCommandSequence.new().Create(BC.NET_SERVER_FINISHED_SEND_GAME_DATA))
