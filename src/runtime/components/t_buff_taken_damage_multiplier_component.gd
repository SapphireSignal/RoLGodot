class_name TBuffTakenDamageMultiplierComponent
extends TEntityComponent
## Port of TBuffTakenDamageMultiplierComponent (GameServer/BaseConflict.EntityComponents.Server.pas:61, implementation
## :2065), server only. Scales the damage the owner takes (eiTakeDamage read, epLow: after armor, before health) by
## eiWelaModifier of its group (< 1 reduces, > 1 boosts; Flat: subtracts it instead, at least 1 left) when the damage
## types contain all of MustHave, any of MustHaveAny (if set) and none of MustNotHave; no modifier value, no change.
## Changes the Amount var parameter and passes Previous on. DodgeDamage: the modifier is a dodge chance (random <
## modifier: no damage and eiFire [owner] in its group, else full damage). ReflectReducedDamage: when the factor is
## within [0, 1] (or Flat), the damage is not irredirectable and the inflictor exists, the inflictor takes the
## reduced part (Flat: the part left, at least 1) as eiTakeDamage with dtIrredirectable, inflicted by itself.
## ApplyOnHeal: works on eiHeal (epLower) instead, only scaling. Delphi's Random is Godot's RNG.
## Kept: Flat reflection sends back what is left, not what was taken off; asserts of the heal path dropped (release).

var FDamageMustHave: Array = []
var FDamageMustHaveAny: Array = []
var FDamageMustNotHave: Array = []
var FReflect := false
var FDodge := false
var FOnHeal := false
var FFlatValue := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnTakeDamage", C.eiTakeDamage, C.epLow, C.etRead))
	e.append(XEvent("OnHeal", C.eiHeal, C.epLower, C.etRead))


func DamageTypeMustHaveAny(DamageTypes: Array) -> TBuffTakenDamageMultiplierComponent:
	FDamageMustHaveAny = DSet.Make(DamageTypes)
	return self


func DamageTypeMustHave(DamageTypes: Array) -> TBuffTakenDamageMultiplierComponent:
	FDamageMustHave = DSet.Make(DamageTypes)
	return self


func DamageTypeMustNotHave(DamageTypes: Array) -> TBuffTakenDamageMultiplierComponent:
	FDamageMustNotHave = DSet.Make(DamageTypes)
	return self


func ReflectReducedDamage() -> TBuffTakenDamageMultiplierComponent:
	FReflect = true
	return self


func DodgeDamage() -> TBuffTakenDamageMultiplierComponent:
	FDodge = true
	return self


func ApplyOnHeal() -> TBuffTakenDamageMultiplierComponent:
	FOnHeal = true
	return self


func Flat() -> TBuffTakenDamageMultiplierComponent:
	FFlatValue = true
	return self


func _Matches(AttackType: Array) -> bool:
	return DSet.Difference(FDamageMustHave, AttackType).is_empty() \
		and (FDamageMustHaveAny.is_empty() or DSet.Intersects(FDamageMustHaveAny, AttackType)) \
		and (FDamageMustNotHave.is_empty() or not DSet.Intersects(FDamageMustNotHave, AttackType))


## Modifies the taken heal if the damage types match.
func OnHeal(Amount, DamageType, _InflictorID, Previous):
	if not FOnHeal:
		return Previous
	var AttackType := RParam.AsSet(DamageType)
	var Factor = Eventbus().Read(C.eiWelaModifier, [], ComponentGroup)
	if not RParam.IsEmpty(Factor) and _Matches(AttackType):
		SetVarParam(0, RParam.ToSingle(RParam.AsSingle(Amount) * RParam.AsSingle(Factor)))
	return Previous


## Reduces the taken damage if the damage type matches.
func OnTakeDamage(Amount, DamageType, InflictorID, Previous):
	if FOnHeal:
		return Previous
	var AttackType := RParam.AsSet(DamageType)
	var Factor = Eventbus().Read(C.eiWelaModifier, [], ComponentGroup)
	if not RParam.IsEmpty(Factor) and _Matches(AttackType):
		var sFactor := RParam.AsSingle(Factor)
		# check whether damage should be dodged by chance, not reduced by factor
		if FDodge:
			if randf() < sFactor:
				sFactor = 0.0
				# if dodged send eiFire to its owning group for following effects
				Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], ComponentGroup)
			else:
				sFactor = 1.0
		# if damage should be reflected, take the reduced amount and send it back to the inflictor; it is only
		# reflected if damage is reduced and not irredirectable (e.g. has been reflected before, prevent ping-pong)
		if FReflect and (FFlatValue or (sFactor >= 0.0 and sFactor <= 1.0)) and not AttackType.has(C.dtIrredirectable):
			var Game = GlobalEventbus().Game
			var Inflictor = Game.EntityManager.TryGetEntityByID(RParam.AsInteger(InflictorID)) if Game != null else null
			if Inflictor != null:
				var reflectedAmount: float
				if FFlatValue:
					reflectedAmount = maxf(1.0, RParam.AsSingle(Amount) - sFactor)
				else:
					reflectedAmount = RParam.AsSingle(Amount) * (1 - sFactor)
				Inflictor.Eventbus.Read(C.eiTakeDamage, [RParam.ToSingle(reflectedAmount),
					DSet.Make(AttackType + [C.dtIrredirectable]), InflictorID])
		if FFlatValue:
			SetVarParam(0, RParam.ToSingle(maxf(1.0, RParam.AsSingle(Amount) - sFactor)))
		else:
			SetVarParam(0, RParam.ToSingle(RParam.AsSingle(Amount) * sFactor))
	return Previous
