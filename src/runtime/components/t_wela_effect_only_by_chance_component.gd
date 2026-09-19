class_name TWelaEffectOnlyByChanceComponent
extends TGDEntityComponent
## Port of TWelaEffectOnlyByChanceComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:280,
## implementation :2803), server only. Stops eiFire (epMiddle, before the effects at epLast) unless a random roll
## falls within eiWelaChance of its group. An empty chance lets every fire through (with an error).
## Delphi's Random is Godot's RNG here, as in the targeting components.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnFire", C.eiFire, C.epMiddle, C.etTrigger))


## Consumes event by a chance.
func OnFire(_Targets) -> bool:
	var Chance = Eventbus().Read(C.eiWelaChance, [], ComponentGroup)
	if RParam.IsEmpty(Chance):
		push_error("TWelaEffectOnlyByChanceComponent.OnFire: Empty eiWelaChance, need this value to work!")
	return RParam.IsEmpty(Chance) or RParam.AsSingle(Chance) >= randf()
