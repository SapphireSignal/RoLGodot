class_name TWarheadSpottyHealthComponent
extends TWarheadSpottyComponent
## Port of TWarheadSpottyHealthComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:117,
## implementation :588), server only. Damages (or, with FHeal, heals) each target entity by eiWeladamage ×
## eiWelaModifier (default 1) of its group, with the group's eiDamageType; PercentageOf{Current,Max}Health makes
## that a fraction of the target's health balance / cap.
## Damage: the owner's eiWillDealDamage [Amount, DamageType, Target] may replace the amount, the target's
## eiTakeDamage [Amount, DamageType, OwnerID] deals it; dealt > 0 gives the owner eiDamageDone [Dealt, DamageType,
## Target]; a target no longer alive gives eiKillDone [TargetID] in its group. Heal: the target's eiHeal, healed > 0
## gives the owner eiHealDone [Healed, DamageType, Target].

var FHeal := false
var FPercentage := false
var FPercentageOfCurrent := false


func ApplyEffect(Entity: TEntity) -> void:
	var DamageType := RParam.AsSet(Eventbus().Read(C.eiDamageType, [], ComponentGroup))
	# amount of damage
	var DamageToDo := RParam.ToSingle(RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup)) * RParam.AsSingleDefault(Eventbus().Read(C.eiWelaModifier, [], ComponentGroup), 1.0))
	# if amount is percentage adjust to it
	if FPercentage:
		if FPercentageOfCurrent:
			DamageToDo = RParam.ToSingle(DamageToDo * RParam.AsSingle(Entity.Balance(C.reHealth)))
		else:
			DamageToDo = RParam.ToSingle(DamageToDo * RParam.AsSingle(Entity.Cap(C.reHealth)))
	var DamageDone
	if FHeal:
		DamageDone = Entity.Eventbus.Read(C.eiHeal, [DamageToDo, DamageType.duplicate(), Owner.ID])
		if RParam.AsSingle(DamageDone) > 0:
			Eventbus().Trigger(C.eiHealDone, [DamageDone, DamageType.duplicate(), Entity])
	else:
		var ModifiedDamageToDo = Eventbus().Read(C.eiWillDealDamage, [DamageToDo, DamageType.duplicate(), Entity])
		if not RParam.IsEmpty(ModifiedDamageToDo):
			DamageToDo = RParam.AsSingle(ModifiedDamageToDo)
		DamageDone = Entity.Eventbus.Read(C.eiTakeDamage, [DamageToDo, DamageType.duplicate(), Owner.ID])
		if RParam.AsSingle(DamageDone) > 0:
			Eventbus().Trigger(C.eiDamageDone, [DamageDone, DamageType.duplicate(), Entity])
		if not RParam.AsBoolean(Entity.Eventbus.Read(C.eiIsAlive, [])):
			Eventbus().Trigger(C.eiKillDone, [Entity.ID], ComponentGroup)


func PercentageOfCurrentHealth() -> TWarheadSpottyHealthComponent:
	FPercentage = true
	FPercentageOfCurrent = true
	return self


func PercentageOfMaxHealth() -> TWarheadSpottyHealthComponent:
	FPercentage = true
	FPercentageOfCurrent = false
	return self
