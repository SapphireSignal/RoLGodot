class_name TWelaEffectIncreaseResourceComponent
extends TWelaEffectComponent
## Port of TWelaEffectIncreaseResourceComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:456,
## implementation :3242), server only. On fire adds 1 (1.0 for float resources) of its resource (default reNone)
## in its own group: eiResourceTransaction.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FResource := C.reNone


func Fire(_Targets: Array) -> void:
	var Amount = 1 if BC.IsIntResource(FResource) else 1.0
	Eventbus().Trigger(C.eiResourceTransaction, [FResource, Amount], ComponentGroup)


func SetResourceType(Resource: int = 0) -> TWelaEffectIncreaseResourceComponent:
	FResource = Resource
	return self
