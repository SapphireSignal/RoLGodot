class_name TArmorComponent
extends TEntityComponent
## Port of TArmorComponent (BaseConflict.EntityComponents.Shared.pas:521, implementation :2041).
## Takes different armor into account while damaging (type and value).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDamage", C.eiTakeDamage, C.epMiddle, C.etRead))


## Adjust damage according to the ArmorMatrix and the armor value of the unit. Amount is a `var` parameter:
## the reduced damage reaches the eiTakeDamage handlers after this one (THealthComponent).
func OnDamage(Amount, DamageType, _InflictorID, Previous):
	var AttackType: Array = RParam.AsSet(DamageType)
	if not AttackType.has(C.dtIgnoreArmor) and RParam.AsSingle(Amount) > 1.0:
		var MyArmor := RParam.AsEnumType(Eventbus().Read(C.eiArmorType, []))
		var Factor := 1.0
		var Offset := 0.0
		match MyArmor:
			# No Damage-Reduction
			C.atUnarmored:
				Factor = 1.0
			# 15% Damage-Reduction
			C.atLight:
				Factor = 0.85
			# 20% Damage-Reduction, 30% Damage-Reduction against Ranged
			C.atMedium:
				Factor = 0.7 if AttackType.has(C.dtRanged) else 0.8
			# 30% Damage-Reduction + 5 Flat-Damage-Reduction
			C.atHeavy:
				Factor = 0.7
				Offset = 5
			# 400% Damage if Siege, otherwise no changes
			C.atFortified:
				if AttackType.has(C.dtSiege):
					Factor = 4.0
			_:
				push_error("TArmorComponent.OnDamage: Missing armor type!")
				return Previous
		# apply armor type, every shot deals 1 Damage at least
		SetVarParam(0, RParam.ToSingle(maxf(1.0, RParam.ToSingle(RParam.ToSingle(Factor) * RParam.AsSingle(Amount)) - Offset)))
	return Previous
