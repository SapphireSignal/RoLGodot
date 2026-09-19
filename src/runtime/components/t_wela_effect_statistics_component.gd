class_name TWelaEffectStatisticsComponent
extends TGDEntityComponent
## Port of TWelaEffectStatisticsComponent (GameServer/BaseConflict.EntityComponents.Server.Statistics.pas:60,
## implementation :275), server only. Tracks statistics of single welas: for every name given with Name(..) it
## counts in Game.Statistics, owner's commander unless said otherwise (all handlers epLast, reads pass Previous on):
## - TriggerOnCreate: wela_triggers_ at eiAfterCreate.
## - TriggerOnFire: on a local eiFire wela_triggers_, and wela_targets_ per target passing the unit property checks
##   (TakeOwnerFromTarget: counted for the target entity's commander; CheckMaxTargets: only when the targets reach
##   eiWelaTargetCount of its group).
## - TriggerOnKill (eiYouHaveKilledMeShameOnYou, the victim passing the unit property checks), TriggerOnKillDone (a
##   local eiKillDone): wela_kills_; TriggerGlobalOnKillDone: global_kills on a local eiKillDone. Never for suicide.
## - TriggerOnDie / TriggerOnKilled (eiDie): wela_deaths_ for the owner / wela_kills_ for the killer's commander (not
##   for suicide).
## - TriggerOnTakeDamage / TriggerOnHeal (eiTakeDamage / eiHeal reads, CheckDamageType: only with that type):
##   wela_gain_damage_ by the rounded amount.
## - TriggerOnDamageDone (wela_dealt_damage_, amount) / TriggerOnDamageDoneTargets (wela_targets_) on eiDamageDone
##   for a target passing the unit property checks; TriggerOnHealDone: wela_dealt_damage_ on eiHealDone.
## - TriggerOnDuration: a 1 s timer from the call; when the component is freed, wela_duration_ by the whole seconds
##   passed.
## Every event first passes Check: CheckNth (counts every check, passes every nth), CheckResourceMax (its group's
## balance at its cap), CheckResourceEmpty (balance <= 0). Counts are multiplied by Times: 1, or the rounded
## balance of TriggerTimesByResource in its group. Nothing counts without a game (assigned(ServerGame)).
## Kept: Check runs before the damage type / target checks, so the nth counter also counts failing events.

const L = preload("res://src/runtime/dws/dws_lib.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FWelaName: Array = []  # of String
var FTriggerOnKill := false
var FTriggerOnFire := false
var FTriggerOnKillDone := false
var FTriggerOnDie := false
var FTriggerOnKilled := false
var FTriggerOnTakeDamage := false
var FTriggerOnHealDone := false
var FTriggerOnDamageDone := false
var FTriggerOnDamageDoneTargets := false
var FTriggerOnHeal := false
var FTriggerOnCreate := false
var FKillCountsGlobal := false
var FCheckMaxTargets := false
var FCheckDamageType := false
var FTakeOwnerFromTarget := false
var FCheckUnitPropertyMustHave: Array = []
var FCheckUnitPropertyMustHaveAny: Array = []
var FCheckResourceMax := C.reNone
var FCheckResourceEmpty := C.reNone
var FTriggerTimesByResource := C.reNone
var FDamageType := 0
var FDurationCounter: TTimer = null
var FNth := 0
var FNthCounter := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))
	e.append(XEvent("OnYouHaveKilledMeShameOnYou", C.eiYouHaveKilledMeShameOnYou, C.epLast, C.etTrigger))
	e.append(XEvent("OnKillDone", C.eiKillDone, C.epLast, C.etTrigger))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnTakeDamage", C.eiTakeDamage, C.epLast, C.etRead))
	e.append(XEvent("OnHeal", C.eiHeal, C.epLast, C.etRead))
	e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epLast, C.etTrigger))
	e.append(XEvent("OnHealDone", C.eiHealDone, C.epLast, C.etTrigger))


func Destroy() -> void:
	if FDurationCounter != null:
		var Game = GlobalEventbus().Game if GlobalEventbus() != null else null
		if Game != null:
			for WelaName in FWelaName:
				Game.Statistics.WelaDuration(Owner.CommanderID(), WelaName, FDurationCounter.TimesExpired())
		FDurationCounter = null
	super()


func Statistics() -> TGameStatisticManager:
	var Game = GlobalEventbus().Game
	return Game.Statistics if Game != null else null


