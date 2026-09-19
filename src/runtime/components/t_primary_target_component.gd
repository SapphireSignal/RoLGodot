class_name TPrimaryTargetComponent
extends TSerializableEntityComponent
## Port of TPrimaryTargetComponent (BaseConflict.EntityComponents.Shared.pas:620, implementation :1973). Only nexus
## get this component: the lose condition of their team. Answers the global eiEnumerateNexus read by appending its
## owner to the list of the previous handlers (a fresh Array when it is the first). Marked XNetworkBaseType: the
## server's TServerPrimaryTargetComponent reaches the client as this class.


## [XNetworkBaseType]
func NetworkBaseType() -> String:
	return "TPrimaryTargetComponent"


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGetNexusPosition", C.eiEnumerateNexus, C.epFirst, C.etRead, C.esGlobal))


func OnGetNexusPosition(Previous):
	var NexusList: Array = Previous if Previous is Array else []
	NexusList.append(Owner)
	return NexusList
