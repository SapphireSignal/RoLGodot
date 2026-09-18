class_name TPositionComponent
extends TSerializableEntityComponent
## Port of TPositionComponent (BaseConflict.EntityComponents.Shared.pas:98, implementation :651).
## Handles synchronous positioning of entities: eiSyncPosition moves the owner there.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnSyncPosition", C.eiSyncPosition, C.epLast, C.etTrigger))


## Move entity to synchronized position.
func OnSyncPosition(Pos) -> bool:
	Owner.Position = RParam.AsVector2(Pos)
	return true
