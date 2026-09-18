class_name TModifierMultiplyDealtDamageComponent
extends TModifierComponent
## Port of TModifierMultiplyDealtDamageComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:737,
## implementation :2586), server only. On eiWillDealDamage (read, epMiddle) the damage so far (Previous, else Amount)
## is multiplied by eiWelaModifier of the value group when the roll succeeds (eiWelaChance, always without one), the
## types contain MustHave and none of MustNotHave, and (CheckWelaConstraint) the target is possible in the value
## group; then it also fires eiFire [target] in the value group. Delphi's Random is Godot's RNG.
## Not applied to ReadyGroup (the original ignores it here too).

var FMustHave: Array = []
var FMustNotHave: Array = []
var FCheckWelaConstraint := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWillDealDamage", C.eiWillDealDamage, C.epMiddle, C.etRead))


func CheckWelaConstraint() -> TModifierMultiplyDealtDamageComponent:
	FCheckWelaConstraint = true
	return self


func MustHave(DamageTypes: Array) -> TModifierMultiplyDealtDamageComponent:
	FMustHave = DSet.Make(DamageTypes)
	return self


func MustNotHave(DamageTypes: Array) -> TModifierMultiplyDealtDamageComponent:
	FMustNotHave = DSet.Make(DamageTypes)
	return self


## Roll the dice to deal possibly adjusted damage.
func OnWillDealDamage(Amount, DamageTypes, TargetEntity, Previous):
	var RealDamageTypes := RParam.AsSet(DamageTypes)
	var RealAmount: float = RParam.AsSingle(Amount) if RParam.IsEmpty(Previous) else RParam.AsSingle(Previous)
	var Chance = Eventbus().Read(C.eiWelaChance, [], FValueGroup)
	var Multiplier := RParam.AsSingle(Eventbus().Read(C.eiWelaModifier, [], FValueGroup))
	if (RParam.IsEmpty(Chance) or randf() <= RParam.AsSingle(Chance)) \
		and (FMustHave.is_empty() or DSet.Difference(FMustHave, RealDamageTypes).is_empty()) \
		and not DSet.Intersects(FMustNotHave, RealDamageTypes) \
		and (not FCheckWelaConstraint or RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible,
			[ATarget.ToRParam(ATarget.Make(TargetEntity))], FValueGroup)).IsValid()):
		var Result := RParam.ToSingle(RealAmount * Multiplier)
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(TargetEntity))], FValueGroup)
		return Result
	return RealAmount
