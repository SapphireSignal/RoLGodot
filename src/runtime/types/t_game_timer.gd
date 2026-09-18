class_name TGameTimer
extends TTimer
## Port of TGameTimer (BaseConflict.Types.Shared.pas:54, implementation :214): a TTimer on the game clock, with
## its start time exposed (StartingTime) so the server can send it to the client.
## Port note: the original reads GameTimeManager (server; a pausable clock per game) or Game.ServerTime (client).
## Both are TTimeManager's clock here until the game loop brings the per-game clock (phase 3).

var StartingTime: float:
	get:
		return FLastTime
	set(value):
		FLastTime = value


func GetTimeStamp() -> float:
	return TTimeManager.GetFloatingTimestamp()
