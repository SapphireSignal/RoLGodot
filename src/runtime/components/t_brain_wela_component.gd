class_name TBrainWelaComponent
extends TBrainComponent
## Port of TBrainWelaComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:330, implementation
## :1045), server only. Base of the brains that fire a wela: they fire FFireEvent (eiFire; eiPreFire when
## Blocking, so TBrainActionComponent delays the shot and blocks the chain for the action duration).

var FBlocking := false
var FFireEvent: int = C.eiFire


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FFireEvent = C.eiFire
	return self


## Blocking brains block the whole think chain after their activation for the eiWelaActionduration.
func Blocking() -> TBrainWelaComponent:
	FBlocking = true
	FFireEvent = C.eiPreFire
	return self
