class_name TTimeManager
extends RefCounted
## Port of the TTimeManager clock (Engine/Engine.Helferlein.Windows.pas:2214): milliseconds since program start.
## Only the timestamps for now; the global pause (SetPause) and TickTack come with the game loop in phase 3.
## Tests freeze the clock with FakeTime (milliseconds, a float), null = the real clock.

const L = preload("res://src/runtime/dws/dws_lib.gd")

static var FakeTime = null


## GetFloatingTimestamp: milliseconds as a double.
static func GetFloatingTimestamp() -> float:
	if FakeTime != null:
		return float(FakeTime)
	return Time.get_ticks_usec() / 1000.0


## GetTimeStamp: whole milliseconds (Round).
static func GetTimeStamp() -> int:
	return L.Round(GetFloatingTimestamp())
