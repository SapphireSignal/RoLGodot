class_name TAutoBrainOnBeforeDeath
extends TAutoBrainOnDeathComponent
## Port of TAutoBrainOnBeforeDeath (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:645, implementation
## :2870), server only. TAutoBrainOnDeathComponent whose eiDie handler runs at epMiddle, before the health
## component's death handling.


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	ChangeEventPriority(C.eiDie, C.etTrigger, C.epMiddle)
	return self
