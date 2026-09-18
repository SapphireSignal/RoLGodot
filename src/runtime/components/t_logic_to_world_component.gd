class_name TLogicToWorldComponent
extends TEntityComponent
## Port of TLogicToWorldComponent (BaseConflict.EntityComponents.Client.pas:418, implementation :2851). The client
## adds it to every entity it gets from the server (TClientNetworkComponent.DeserializeEntity): the logic position
## and front become the display position / front (on the ground, y = 0), up is UNITY; the entity's display fields
## are refreshed every frame for the visualizers.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDisplayPosition", C.eiDisplayPosition, C.epFirst, C.etRead))
	e.append(XEvent("OnDisplayFront", C.eiDisplayFront, C.epFirst, C.etRead))
	e.append(XEvent("OnDisplayUp", C.eiDisplayUp, C.epFirst, C.etRead))
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnIdle", C.eiIdle, C.epHigh, C.etTrigger, C.esGlobal))


func OnDisplayPosition():
	var p: Vector2 = Owner.Position
	return Vector3(p.x, 0, p.y)


func OnDisplayFront():
	var f: Vector2 = Owner.Front
	if f == Vector2.ZERO:
		return Vector3(0, 0, 1)
	return Vector3(f.x, 0, f.y)


func OnDisplayUp():
	return Vector3(0, 1, 0)


func OnAfterCreate() -> bool:
	OnIdle()
	return true


func OnIdle() -> bool:
	Owner.DisplayPosition = RParam.AsVector3(Eventbus().Read(C.eiDisplayPosition, []))
	Owner.DisplayFront = RParam.AsVector3(Eventbus().Read(C.eiDisplayFront, []))
	Owner.DisplayUp = RParam.AsVector3(Eventbus().Read(C.eiDisplayUp, []))
	return true
