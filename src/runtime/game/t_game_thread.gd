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
## Port notes: there is no thread; the owner calls DoComputeGame every frame until Terminated (the original's
## heartbeat aims at TARGET_FRAMETIME = 32 ms). The game has its own clock (the original's per-thread
## GameTimeManager): DoComputeGame swaps its LastTickTime / ZDiff into TTimeManager and back out, so a client in the
## same process keeps its own frame times. Not ported: reporting the result to the master server, madExcept bug
## reports, the abort's one second sleep. SetAllPlayersPlaying lets headless runs without clients start the game.

const C = preload("res://src/runtime/dws/dws_const.gd")

## THeartbeatManager.TARGET_FRAMETIME: the frame time the server aims at (ms).
const TARGET_FRAMETIME = 32
## Players must have connected within this time (ms), and an aborted game ends after it.
const TIMEOUT_TIME = 30 * 1000

enum { gsWaitingForPlayers, gsRunning, gsAborted }  # EnumGameThreadState
enum { gfNone, gfCrashed, gfFinished, gfAborted }  # EnumGameFinishedState

var FServerGame: TServerGame = null
var FNetworkComponent: TServerNetworkComponent = null
var FClock: Array = []  # the game's TTimeManager.SaveClock
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
	GameInformation.UpdateGamePlayers()
	FTimeSinceCreate = TTimer.new().CreateAndStart(1000)
	FServerGame = TServerGame.new().Create(GameInformation)
	FNetworkComponent = TServerNetworkComponent.new().Create(FServerGame.GameEntity, GameInformation)
	FGameID = GameInformation.GameID
	var OuterClock := TTimeManager.SaveClock()
	TTimeManager.StartTickTack()
	FServerGame.GlobalEventbus.EntityDataCache = TEntityDataCache.new().Create(FServerGame.GlobalEventbus)
	PrepareGame()
	FClock = TTimeManager.SaveClock()
	TTimeManager.RestoreClock(OuterClock)
	return self


func Destroy() -> void:
	if FServerGame != null:
		FServerGame.Free()
		FServerGame = null
	super()


func PrepareGame() -> void:
	TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES.duplicate()
	# after setup, game need some init code
	FServerGame.Initialize()

	if FServerGame.IsPerformanceTest():
		FState = gsRunning
		FServerGame.Start()


## The port's stand-in for the network: all players have loaded and play.
func SetAllPlayersPlaying() -> void:
	FAllPlayersPlaying = true


## One frame of the game (the thread's loop runs it while not Terminated).
func DoComputeGame() -> void:
	if Terminated:
		return
	var OuterClock := TTimeManager.SaveClock()
	TTimeManager.RestoreClock(FClock)
	_ComputeFrame()
	FClock = TTimeManager.SaveClock()
	TTimeManager.RestoreClock(OuterClock)


func _ComputeFrame() -> void:
	# pre setup
	TTimeManager.TickTack()
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
