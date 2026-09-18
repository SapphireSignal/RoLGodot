class_name TTimeManager
extends RefCounted
## Port of the TTimeManager clock (Engine/Engine.Helferlein.Windows.pas:2214): milliseconds since program start.
## Every TTimeManager of the original reads the same clock; the server game's GameTimeManager only adds its own
## ZDiff (TickTack). The port runs one game at a time, so this is static. The pause (SetPause) is not ported yet.
## Tests freeze the clock with FakeTime (milliseconds, a float), null = the real clock.

const L = preload("res://src/runtime/dws/dws_lib.gd")

static var FakeTime = null
## ZDiff: milliseconds between the last two TickTacks (a single). The original's per-game GameTimeManager.ZDiff;
## TGameThread's frame sets it, tests may set it by hand.
static var ZDiff := 0.0
## LetzteZeit: the time of the last TickTack (StartTickTack: the time manager's creation).
static var LastTickTime := 0.0


## The TTimeManager constructor's part: TickTack measures from now.
static func StartTickTack() -> void:
	LastTickTime = GetFloatingTimestamp()


## Call every frame: ZDiff = milliseconds since the last TickTack.
static func TickTack() -> void:
	var Now := GetFloatingTimestamp()
	ZDiff = RParam.ToSingle(Now - LastTickTime)
	LastTickTime = Now


## GetFloatingTimestamp: milliseconds as a double.
static func GetFloatingTimestamp() -> float:
	if FakeTime != null:
		return float(FakeTime)
	return Time.get_ticks_usec() / 1000.0


## GetTimeStamp: whole milliseconds (Round).
static func GetTimeStamp() -> int:
	return L.Round(GetFloatingTimestamp())
