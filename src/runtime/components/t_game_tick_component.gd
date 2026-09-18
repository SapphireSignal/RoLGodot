class_name TGameTickComponent
extends TEntityComponent
## Port of TGameTickComponent (BaseConflict.EntityComponents.Shared.pas:356, implementation :1986), on the game
## entity: the game's tick clock. eiGameCommencing starts the warm-up (GAME_WARMING_DURATION); on the server each
## eiIdle fires eiGameTick when the timer has run out, and every eiGameTick restarts it with GAME_TICK_DURATION and
## counts up. The first tick also fires eiGameStart (server). Answers eiGameTickTimeToFirstTick (ms left of the
## warm-up, 0 once ticking) and eiGameTickCounter.

const BC = preload("res://src/runtime/base_conflict_constants.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")

var FTickTimer: TTimer
var FTickCounter := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameCommencing", C.eiGameCommencing, C.epMiddle, C.etTrigger, C.esGlobal))
	if IsServerSide():
		e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnGameTick", C.eiGameTick, C.epHigher, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnGetTimeToFirstTick", C.eiGameTickTimeToFirstTick, C.epFirst, C.etRead, C.esGlobal))
	e.append(XEvent("OnGetGameTickCounter", C.eiGameTickCounter, C.epFirst, C.etRead, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	FTickTimer = TTimer.new().CreatePaused(BC.GAME_WARMING_DURATION)
	super(Owner, Group)
	return self


func OnGameCommencing() -> bool:
	if FTickTimer.Paused:
		FTickTimer.SetIntervalAndStart(BC.GAME_WARMING_DURATION)
	return true


func OnGetTimeToFirstTick(_Previous):
	var Result := 0
	if FTickCounter <= 0:
		Result = L.Round(FTickTimer.TimeToExpired())
	return Result


func OnGetGameTickCounter(_Previous):
	return FTickCounter


func OnIdle() -> bool:
	if FTickTimer.Expired:
		GlobalEventbus().Trigger(C.eiGameTick, [])
	return true


func OnGameTick() -> bool:
	if IsServerSide() and FTickCounter <= 0:
		GlobalEventbus().Trigger(C.eiGameStart, [])
	FTickTimer.SetIntervalAndStart(BC.GAME_TICK_DURATION)
	FTickCounter += 1
	return true
