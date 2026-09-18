class_name TAutoBrainBuffComponent
extends TAutoBrainComponent
## Port of TAutoBrainBuffComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:768, implementation
## :2277), server only. Marks a buff: eiBuffed (read, epFirst) adds its buff types to the previous set, and
## eiRemoveBuffs [Whitelist, Blacklist] (epLast) with one of its types whitelisted and none blacklisted fires eiFire
## at the owner in its group (no other checks); the effect there removes the buff.

var FBuffType: Array = []


func CreateGrouped(Owner = null, Group = [], BuffTypes = []) -> TEntityComponent:
	super(Owner, Group)
	FBuffType = DSet.Make(BuffTypes)
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnBuffed", C.eiBuffed, C.epFirst, C.etRead))
	e.append(XEvent("OnRemoveBuff", C.eiRemoveBuffs, C.epLast, C.etTrigger))


func OnBuffed(Previous):
	return DSet.Union(RParam.AsSet(Previous), FBuffType)


func OnRemoveBuff(Whitelist, Blacklist) -> bool:
	if DSet.Intersects(RParam.AsSet(Whitelist), FBuffType) and not DSet.Intersects(RParam.AsSet(Blacklist), FBuffType):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(FOwner))], ComponentGroup)
	return true
