class_name TClientGame
extends TGame
## Part of TClientGame (BaseConflict.Game.Client.pas:36, implementation :79): the client's game on its own global
## bus (client side): the client map (with its decorations), collision and entity manager, the network component on
## the socket the loading game state connected, then Initialize runs the scenario scripts' client parts (e.g. the PvE
## scenarios' Game.ClientMap.AddDecoEntity). Entities and events come from the server over the network
## (TClientNetworkComponent); once the server has sent the world, the token mapping runs and the game is running.
## JoinLocal is the port's stand-in for the loading game state's connect (TGameStateLoadCoreGame: NET_HELLO_SERVER
## with the token, NET_ASSIGNED_PLAYER back) against an in-process game server; ReadyWhenLoaded stands in for the
## core game state's client-ready event once the game is ready.
## Not ported yet: input, camera, GUI, sound, commander manager (OnTokenMapping's eiNewCommander), the trace
## manager, minimap, the build grid manager and TClientEntityManagerComponent (the end screen).

enum { gsPreparing, gsRunning, gsReconnecting, gsAborted, gsCrashed, gsFinishing, gsFinished }  # EnumGameStatus

var FClientMap: TClientMap = null
var FClientNetworkComponent: TClientNetworkComponent = null
var FTokenMapping: Array = []
var FGameState: int = gsPreparing
var FSentReady := false
var DecayManager: TUnitDecayManagerComponent = null

var ClientMap: TClientMap:
	get:
		return FClientMap
var GameState: int:
	get:
		return FGameState
	set(value):
		FGameState = value


func Create(GameInfo_ = null, Socket: TLoopbackSocket = null, AuthentificationToken: String = "", TokenMapping: Array = []) -> TGame:
	var Bus := TEventbus.new().Create(null)
	Bus.ApplicationType = C.nsClient
	super(GameInfo_, Bus)
	FGameState = gsPreparing
	FTokenMapping = TokenMapping
	# the client's EntityDataCache is per process (BaseConflictMainUnit); the port keeps it on the global bus
	FGlobalEventbus.EntityDataCache = TEntityDataCache.new().Create(FGlobalEventbus)
	if FGameInfo.Scenario.MapName == "":
		push_error("TClientGame.Create: Mapname should not be empty!")
	else:
		FClientMap = TClientMap.CreateFromFile(FGameInfo.Scenario.MapName, FGlobalEventbus)
	CollisionManager = TCollisionManagerComponent.new().Create(GameEntity)
	FEntityManager = TEntityManagerComponent.new().Create(GameEntity)
	if Socket != null:
		FClientNetworkComponent = TClientNetworkComponent.new().Create(GameEntity, Socket, AuthentificationToken,
			FinishedReceiveGameData)
	DecayManager = TUnitDecayManagerComponent.new().Create(GameEntity)
	Initialize()
	return self


func Destroy() -> void:
	var Bus := FGlobalEventbus
	if FClientMap != null:
		FClientMap.FreeDecorations()
		if FClientMap.is_inside_tree():
			FClientMap.queue_free()
		else:
			FClientMap.free()
		FClientMap = null
	FClientNetworkComponent = null
	super()
	Bus.Free()


## Port: connects to an in-process game server as the loading game state does (a new connection, NET_HELLO_SERVER
## with the token, the server's next frame answers NET_ASSIGNED_PLAYER with the token's commanders), then makes the
## client game on that connection. Returns null if the server refused the token.
static func JoinLocal(GameThread: TGameThread, GameInfo_: TGameInformation, AuthentificationToken: String) -> TClientGame:
	var Sockets := TLoopbackSocket.CreatePair()
	GameThread.NetworkComponent.OnClientConnect(Sockets[0])
	var Socket: TLoopbackSocket = Sockets[1]
	var Hello := TCommandSequence.new().Create(BC.NET_HELLO_SERVER)
	Hello.AddData(AuthentificationToken)
	Socket.SendData(Hello)
	GameThread.DoComputeGame()
	var TokenMapping = null
	while Socket.IsDataPacketAvailable():
		var DataPacket := Socket.ReceiveDataPacket()
		match DataPacket.Command:
			BC.NET_ASSIGNED_PLAYER:
				TokenMapping = DataPacket.ReadList()
			BC.NET_SECURITY_ERROR:
				push_warning("TClientGame.JoinLocal: connection refused: %d %s" % [DataPacket.Read(), DataPacket.ReadString()])
				return null
	if TokenMapping == null:
		push_warning("TClientGame.JoinLocal: the server assigned no player")
		return null
	return TClientGame.new().Create(GameInfo_, Socket, AuthentificationToken, TokenMapping)


## The network got the whole game data: token mapping, then the game runs.
func FinishedReceiveGameData() -> void:
	OnTokenMapping(FTokenMapping)


## TClientGame.OnTokenMapping: the commanders go to the commander manager (not ported yet), then the game runs.
func OnTokenMapping(_TokenMapping: Array) -> void:
	FGameState = gsRunning


## TClientGame.Idle: the map, then TGame.Idle.
func Idle() -> void:
	super()


func IsFinished() -> bool:
	return FGameState in [gsAborted, gsCrashed, gsFinished]


func IsReady() -> bool:
	return FGameState != gsPreparing


func IsRunning() -> bool:
	return FGameState in [gsPreparing, gsRunning, gsReconnecting]


## Port stand-in for TGameStateCoreGame: once the game is ready (world received) it says so once, as the core game
## state's GAME_EVENT_CLIENT_READY does (eiClientReady -> NET_CLIENT_READY: the server starts the game).
func ReadyWhenLoaded() -> void:
	if not FSentReady and IsReady():
		FGlobalEventbus.Trigger(C.eiClientReady, [])
		FSentReady = true


func Ping() -> int:
	return FClientNetworkComponent.Ping()
