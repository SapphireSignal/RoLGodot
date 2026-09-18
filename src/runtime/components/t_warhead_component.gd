class_name TWarheadComponent
extends TEntityComponent
## Port of TWarheadComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:29, implementation
## :684), server only. Master class of the warheads, the things that act on the targets (deal damage, heal, ...):
## eiFireWarhead [ATarget] reaching its group runs FireWarhead at epLast (RedirectToSelf: on its owner instead).

var FRedirectToSelf := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnFireWarhead", C.eiFireWarhead, C.epLast, C.etTrigger))


## Abstract. Targets: an ATarget (Array of RTarget).
func FireWarhead(_Targets: Array) -> void:
	pass


## Fires the warhead on an entity.
func OnFireWarhead(Targets) -> bool:
	if FRedirectToSelf:
		FireWarhead(ATarget.Make(Owner))
	else:
		FireWarhead(ATarget.FromRParam(Targets).duplicate())
	return true


func RedirectToSelf() -> TWarheadComponent:
	FRedirectToSelf = true
	return self
