class_name TCommanderComponent
extends TGDEntityComponent
## Port of TCommanderComponent (BaseConflict.EntityComponents.Client.pas:199, implementation :2694), client only
## (the client CommanderTemplate adds it). Adds its commander to the global eiEnumerateCommanders read (epFirst):
## the list (an Array of entities) starts empty.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnEnumerateCommanders", C.eiEnumerateCommanders, C.epFirst, C.etRead, C.esGlobal))


## Add this commander to the enumeration.
func OnEnumerateCommanders(PrevValue):
	var Result = PrevValue
	if Result == null:
		Result = []
	Result.append(FOwner)
	return Result
