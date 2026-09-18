class_name TTimer
extends TObject
## Port of TTimer (Engine/Engine.Helferlein.Windows.pas:985, implementation :2013): a millisecond countdown on
## TTimeManager's clock. A timer made with Create(Interval) starts expired; CreateAndStart starts it now.

const L = preload("res://src/runtime/dws/dws_lib.gd")

var FInterval := 1
var FLastTime := 0.0
var FPauseTime := 0.0
var FPaused := false

var Interval: int:
	get:
		return FInterval
	set(value):
		SetInterval(value)

var Paused: bool:
	get:
		return FPaused
	set(value):
		setPaused(value)

## Whether the interval has passed since the last Start.
var Expired: bool:
	get:
		return getExpired()
	set(value):
		setExpired(value)


## Create / Create(Interval): initially expired.
func Create(NewInterval = null) -> TObject:
	SetInterval(1 if NewInterval == null else int(NewInterval))
	return self


func CreateAndStart(NewInterval: int) -> TTimer:
	Create(NewInterval)
	Start()
	return self


func CreatePaused(NewInterval: int) -> TTimer:
	CreateAndStart(NewInterval)
	Pause()
	return self


func Clone() -> TTimer:
	var Result := TTimer.new()
	Result.Create()
	Result.FInterval = FInterval
	Result.FLastTime = FLastTime
	Result.FPauseTime = FPauseTime
	Result.FPaused = FPaused
	return Result


func Delay(DelayMs: int) -> void:
	FLastTime = FLastTime + DelayMs


func Expire() -> void:
	Expired = true


func getExpired() -> bool:
	if FPaused:
		return FPauseTime >= FInterval
	return GetTimeStamp() - FLastTime >= FInterval


func GetTimeStamp() -> float:
	return TTimeManager.GetFloatingTimestamp()


func HasStarted() -> bool:
	return FLastTime >= GetTimeStamp()


func setExpired(IsExpired: bool) -> void:
	const EPSILON = 1E-7
	if IsExpired:
		if FPaused:
			FPauseTime = FInterval
		else:
			FLastTime = GetTimeStamp() - FInterval - EPSILON  # due to rounding errors we go slightly beyond expired
	else:
		var WasPaused := FPaused
		Start()
		if WasPaused:
			Pause()


func ZeitDiffProzent(ClampZeroOne: bool = false) -> float:
	var Result := 1.0 if FInterval == 0 else RParam.ToSingle(TimeSinceStart() / FInterval)
	if ClampZeroOne:
		Result = clampf(Result, 0, 1)
	return Result


func ZeitDiffProzentInverted(ClampZeroOne: bool = false) -> float:
	return RParam.ToSingle(1 - ZeitDiffProzent(ClampZeroOne))


## Start / Start(NewInterval): restart the timer to zero and unpause it.
func Start(NewInterval = null) -> void:
	if NewInterval != null:
		Interval = NewInterval
	FLastTime = GetTimeStamp()
	FPaused = false


func StartAndPause() -> void:
	Start()
	Pause()


func StartWithRest() -> void:
	FLastTime = GetTimeStamp() - L.Round((mini(0, int(ZeitDiffProzent()) - 1) + _Frac(ZeitDiffProzent())) * FInterval)
	FPaused = false


func StartWithFrac() -> void:
	FLastTime = GetTimeStamp() - L.Round(_Frac(ZeitDiffProzent()) * FInterval)
	FPaused = false


func TimesExpired(Maximum: int = -1) -> int:
	var Result := int(ZeitDiffProzent())
	if Maximum > 0:
		Result = mini(Result, Maximum)
	return Result


func TimeSinceStart() -> float:
	var Result := FPauseTime if FPaused else GetTimeStamp() - FLastTime
	return maxf(0, Result)


func TimeToExpired() -> float:
	return RParam.ToSingle(maxf(0, (1 - ZeitDiffProzent()) * Interval))


func Pause() -> void:
	FPaused = true
	FPauseTime = GetTimeStamp() - FLastTime


func Progress() -> float:
	var Result := 1.0 if FInterval == 0 else RParam.ToSingle(TimeSinceStart() / FInterval)
	return clampf(Result, 0, 1)


func ProgressInverted() -> float:
	return RParam.ToSingle(1 - Progress())


func Reset() -> void:
	SetZeitDiffProzent(0)


## Weiter: a paused timer runs on, time stays consistent.
func Weiter() -> void:
	if FPaused:
		FPaused = false
		FLastTime = GetTimeStamp() - FPauseTime


func SetInterval(NewInterval: int) -> void:
	FInterval = maxi(1, NewInterval)


func SetIntervalAndStart(NewInterval: int) -> void:
	SetInterval(NewInterval)
	Start()


## Kept as in the original, which is inverted: Paused := True on a running timer calls Weiter (no-op),
## Paused := False on a paused timer calls Pause again.
func setPaused(IsExpired: bool) -> void:
	if Paused != IsExpired:
		if IsExpired:
			Weiter()
		else:
			Pause()


func SetZeitDiffProzent(Wert: float) -> void:
	if Paused:
		FPauseTime = Wert * FInterval
	else:
		FLastTime = GetTimeStamp() - Wert * FInterval


## Delphi Frac: the fractional part, sign kept.
static func _Frac(x: float) -> float:
	return x - float(int(x))
