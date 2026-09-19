class_name TWelaEffectRedirecterComponent
extends TGDEntityComponent
## Port of TWelaEffectRedirecterComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:253,
## implementation :3162), server only. RedirectToGround: at epFirst of eiFire, replaces the `var` targets with the
## ground at the owner's position for every later handler. Not group checked (the event's groups decide).

var FRedirectToGround := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))


## Fires the wela at all targets.
func OnFire(_Targets) -> bool:
	if FRedirectToGround:
		SetVarParam(0, ATarget.ToRParam(ATarget.Make(Owner.Position)))
	return true


func RedirectToGround() -> TWelaEffectRedirecterComponent:
	FRedirectToGround = true
	return self