func Check() -> bool:
	var Result := true
	if FNth > 0:
		FNthCounter += 1
		Result = Result and (FNthCounter % FNth) == 0
	if FCheckResourceMax != C.reNone:
		Result = Result and BC.ResourceCompareParam(FCheckResourceMax, Owner.Balance(FCheckResourceMax, ComponentGroup),
			C.coGreaterEqual, Owner.Cap(FCheckResourceMax, ComponentGroup))
	if FCheckResourceEmpty != C.reNone:
		Result = Result and BC.ResourceCompare(FCheckResourceEmpty, Owner.Balance(FCheckResourceEmpty, ComponentGroup),
			C.coLowerEqual, 0.0)
	return Result


func CheckTarget(Target: RTarget) -> bool:
	var Result := true
	if not FCheckUnitPropertyMustHave.is_empty() or not FCheckUnitPropertyMustHaveAny.is_empty():
		var TargetEntity = Target.TryGetTargetEntity(GlobalEventbus().Game)
		if TargetEntity != null:
			var UnitProperties: Array = TargetEntity.UnitProperties()
			if not FCheckUnitPropertyMustHave.is_empty():
				Result = Result and DSet.Difference(FCheckUnitPropertyMustHave, UnitProperties).is_empty()
			if not FCheckUnitPropertyMustHaveAny.is_empty():
				Result = Result and DSet.Intersects(FCheckUnitPropertyMustHaveAny, UnitProperties)
		else:
			Result = false
	return Result


func Times() -> int:
	if FTriggerTimesByResource == C.reNone:
		return 1
	if BC.IsIntResource(FTriggerTimesByResource):
		return RParam.AsInteger(Owner.Balance(FTriggerTimesByResource, ComponentGroup))
	return L.Round(RParam.AsSingle(Owner.Balance(FTriggerTimesByResource, ComponentGroup)))


func OnAfterCreate() -> bool:
	var Stats := Statistics()
	if FTriggerOnCreate and Stats != null and Check():
		for WelaName in FWelaName:
			Stats.WelaTriggers(Owner.CommanderID(), WelaName, Times())
	return true


func OnDamageDone(Amount, _DamageType, TargetEntity) -> bool:
	var Stats := Statistics()
	if (FTriggerOnDamageDone or FTriggerOnDamageDoneTargets) and Stats != null and Check() \
			and CheckTarget(RTarget.Create(TargetEntity)):
		for WelaName in FWelaName:
			if FTriggerOnDamageDone:
				Stats.WelaDealtDamage(Owner.CommanderID(), WelaName, L.Round(RParam.AsSingle(Amount)))
			if FTriggerOnDamageDoneTargets:
				Stats.WelaTargets(Owner.CommanderID(), WelaName, Times())
	return true


func OnDie(KillerID, KillerCommanderID) -> bool:
	var Stats := Statistics()
	if (FTriggerOnDie or FTriggerOnKilled) and Stats != null and Check():
		for WelaName in FWelaName:
			# we don't want to count suicide as kill
			if FTriggerOnKilled and RParam.AsInteger(KillerID) != Owner.ID:
				Stats.WelaKills(RParam.AsInteger(KillerCommanderID), WelaName, Times())
			if FTriggerOnDie:
				Stats.WelaDeaths(Owner.CommanderID(), WelaName, Times())
	return true


func OnFire(TargetsParam) -> bool:
	var Stats := Statistics() if FTriggerOnFire and IsLocalCall() else null
	if Stats != null and Check() and (not FCheckMaxTargets
			or RParam.AsInteger(Eventbus().Read(C.eiWelaTargetCount, [], ComponentGroup))
				<= ATarget.FromRParam(TargetsParam).size()):
		var Targets := ATarget.FromRParam(TargetsParam)
		for WelaName in FWelaName:
			Stats.WelaTriggers(Owner.CommanderID(), WelaName, Times())
			for Target: RTarget in Targets:
				if CheckTarget(Target):
					var TargetEntity = null
					if FTakeOwnerFromTarget:
						TargetEntity = Target.TryGetTargetEntity(GlobalEventbus().Game)
					if TargetEntity == null:
						TargetEntity = Owner
					Stats.WelaTargets(TargetEntity.CommanderID(), WelaName, Times())
	return true


func OnHeal(Amount, HealModifier, _InflictorID, Previous):
	var Stats := Statistics()
	if FTriggerOnHeal and Stats != null and Check() \
			and (not FCheckDamageType or RParam.AsSet(HealModifier).has(FDamageType)):
		for WelaName in FWelaName:
			Stats.WelaDamage(Owner.CommanderID(), WelaName, L.Round(RParam.AsSingle(Amount)))
	return Previous


func OnHealDone(Amount, _DamageType, _TargetEntity) -> bool:
	var Stats := Statistics()
	if FTriggerOnHealDone and Stats != null and Check():
		for WelaName in FWelaName:
			Stats.WelaDealtDamage(Owner.CommanderID(), WelaName, L.Round(RParam.AsSingle(Amount)))
	return true


