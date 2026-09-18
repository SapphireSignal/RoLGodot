class_name TWelaEffectSuicideComponent
extends TWelaEffectComponent
## Port of TWelaEffectSuicideComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:372,
## implementation :2037), server only. On fire triggers eiDie [-1, -1] on its owner, then (unless DontFree, or the
## owner is still alive) the global eiDelayedKillEntity. PreventDeath stops every eiDie of the owner at epLow (so
## the health component's death at a later priority never runs). DontFree has no setter the scripts use.

var FDontFree := false
var FPreventDeath := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnBeforeDie", C.eiDie, C.epLow, C.etTrigger))


func Fire(_Targets: Array) -> void:
	Eventbus().Trigger(C.eiDie, [-1, -1])
	if not (FDontFree or RParam.AsBoolean(Eventbus().Read(C.eiIsAlive, []))):
		GlobalEventbus().Trigger(C.eiDelayedKillEntity, [Owner.ID])


## On dying fire at itself.
func OnBeforeDie(_KillerID, _KillerCommanderID) -> bool:
	return not FPreventDeath


func PreventDeath() -> TWelaEffectSuicideComponent:
	FPreventDeath = true
	return self


func DontFree() -> TWelaEffectSuicideComponent:
	FDontFree = true
	return self
