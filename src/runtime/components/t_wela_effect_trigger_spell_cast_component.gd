class_name TWelaEffectTriggerSpellCastComponent
extends TWelaEffectComponent
## Port of TWelaEffectTriggerSpellCastComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:388,
## implementation :3184), server only. On fire notifies a spell cast: global eiCommanderAbilityUsed
## [owner's TeamID, ATarget].


func Fire(Targets: Array) -> void:
	GlobalEventbus().Trigger(C.eiCommanderAbilityUsed, [Owner.TeamID(), ATarget.ToRParam(Targets)])
