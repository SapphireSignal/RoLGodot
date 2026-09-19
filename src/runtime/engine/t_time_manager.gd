class_name TTimeManager
extends RefCounted
## Port of the TTimeManager clock (Engine/Engine.Helferlein.Windows.pas:2214): milliseconds since program start.
## Every TTimeManager of the original reads the same clock; the server game's GameTimeManager only adds its own
## ZDiff (TickTack). The port keeps the clock static; the frame state (ZDiff, LastTickTime) is per thread like the
## original's threadvar GameTimeManager (TThreadContext: a server game's context has its own). The pause (SetPause)
## is not ported yet.
## Tests freeze the clock with FakeTime (milliseconds, a float), null = the real clock.

const L = preload("res://src/runtime/dws/dws_lib.gd")

static var FakeTime = null
## ZDiff: milliseconds between the last two TickTacks (a single). The original's per-game GameTimeManager.ZDiff;
## TGameThread's frame sets it, tests may set it by hand.
static var ZDiff: float:
	get:
		return TThreadContext.Current().ZDiff
	set(value):
		TThreadContext.Current().ZDiff = value
## LetzteZeit: the time of the last TickTack (StartTickTack: the time manager's creation).
static var LastTickTime: float:
	get:
		return TThreadContext.Current().LastTickTime
	set(value):
		TThreadContext.Current().LastTickTime = value


## The TTimeManager constructor's part: TickTack measures from now.
static func StartTickTack() -> void:
	LastTickTime = GetFloatingTimestamp()


## Call every frame: ZDiff = milliseconds since the last TickTack.
static func TickTack() -> void:
	var Now := GetFloatingTimestamp()
	ZDiff = RParam.ToSingle(Now - LastTickTime)
	LastTickTime = Now


## Port: the frame state of one time manager ([LastTickTime, ZDiff]). A server game in the same process as a client
## keeps its own (the original's per-thread GameTimeManager); TGameThread swaps it in for its frame.
static func SaveClock() -> Array:
	return [LastTickTime, ZDiff]


static func RestoreClock(Clock: Array) -> void:
	LastTickTime = Clock[0]
	ZDiff = Clock[1]


## GetFloatingTimestamp: milliseconds as a double.
static func GetFloatingTimestamp() -> float:
	if FakeTime != null:
		return float(FakeTime)
	return Time.get_ticks_usec() / 1000.0


## GetTimeStamp: whole milliseconds (Round).
static func GetTimeStamp() -> int:
	return L.Round(GetFloatingTimestamp())
