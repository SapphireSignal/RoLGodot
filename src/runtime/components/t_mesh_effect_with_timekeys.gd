class_name TMeshEffectWithTimekeys
extends TMeshEffectGeneric
## Port of TMeshEffectWithTimekeys (BaseConflict.EntityComponents.Client.Visuals.pas:525, implementation :5983): an
## effect that runs for a duration (0 or less: 10000000 ms) and expires then; its values follow timelines of
## (time ms, value) keys, interpolated linearly over the duration (HMath.Interpolate), or 1 - progress without keys.


var FTimer: TTimer = null
## Timelines: Arrays of [time key (ms), value].
var FTimedKeyPoints: Array = []


## HMath.Interpolate(TimeKeys, Progress, imLinear, TimeRange) with GetInterpolationKeys: the key pair around
## progress * TimeRange (the last key's time when TimeRange <= 0), searched from the end for the first key before it.
## Port: at a time no key lies before (time 0 with a first key at 0), the original's release build reads uninitialized
## values (the assert is off); the port takes the first key's value.
static func Interpolate(TimeKeys: Array, Progress: float, TimeRange: int) -> float:
	if TimeKeys.is_empty():
		return 0.0
	if TimeKeys.size() == 1:
		return TimeKeys[0][1]
	var TimeSpan: int = TimeKeys[TimeKeys.size() - 1][0]
	var CurrentTime := clampf(Progress, 0.0, 1.0) * (TimeRange if TimeRange > 0 else TimeSpan)
	for i in range(TimeKeys.size() - 1, -1, -1):
		if CurrentTime > TimeKeys[i][0]:
			var endIndex := mini(i + 1, TimeKeys.size() - 1)
			var localFactor := 0.0
			if i != endIndex:
				localFactor = (CurrentTime - TimeKeys[i][0]) / float(TimeKeys[endIndex][0] - TimeKeys[i][0])
			return lerpf(TimeKeys[i][1], TimeKeys[endIndex][1], localFactor)
	return TimeKeys[0][1]


func Create(Duration = null, _Param1 = null):
	super("", "")
	var d := 0 if Duration == null else int(Duration)
	if d <= 0:
		d = 10000000
	FTimer = TTimer.new().CreateAndStart(d)
	FTimedKeyPoints = [[]]
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result: TMeshEffect = _NewOfMyClass().CreateEmpty() if Effect == null else Effect
	Result = super(Result)
	Result.FTimer = FTimer.Clone()
	Result.FTimedKeyPoints = []
	for timeline: Array in FTimedKeyPoints:
		Result.FTimedKeyPoints.append(timeline.duplicate(true))
	return Result


func AddKey(TimeKey = null, Value = null):
	FTimedKeyPoints[FTimedKeyPoints.size() - 1].append([int(TimeKey), RParam.ToSingle(Value)])
	return self


func AddNextTimeLine():
	FTimedKeyPoints.append([])
	return self


## MaxInt
func AddPermaKey(Value = null):
	AddKey(0, Value)
	AddKey(2147483647, Value)
	return self


func CurrentValue(Index := 0) -> float:
	assert(Index < FTimedKeyPoints.size(), "TMeshEffectWithTimekeys.CurrentValue: Not enough timelines!")
	var TimedKeyPoints: Array = FTimedKeyPoints[Index]
	if not TimedKeyPoints.is_empty():
		return Interpolate(TimedKeyPoints, FTimer.ZeitDiffProzent(true), FTimer.Interval)
	return 1.0 - FTimer.ZeitDiffProzent(true)


func HasTimeLine(Index: int) -> bool:
	return FTimedKeyPoints.size() > Index


func Expired() -> bool:
	return super() or FTimer.Expired


func Reset() -> void:
	super()
	FTimer.Start()
