class_name TGameThread
extends TObject
## Port of TGameThread (GameServer/BaseConflict.Game.Server.pas:198, implementation :953): runs one server game.
## Create makes the TServerGame (after UpdateGamePlayers), its TServerNetworkComponent, its entity data cache and
## prepares it (the original's single-thread mode: PrepareGame at once): the per-game NOT_PAYED_RESOURCES default,
## then Initialize.
## DoComputeGame is one frame: TickTack, then (unless finished) Idle, the debug ticks and the player state machine
## (waiting for players: all playing -> running = Start, one disconnected or not all connected within TIMEOUT_TIME
## -> aborted; aborted: abort sent, players disconnected, terminated after TIMEOUT_TIME; running: all players gone ->
## crashed); once the game is finished it terminates and fires eiServerShutdown.
## Threads: the game's threadvars live in its own TThreadContext (FContext: clock, current event, NOT_PAYED_RESOURCES,
## ...). StartThread runs it like the original's Execute on a real thread (DoComputeGame at the THeartbeatManager
## heartbeat, TARGET_FRAMETIME = 32 ms) until Terminated or StopThread: then a client in the same process (the map
## viewer) draws without waiting for server frames. Without the thread the owner calls DoComputeGame (tests, headless
## matches, a client joining before the thread starts): it swaps FContext in on the calling main thread. While the
## thread runs, only the network (TLoopbackSocket) and the thread-safe flags cross over.
## Not ported: reporting the result to the master server, madExcept bug reports, the abort's one second sleep.
## SetAllPlayersPlaying lets headless runs without clients start the game.

const C = preload("res://src/runtime/dws/dws_const.gd")

## THeartbeatManager.TARGET_FRAMETIME: the frame time the server aims at (ms).
const TARGET_FRAMETIME = 32
## Players must have connected within this time (ms), and an aborted game ends after it.
const TIMEOUT_TIME = 30 * 1000

enum { gsWaitingForPlayers, gsRunning, gsAborted }  # EnumGameThreadState
enum { gfNone, gfCrashed, gfFinished, gfAborted }  # EnumGameFinishedState

var FServerGame: TServerGame = null
var FNetworkComponent: TServerNetworkComponent = null
## The game's threadvars (see TThreadContext)
var FContext := TThreadContext.new()
var FThread: Thread = null
var FStopRequested := false
## the thread's frame times (ms): the last one and the slowest since the thread started
var LastFrameMs := 0.0
var WorstFrameMs := 0.0
## frames computed on the thread, and its OS thread id (tests)
var ThreadFrames := 0
var ThreadID := -1
var ErrorMsg := ""
var FTicksToGo := 0
var FGameID := ""
var FGameFinishedState: int = gfNone
var FTimeSinceCreate: TTimer = null
var FState: int = gsWaitingForPlayers
var FAllPlayersPlaying := false
var Terminated := false

## Direct access to the game.
var InternalGame: TServerGame:
	get:
		return FServerGame
var GameID: String:
	get:
		return FGameID
var State: int:
	get:
		return FState
var GameFinishedState: int:
	get:
		return FGameFinishedState
var NetworkComponent: TServerNetworkComponent:
	get:
		return FNetworkComponent


func Create(GameInformation = null) -> TGameThread:
	# final init game player data (TeamID and isBot)
	var Outer := TThreadContext.Enter(FContext)
	GameInformation.UpdateGamePlayers()
	FTimeSinceCreate = TTimer.new().CreateAndStart(1000)
	FServerGame = TServerGame.new().Create(GameInformation)
	FNetworkComponent = TServerNetworkComponent.new().Create(FServerGame.GameEntity, GameInformation)
	FGameID = GameInformation.GameID
	TThreadContext.Current().GameTimeManager.StartTickTack()
	FServerGame.GlobalEventbus.EntityDataCache = TEntityDataCache.new().Create(FServerGame.GlobalEventbus)
	PrepareGame()
	TThreadContext.Leave(Outer)
	return self


func Destroy() -> void:
	StopThread()
	if FServerGame != null:
		var Outer := TThreadContext.Enter(FContext)
		FServerGame.Free()
		FServerGame = null
		TThreadContext.Leave(Outer)
	super()


## TGameThread.Execute on its own thread: frames at the heartbeat until Terminated or StopThread. The caches the
## game fills lazily and shares (card and scenario databases) are made first; the thread waits until its context
## is registered.
func StartThread() -> void:
	if FThread != null:
		return
	TCardInfoManager.Instance()
	TScenarioInfoManager.Instance()
	FStopRequested = false
	var Ready := Semaphore.new()
	var Go := Semaphore.new()
	var IDs := []
	FThread = Thread.new()
	FThread.start(_Execute.bind(Ready, Go, IDs), Thread.PRIORITY_HIGH)
	Ready.wait()
	TThreadContext.RegisterThread(IDs[0], FContext)
	Go.post()


