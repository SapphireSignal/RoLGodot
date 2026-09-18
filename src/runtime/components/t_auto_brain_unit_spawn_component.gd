class_name TAutoBrainUnitSpawnComponent
extends TAutoBrainComponent
## Port of TAutoBrainUnitSpawnComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:509,
## implementation :2495), server only. At every global eiNewEntity [Entity] (epLast) fires eiFire at the new entity
## in its group if eiIsReady and eiWelaTargetPossible there allow (no CanThink check).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnNewEntity", C.eiNewEntity, C.epLast, C.etTrigger, C.esGlobal))


func OnNewEntity(Entity) -> bool:
	var Target := ATarget.Make(Entity)
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)) and \
		_TargetsPossible(ATarget.ToRParam(Target), ComponentGroup):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], ComponentGroup)
	return true
