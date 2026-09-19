class_name TWelaHelperActivateTimerComponent
extends TGDEntityComponent
## Port of TWelaHelperActivateTimerComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:811,
## implementation :3006), server only. At the first global eiIdle after its timer (started at creation, 1 ms, or
## Delay ms: setting the interval keeps the start) expired, writes eiWelaActive := True to its group and frees
## itself.

var FTimer: TTimer = null


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epLast, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FTimer = TTimer.new().CreateAndStart(1)
	return self


func Destroy() -> void:
	if FTimer != null:
		FTimer.Free()
	FTimer = null
	super()


func Delay(Duration: int = 0) -> TWelaHelperActivateTimerComponent:
	FTimer.Interval = Duration
	return self


## Activate this weapon if timer expired.
func OnIdle() -> bool:
	if FTimer.Expired:
		Eventbus().Write(C.eiWelaActive, [true], ComponentGroup)
		Free()
	return true
