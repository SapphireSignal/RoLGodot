class_name TGUITransitionValueSingle
extends RefCounted
## Port of TGUITransitionValue<T> / TGUITransitionValueSingle (Engine/Engine.GUI.pas:524, implementation :9130): a
## value that eases from where it is to a new target over Duration ms (TimeManager's clock) along TimingFunction.
## Setting the target it already has changes nothing; the first SetValue jumps.

var FInitialized := false
var FStartValue := 0.0
var FTargetValue := 0.0
var FStartingTimestamp := 0
var Duration := 0
var TimingFunction: RCubicBezier = RCubicBezier.LINEAR()


func CurrentFactor() -> float:
	if Duration <= 0:
		return 1.0
	return TimingFunction.Solve(clampf(float(TTimeManager.GetTimeStamp() - FStartingTimestamp) / Duration, 0.0, 1.0))


func SetValue(Value: float) -> void:
	if not FInitialized:
		FInitialized = true
		FStartValue = Value
		FTargetValue = Value
	if FTargetValue != Value:
		FStartValue = CurrentValue()
		FStartingTimestamp = TTimeManager.GetTimeStamp()
	FTargetValue = Value


## HMath.LinLerpF(start, target, factor) = X * (1 - s) + Y * s
func CurrentValue() -> float:
	var s := CurrentFactor()
	return FStartValue * (1 - s) + FTargetValue * s
