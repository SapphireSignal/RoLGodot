class_name TGameThread
extends TObject
## Port of TGameThread (GameServer/BaseConflict.Game.Server.pas:198, implementation :953): runs one server game.
## Create makes the TServerGame (after UpdateGamePlayers), its entity data cache and prepares it (the original's
## single-thread mode: PrepareGame at once): the per-game NOT_PAYED_RESOURCES default, then Initialize.
## DoComputeGame is one frame: TickTack, then (unless finished) Idle, the debug ticks and the player state machine
## (waiting for players -> running = Start); once the game is finished it terminates and fires eiServerShutdown.
## Port notes: there is no thread; the owner calls DoComputeGame every frame (the original's heartbeat aims at
## TARGET_FRAMETIME = 32 ms). The network parts (TServerNetworkComponent: connections, abort on disconnect or
## timeout, reporting the result to the master server, madExcept bug reports) wait for the client-server link;
## until then SetAllPlayersPlaying stands in for FNetworkComponent.AllPlayersInStatePlaying.

const C = preload("res://src/runtime/dws/dws_const.gd")

## THeartbeatManager.TARGET_FRAMETIME: the frame time the server aims at (ms).
const TARGET_FRAMETIME = 32

enum { gsWaitingForPlayers, gsRunning, gsAborted }  # EnumGameThreadState
enum { gfNone, gfCrashed, gfFinished, gfAborted }  # EnumGameFinishedState

var FServerGame: TServerGame = null
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


func Create(GameInformation = null) -> TGameThread:
	# final init game player data (TeamID and isBot)
	GameInformation.UpdateGamePlayers()
	FTimeSinceCreate = TTimer.new().CreateAndStart(1000)
	FServerGame = TServerGame.new().Create(GameInformation)
	FGameID = GameInformation.GameID
	TTimeManager.StartTickTack()
	FServerGame.GlobalEventbus.EntityDataCache = TEntityDataCache.new().Create(FServerGame.GlobalEventbus)
	PrepareGame()
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


## One frame of the game.
func DoComputeGame() -> void:
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
			if FAllPlayersPlaying:
				FState = gsRunning
				FServerGame.Start()
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
