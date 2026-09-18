class_name TAutoBrainOnDeathComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnDeathComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:628,
## implementation :2248), server only. At eiDie [KillerID, KillerCommanderID] (epLast) remembers the killer and runs
## CheckAndFire (default target: the dying owner).
## Quirk kept: FireAtKiller overrides the original's parameterless Fire, but CheckAndFire calls the other overload
## (FireTargets here), so FireAtKiller never changes the target of a death (used once, the HighlyExplosiveBuff
## mutator: it fires at the dying unit).

var FFireAtKiller := false
var FKillerID := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))


func Fire() -> void:
	if FFireAtKiller:
		var Target := ATarget.Make(FKillerID)
		if not _TargetsPossible(ATarget.ToRParam(Target), FFireGroup):
			return
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], FFireGroup)
	else:
		super()


## Fires at the killer of this unit (see the quirk above).
func FireAtKiller() -> TAutoBrainOnDeathComponent:
	FFireAtKiller = true
	return self


func OnDie(KillerID, _KillerCommanderID) -> bool:
	FKillerID = RParam.AsInteger(KillerID)
	CheckAndFire()
	return true
