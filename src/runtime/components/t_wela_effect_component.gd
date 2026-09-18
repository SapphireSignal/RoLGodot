class_name TWelaEffectComponent
extends TEntityComponent
## Port of TWelaEffectComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:268, implementation
## :1095), server only. Master class of a wela's effects: eiFire [ATarget] called to its group (a local call; a
## groupless fire reaches only groupless effects) runs Fire(Targets) at epLast.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))


## Abstract. Targets: an ATarget (Array of RTarget), a fresh copy.
func Fire(_Targets: Array) -> void:
	pass


## Fires the wela at all targets.
func OnFire(Targets) -> bool:
	if IsLocalCall():
		Fire(ATarget.FromRParam(Targets).duplicate())
	return true