func OnKillDone(KilledUnitID) -> bool:
	var Stats := Statistics()
	if (FKillCountsGlobal or FTriggerOnKillDone) and IsLocalCall() and Stats != null \
			and RParam.AsInteger(KilledUnitID) != Owner.ID and Check():
		# we don't want to count suicide as kill
		if FTriggerOnKillDone:
			for WelaName in FWelaName:
				Stats.WelaKills(Owner.CommanderID(), WelaName, Times())
		if FKillCountsGlobal:
			Stats.GlobalKills(Owner.CommanderID())
	return true


func OnTakeDamage(Amount, DamageType, _InflictorID, Previous):
	var Stats := Statistics()
	if FTriggerOnTakeDamage and Stats != null and Check() \
			and (not FCheckDamageType or RParam.AsSet(DamageType).has(FDamageType)):
		for WelaName in FWelaName:
			Stats.WelaDamage(Owner.CommanderID(), WelaName, L.Round(RParam.AsSingle(Amount)))
	return Previous


func OnYouHaveKilledMeShameOnYou(KilledUnitID) -> bool:
	var Stats := Statistics()
	if FTriggerOnKill and Stats != null and RParam.AsInteger(KilledUnitID) != Owner.ID and Check() \
			and CheckTarget(RTarget.Create(RParam.AsInteger(KilledUnitID))):
		for WelaName in FWelaName:
			Stats.WelaKills(Owner.CommanderID(), WelaName, Times())
	return true


## Adds a wela name for which events are tracked. Can be called multiple times for multiple names.
func Name(WelaName: String) -> TWelaEffectStatisticsComponent:
	FWelaName.append(WelaName)
	return self


func CheckResourceMax(Resource: int) -> TWelaEffectStatisticsComponent:
	FCheckResourceMax = Resource
	return self


func CheckResourceEmpty(Resource: int) -> TWelaEffectStatisticsComponent:
	FCheckResourceEmpty = Resource
	return self


func CheckUnitPropertyMustHave(UnitProperties: Array) -> TWelaEffectStatisticsComponent:
	FCheckUnitPropertyMustHave = DSet.Make(UnitProperties)
	return self


func CheckUnitPropertyMustHaveAny(UnitProperties: Array) -> TWelaEffectStatisticsComponent:
	FCheckUnitPropertyMustHaveAny = DSet.Make(UnitProperties)
	return self


func CheckMaxTargets() -> TWelaEffectStatisticsComponent:
	FCheckMaxTargets = true
	return self


func CheckDamageType(DamageType: int) -> TWelaEffectStatisticsComponent:
	FCheckDamageType = true
	FDamageType = DamageType
	return self


func CheckNth(Nth: int) -> TWelaEffectStatisticsComponent:
	FNth = Nth
	return self


func TriggerTimesByResource(Resource: int) -> TWelaEffectStatisticsComponent:
	FTriggerTimesByResource = Resource
	return self


func TriggerOnCreate() -> TWelaEffectStatisticsComponent:
	FTriggerOnCreate = true
	return self


func TriggerOnDuration() -> TWelaEffectStatisticsComponent:
	FDurationCounter = TTimer.new().CreateAndStart(1000)
	return self


func TriggerOnDamageDone() -> TWelaEffectStatisticsComponent:
	FTriggerOnDamageDone = true
	return self


func TriggerOnDamageDoneTargets() -> TWelaEffectStatisticsComponent:
	FTriggerOnDamageDoneTargets = true
	return self


func TriggerOnHealDone() -> TWelaEffectStatisticsComponent:
	FTriggerOnHealDone = true
	return self


func TriggerOnDie() -> TWelaEffectStatisticsComponent:
	FTriggerOnDie = true
	return self


func TriggerOnKilled() -> TWelaEffectStatisticsComponent:
	FTriggerOnKilled = true
	return self


func TriggerOnFire() -> TWelaEffectStatisticsComponent:
	FTriggerOnFire = true
	return self


func TriggerOnKill() -> TWelaEffectStatisticsComponent:
	FTriggerOnKill = true
	return self


func TriggerOnKillDone() -> TWelaEffectStatisticsComponent:
	FTriggerOnKillDone = true
	return self


func TriggerGlobalOnKillDone() -> TWelaEffectStatisticsComponent:
	FKillCountsGlobal = true
	return self


func TriggerOnTakeDamage() -> TWelaEffectStatisticsComponent:
	FTriggerOnTakeDamage = true
	return self


func TriggerOnHeal() -> TWelaEffectStatisticsComponent:
	FTriggerOnHeal = true
	return self


func TakeOwnerFromTarget() -> TWelaEffectStatisticsComponent:
	FTakeOwnerFromTarget = true
	return self