## Stops the thread after its current frame and waits for it.
func StopThread() -> void:
	if FThread == null:
		return
	FStopRequested = true
	FThread.wait_to_finish()
	FThread = null


func IsThreadRunning() -> bool:
	return FThread != null and FThread.is_alive()


func _Execute(Ready: Semaphore, Go: Semaphore, IDs: Array) -> void:
	var ID := OS.get_thread_caller_id()
	IDs.append(ID)
	Ready.post()
	Go.wait()
	ThreadID = ID
	var NextFrame := Time.get_ticks_usec()
	while not Terminated and not FStopRequested:
		var Start := Time.get_ticks_usec()
		_ComputeFrame()
		ThreadFrames += 1
		LastFrameMs = (Time.get_ticks_usec() - Start) / 1000.0
		WorstFrameMs = maxf(WorstFrameMs, LastFrameMs)
		# THeartbeatManager: the next frame TARGET_FRAMETIME after this one started (no catching up after a slow one)
		NextFrame = maxi(NextFrame + TARGET_FRAMETIME * 1000, Time.get_ticks_usec())
		while not FStopRequested and Time.get_ticks_usec() < NextFrame:
			OS.delay_usec(mini(1000, NextFrame - Time.get_ticks_usec()))
	TThreadContext.UnregisterThread(ID)


func PrepareGame() -> void:
	TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES.duplicate()
	# after setup, game need some init code
	FServerGame.Initialize()

	if FServerGame.IsPerformanceTest():
		FState = gsRunning
		FServerGame.Start()


## Port: the server's listening socket accepting a local connection (before the thread starts: it runs on the
## calling thread in the game's context).
func ConnectClient(Socket: TLoopbackSocket) -> void:
	assert(FThread == null, "TGameThread.ConnectClient: connect before StartThread")
	var Outer := TThreadContext.Enter(FContext)
	FNetworkComponent.OnClientConnect(Socket)
	TThreadContext.Leave(Outer)


## The port's stand-in for the network: all players have loaded and play.
func SetAllPlayersPlaying() -> void:
	FAllPlayersPlaying = true


## One frame of the game (the thread's loop runs it while not Terminated).
func DoComputeGame() -> void:
	if Terminated:
		return
	assert(FThread == null, "TGameThread.DoComputeGame: the game runs on its own thread")
	var Outer := TThreadContext.Enter(FContext)
	_ComputeFrame()
	TThreadContext.Leave(Outer)


func _ComputeFrame() -> void:
	# pre setup
	TThreadContext.Current().GameTimeManager.TickTack()
	if not FServerGame.IsFinished:
		# do the hot stuff, idle game
		FServerGame.Idle()
		# debug ticking
		for tick in FTicksToGo:
			FServerGame.GlobalEventbus.Trigger(C.eiGameTick, [])
		FTicksToGo = 0

		if FState == gsWaitingForPlayers:
			if FAllPlayersPlaying or FNetworkComponent.AllPlayersInStatePlaying():
				FState = gsRunning
				FNetworkComponent.AllowReconnect = true
				FServerGame.Start()
			elif FNetworkComponent.AnyPlayerDisconnected():
				FState = gsAborted
				ErrorMsg = "A player lost connection during loading."
			elif TimeSinceCreate() >= TIMEOUT_TIME and not FNetworkComponent.AllPlayersConnected():
				FState = gsAborted
				ErrorMsg = "Not all players connected within 30s."

		if FState == gsAborted:
			# inform all connected players that game is aborted
			FNetworkComponent.SendAbort()
			# and bye bye players
			FNetworkComponent.DisconnectAllPlayers()
			# waiting time give user oppurtunity to get info that game is aborted, but after some time is needed to be killed
			if TimeSinceCreate() >= TIMEOUT_TIME:
				FGameFinishedState = gfAborted
				Terminated = true

		if FState == gsRunning:
			# all disconnected -> kill game
			if not FServerGame.IsPerformanceTest() and not FAllPlayersPlaying and FNetworkComponent.AllPlayersDisconnected():
				FGameFinishedState = gfCrashed
				Terminated = true
				ErrorMsg = "All players are disconnected."
	else:
		Terminated = true
		FGameFinishedState = gfFinished
		FServerGame.GlobalEventbus.Trigger(C.eiServerShutdown, [])


## Force a game tick at the next frame.
func SendGameTick() -> void:
	FTicksToGo += 1


## The milliseconds since creation.
func TimeSinceCreate() -> int:
	return int(FTimeSinceCreate.TimeSinceStart())
