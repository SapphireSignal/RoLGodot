class_name TThinkImpulseNowComponent
extends TEntityComponent
## Port of TThinkImpulseNowComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:37, implementation
## :2843), server only. Thinks once in its group right in its constructor, unless the unit is exiled.


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	if not RParam.AsBoolean(Eventbus().Read(C.eiExiled, [])):
		Eventbus().Trigger(C.eiThink, [], ComponentGroup)
		Eventbus().Trigger(C.eiThinkChain, [], ComponentGroup)
	return self
