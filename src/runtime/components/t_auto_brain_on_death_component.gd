class_name TAutoBrainOnDeathComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnDeathComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:628,
## implementation :2248), server only. At eiDie [KillerID, KillerCommanderID] (epLast) remembers the killer and runs
## CheckAndFire (default target: the dying owner).
## Fixed bug of the original: its FireAtKiller override sat on the parameterless Fire, but CheckAndFire calls the other
## overload, so a death never fired at the killer (the HighlyExplosiveBuff mutator). Here the override is FireTargets,
## the overload CheckAndFire calls (docs/original-bugs.md).

var FFireAtKiller := false
var FKillerID := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))


func FireTargets(DefaultTargets: Array) -> void:
	if FFireAtKiller:
		var Target := ATarget.Make(FKillerID)
		if not _TargetsPossible(ATarget.ToRParam(Target), FFireGroup):
			return
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], FFireGroup)
	else:
		super(DefaultTargets)


## Fires at the killer of this unit.
func FireAtKiller() -> TAutoBrainOnDeathComponent:
	FFireAtKiller = true
	return self


func OnDie(KillerID, _KillerCommanderID) -> bool:
	FKillerID = RParam.AsInteger(KillerID)
	CheckAndFire()
	return true
