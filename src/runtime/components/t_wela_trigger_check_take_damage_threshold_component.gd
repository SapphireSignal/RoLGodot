class_name TWelaTriggerCheckTakeDamageThresholdComponent
extends TWelaTriggerCheckTakeDamageComponent
## Port of TWelaTriggerCheckTakeDamageThresholdComponent (BaseConflict.EntityComponents.Shared.Wela.pas:548,
## implementation :1792). Only damage >= eiWelaDamage of its group (LesserEqual: <=).

var FLesserEqualCheck := false


func IsValid(Amount: float, _DamageType: Array, _InflictorID: int) -> bool:
	var Threshold := RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup))
	if FLesserEqualCheck:
		return Amount <= Threshold
	return Amount >= Threshold


func LesserEqual() -> TWelaTriggerCheckTakeDamageThresholdComponent:
	FLesserEqualCheck = true
	return self
