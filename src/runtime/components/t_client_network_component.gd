class_name TClientNetworkComponent
extends TNetworkComponent
## Port of TClientNetworkComponent (BaseConflict.EntityComponents.Client.pas:106, implementation :937), on the
## client's game entity (made by TClientGame): the client's side of the connection to the game server. Created with
## the socket the loading game state connected (TClientGame.ConnectToServer), it asks the server for the world
## (NET_CLIENT_ENTER_CORE). Each eiIdle it handles every received packet: NET_NEW_ENTITY deserializes the entities
## the client does not have yet (with a TLogicToWorldComponent, eiAfterCreate, Deploy), NET_EVENT invokes the event
## (TNetworkComponent.NewData), NET_SERVER_FINISHED_SEND_GAME_DATA calls the game back (token mapping), abort and
## security errors end the game; then it takes the server's time (Game.ServerTime). eiClientReady tells the server.
## Port notes: the socket is a TLoopbackSocket; no reconnect (thread, NET_RECONNECT_RESULT handling beyond the game
## state), ping log, bug reports to the account API, or the Ctrl+Alt debug disconnect keys.

var FSocket: TLoopbackSocket = null
var FAuthentificationToken := ""
var FLastReceivedIndex := -1
var FFinishedReceivedGameData: Callable


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnClientReady", C.eiClientReady, C.epLast, C.etTrigger, C.esGlobal))


func Create(Owner = null, Socket: TLoopbackSocket = null, AuthentificationToken: String = "", FinishedReceivedGameData: Callable = Callable()) -> TEntityComponent:
	super(Owner)
	FSocket = Socket
	FSocket.SendCommand(BC.NET_CLIENT_ENTER_CORE)
	FFinishedReceivedGameData = FinishedReceivedGameData
	FAuthentificationToken = AuthentificationToken
	return self


func Destroy() -> void:
	if FSocket != null:
		FSocket.CloseConnection()
	FSocket = null
	FFinishedReceivedGameData = Callable()  # it holds the game
	super()


func BeforeComponentFree() -> void:
	SendRageQuit()
	super()


func DeserializeEntity(Stream: TEntityStream) -> void:
	var EntityID: int = Stream.Read()
	var Game = GlobalEventbus().Game
	if not Game.EntityManager.HasEntityByID(EntityID):
		var Entity := TEntity.Deserialize(EntityID, Stream, GlobalEventbus())
		if Entity == null:
			return
		TLogicToWorldComponent.new().Create(Entity)
		Entity.Eventbus.Trigger(C.eiAfterCreate, [])
		Entity.Deploy()


func NewData(Data: TCommandSequence) -> void:
	var ClientGame = GlobalEventbus().Game
	match Data.Command:
		BC.NET_SERVER_FINISHED_SEND_GAME_DATA:
			if FFinishedReceivedGameData.is_valid():
				FFinishedReceivedGameData.call()
		BC.NET_NEW_ENTITY:
			var Count: int = Data.Read()
			for i in Count:
				DeserializeEntity(Data.ReadStream())
		BC.NET_SECURITY_ERROR:
			var ErrorCode: int = Data.Read()
			var ErrorMessage: String = Data.ReadString()
			push_warning("Connect to server failed: %d %s" % [ErrorCode, ErrorMessage])
			ClientGame.GameState = TClientGame.gsCrashed
		BC.NET_SERVER_GAME_ABORTED:
			ClientGame.GameState = TClientGame.gsAborted
		BC.NET_RECONNECT_RESULT:
			if Data.Read():
				ClientGame.GameState = TClientGame.gsRunning
			else:
				push_warning("Reconnect failed. Reason: " + Data.ReadString())
				ClientGame.GameState = TClientGame.gsCrashed
		_:
			super(Data)
	FLastReceivedIndex = Data.Read()


func OnClientReady() -> bool:
	if FSocket != null and FSocket.IsConnected():
		FSocket.SendCommand(BC.NET_CLIENT_READY)
	return true


func OnIdle() -> bool:
	while FSocket.IsDataPacketAvailable():
		NewData(FSocket.ReceiveDataPacket())
	var ClientGame = GlobalEventbus().Game
	if FSocket.Status == TLoopbackSocket.TCPStDisconnected:
		if ClientGame.GameState == TClientGame.gsPreparing:
			push_warning("Client lost connection to game server after loading and before token mapping.")
			ClientGame.GameState = TClientGame.gsCrashed
		elif ClientGame.GameState == TClientGame.gsRunning:
			# port: no reconnect
			ClientGame.GameState = TClientGame.gsCrashed
	# update servertime
	ClientGame.ServerTime = FSocket.GetCurrentPeerTime()
	return true


func Ping() -> int:
	return FSocket.Ping()


func Send(Data: TCommandSequence) -> void:
	assert(FSocket != null)
	FSocket.SendData(Data)


func SendRageQuit() -> void:
	var ClientGame = GlobalEventbus().Game
	if FSocket != null and FSocket.IsConnected() and ClientGame != null \
			and not ClientGame.GameState in [TClientGame.gsFinishing, TClientGame.gsFinished]:
		FSocket.SendData(TCommandSequence.new().Create(BC.NET_CLIENT_RAGE_QUIT))
