class_name TWarheadSplashHealthComponent
extends TWarheadSplashComponent
## Port of TWarheadSplashHealthComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:259,
## implementation :771), server only. Damages (FHeal: heals) the entities hit, sharing a capped amount: each unit
## gets at most eiWelaDamage of its group, all together at most eiWelaDamage × eiWelaSplashfactor (default 10000,
## i.e. no shared cap). The amount is spread evenly; a unit that needs less (less health left, or less missing
## health when healing) takes only that and the rest is spread over the others, round by round; what is left at the
## end is spread over all (capped per unit), since armor could otherwise prevent a death. AmountIsPercentage: each
## unit gets eiWelaDamage × its health cap, no shared cap. Heals skip units at full health unless dtOverheal.
## Every hit adds dtSplash to the group's eiDamageType: damage asks the owner's eiWillDealDamage, then the target's
## eiTakeDamage [Amount, Types, OwnerID], dealt > 0 → owner eiDamageDone, target dead → eiKillDone [ID] in its group;
## heal: the target's eiHeal, healed > 0 → owner eiHealDone. Singles as in the original: every stored value is
## rounded to a 32-bit float.

var FHeal := false
var FPercentage := false


func AmountIsPercentage() -> TWarheadSplashHealthComponent:
	FPercentage = true
	return self


## RUnitHealth: [Health, MaxHealth, DoneDamage, Target]
func _DoMetric(item: Array) -> float:
	if FHeal:
		return RParam.ToSingle(item[1] - item[0])
	return item[0]


func ApplyEffect(Targets: Array) -> void:
	if Targets.size() <= 0:
		return
	var S := func(x: float) -> float: return RParam.ToSingle(x)

	var DamageTypes := RParam.AsSet(Eventbus().Read(C.eiDamageType, [], ComponentGroup))
	# the maximal damage of this warhead to a single unit
	var Damage := RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup))
	var MaxDamgePerUnit := Damage
	# the maximal damage of this warhead summed over all targets is determined by Damage * Damagefactor
	# if no splashfactor is determined, all units get same damage
	var Damagefactor := RParam.AsSingleDefault(Eventbus().Read(C.eiWelaSplashfactor, [], ComponentGroup), 10000.0)
	var DamageToDeal: float = S.call(Damage * Damagefactor)
	# evenly distribute Damagesum over enemies

	# build up healtharray of all our targets
	var TargetsToProcess: Array = []
	var FinishedTargets: Array = []
	for Target in Targets:
		var Health := RParam.AsSingle(Target.Eventbus.Read(C.eiResourceBalance, [C.reHealth]))
		var MaxHealth := RParam.AsSingle(Target.Eventbus.Read(C.eiResourceCap, [C.reHealth]))
		if not FHeal or Health < MaxHealth or DamageTypes.has(C.dtOverheal):
			TargetsToProcess.append([Health, MaxHealth, 0.0, Target])

	if FPercentage:
		# for percentages there is no cap of distributed dmg/heal atm, so directly apply percentage
		FinishedTargets.append_array(TargetsToProcess)
		for item in FinishedTargets:
			item[2] = S.call(Damage * item[1])
	else:
		# distribute damage or health until all are satisfied or amount is depleted
		# first precompute all amounts for each target
		while TargetsToProcess.size() > 0:
			# find the unit which would gain the least healing or damage
			var leastItem := -1
			var DamageToDoPerUnit: float = 2147483648.0  # MaxInt as a single
			for i in TargetsToProcess.size():
				if _DoMetric(TargetsToProcess[i]) < DamageToDoPerUnit:
					DamageToDoPerUnit = _DoMetric(TargetsToProcess[i])
					leastItem = i
			# limit maximum damage per unit to the original damage
			DamageToDoPerUnit = minf(DamageToDoPerUnit, Damage)
			# if we could evenly spread our current damage/heal over all units, do it and finish
			# else spread the least value and skip the least item which limits us
			for item in TargetsToProcess:
				item[2] = S.call(item[2] + minf(S.call(DamageToDeal / TargetsToProcess.size()), DamageToDoPerUnit))
			if DamageToDoPerUnit >= S.call(DamageToDeal / TargetsToProcess.size()):
				DamageToDeal = 0.0
				break
			else:
				DamageToDeal = S.call(DamageToDeal - S.call(DamageToDoPerUnit * TargetsToProcess.size()))
				# reduce original damage, so each unit damage is capped to it
				Damage = S.call(Damage - DamageToDoPerUnit)
				# if max damage per unit is reached break
				if Damage <= 0:
					break
				FinishedTargets.append(TargetsToProcess[leastItem])
				TargetsToProcess.remove_at(leastItem)
		FinishedTargets.append_array(TargetsToProcess)
		# distribute all remaining damage due armor reduction would prevent death issues
		if DamageToDeal > 0:
			for item in FinishedTargets:
				item[2] = minf(S.call(item[2] + S.call(DamageToDeal / FinishedTargets.size())), MaxDamgePerUnit)

	# now apply all computed damages / heals
	var SplashTypes := DSet.Union(DamageTypes, [C.dtSplash])
	for item in FinishedTargets:
		var Target: TEntity = item[3]
		if FHeal:
			var DamageDone := RParam.AsSingle(Target.Eventbus.Read(C.eiHeal, [item[2], SplashTypes.duplicate(), Owner.ID]))
			if DamageDone > 0:
				Eventbus().Trigger(C.eiHealDone, [DamageDone, SplashTypes.duplicate(), Target])
		else:
			var DamageToDo: float = item[2]
			var ModifiedDamageToDo = Eventbus().Read(C.eiWillDealDamage, [DamageToDo, SplashTypes.duplicate(), Target])
			if not RParam.IsEmpty(ModifiedDamageToDo):
				DamageToDo = RParam.AsSingle(ModifiedDamageToDo)
			var DamageDone := RParam.AsSingle(Target.Eventbus.Read(C.eiTakeDamage, [DamageToDo, SplashTypes.duplicate(), Owner.ID]))
			if DamageDone > 0:
				Eventbus().Trigger(C.eiDamageDone, [DamageDone, SplashTypes.duplicate(), Target])
			if not RParam.AsBoolean(Target.Eventbus.Read(C.eiIsAlive, [])):
				Eventbus().Trigger(C.eiKillDone, [Target.ID], ComponentGroup)
