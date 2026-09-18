class_name TWelaReadyNthComponent
extends TWelaReadyComponent
## Port of TWelaReadyNthComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:215, implementation
## :2416), server only. Every readiness check counts up (from Counter, default 0); ready on each Nth check (Invert:
## except each Nth), and with Times only while the count is <= Times. Nth / Times of 0 are off.

var FInvert := false
var FCounter := 0
var FNth := 0
var FTimes := 0


func IsReady() -> bool:
	FCounter += 1
	var Result := true
	if FNth > 0:
		if FInvert:
			Result = Result and (FCounter % FNth) != 0
		else:
			Result = Result and (FCounter % FNth) == 0
	if FTimes > 0:
		Result = Result and FCounter <= FTimes
	return Result


## Is only ready each nth time.
func Nth(Nth_: int) -> TWelaReadyNthComponent:
	FNth = Nth_
	return self


## Initializes the counter with another value than 0.
func Counter(Counter_: int) -> TWelaReadyNthComponent:
	FCounter = Counter_
	return self


## Is ready the first n times.
func Times(Times_: int) -> TWelaReadyNthComponent:
	FTimes = Times_
	return self


## Is ready except each nth time.
func Invert() -> TWelaReadyNthComponent:
	FInvert = true
	return self
