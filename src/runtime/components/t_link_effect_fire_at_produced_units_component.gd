class_name TLinkEffectFireAtProducedUnitsComponent
extends TGDEntityComponent
## Port of TLinkEffectFireAtProducedUnitsComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:720,
## implementation :2391), server only, a link's continuous effect. On the link's eiAfterCreate it hooks the
## eiWelaUnitProduced trigger of its destination (eiLinkDest[0], epLast); each unit the destination produces makes the
## link fire (eiFire [unit]) in its group. The hook dies with the link (remote subscription).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))


## Hook destination eiWelaUnitProduced.
func OnAfterCreate() -> bool:
	var Targets := ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
	if not ATarget.HasIndex(Targets, 0):
		push_error(BuildExceptionMessage("TargetTakeDamage: No destinations set!"))
		return true
	var Entity = Targets[0].TryGetTargetEntity(GlobalEventbus().Game)
	if Entity != null:
		Entity.Eventbus.SubscribeRemote(C.eiWelaUnitProduced, C.etTrigger, C.epLast, self, "TargetProducesUnit", 1)
	return true


func TargetProducesUnit(EntityID) -> bool:
	Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(RParam.AsInteger(EntityID)))], ComponentGroup)
	return true
