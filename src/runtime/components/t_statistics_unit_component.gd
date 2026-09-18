class_name TStatisticsUnitComponent
extends TEntityComponent
## Port of TStatisticsUnitComponent (GameServer/BaseConflict.EntityComponents.Server.Statistics.pas:35,
## implementation :152), server only. Placed in every unit, counts its statistics in Game.Statistics (all handlers
## epLast, the reads pass Previous on unchanged):
## - eiAfterCreate: wela_spawns_Ranged / _Range (the main weapon's rounded range) for a ranged main weapon,
##   _upLegendary, _Melee, _gte500Health (health balance >= 500).
## - eiDie: the unit's death; wela_kills_with_two_state_effects for the killer's commander when it had two or more
##   state effects; a global kill for the killer's commander; for a base (upBase) wela_kills_basebuildingwhileeotfactive
##   for every enemy commander with upHasEchoesOfTheFuture.
## - eiInstaDie: global insta death (own commander) and insta kill (killer's commander).
## - eiYouHaveKilledMeShameOnYou (not for suicide): the unit's kill, wela_kills_upBuilding (a building, not a
##   base), _upLegendary.
## - eiTakeDamage read: sums the damage taken; wela_gain_damage_max keeps the highest sum, global_gain_damage adds
##   the sum (not the damage) every time; wela_gain_damage_Ranged (ranged, not true damage), _RootByBasebuilding
##   (true damage while rooted), _upLegendary.
## - eiDamageDone: wela_dealt_damage_rootbyranged for ranged damage on a rooted target.
## - eiHeal read: wela_gain_damage_FlatHeal / _HoT by the heal modifier. eiOverheal: wela_gain_damage_Overheal.
## Amounts are rounded (Delphi's banker's rounding). The handlers skip without a game (assigned(ServerGame));
## port: eiAfterCreate too (the original has no check there, a server unit always has a game).

const L = preload("res://src/runtime/dws/dws_lib.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FGainedDamage := 0.0  # single


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnYouHaveKilledMeShameOnYou", C.eiYouHaveKilledMeShameOnYou, C.epLast, C.etTrigger))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnInstaDie", C.eiInstaDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnTakeDamage", C.eiTakeDamage, C.epLast, C.etRead))
	e.append(XEvent("OnDoneDamage", C.eiDamageDone, C.epLast, C.etTrigger))
	e.append(XEvent("OnHeal", C.eiHeal, C.epLast, C.etRead))
	e.append(XEvent("OnOverheal", C.eiOverheal, C.epLast, C.etTrigger))


func Statistics() -> TGameStatisticManager:
	var Game = GlobalEventbus().Game
	return Game.Statistics if Game != null else null


func OnAfterCreate() -> bool:
	var Stats := Statistics()
	if Stats == null:
		return true
	if RParam.AsSet(Eventbus().Read(C.eiDamageType, [], [C.GROUP_MAINWEAPON])).has(C.dtRanged):
		Stats.WelaSpawns(Owner.CommanderID(), "Ranged", 1)
		Stats.WelaSpawns(Owner.CommanderID(), "Range",
			L.Round(RParam.AsSingle(Eventbus().Read(C.eiWelaRange, [], [C.GROUP_MAINWEAPON]))))
	if Owner.HasUnitProperty(C.upLegendary):
		Stats.WelaSpawns(Owner.CommanderID(), "upLegendary", 1)
	if Owner.HasUnitProperty(C.upMelee):
		Stats.WelaSpawns(Owner.CommanderID(), "Melee", 1)
	if Owner.BalanceSingle(C.reHealth) >= 500.0:
		Stats.WelaSpawns(Owner.CommanderID(), "gte500Health", 1)
	return true


func OnDie(_KillerID, KillerCommanderID) -> bool:
	var Game = GlobalEventbus().Game
	if Game != null:
		Game.Statistics.UnitDeaths(Owner.CommanderID(), Owner.ScriptFileName())
		var StateEffects := DSet.Intersection(Owner.UnitProperties(), BC.UNIT_PROPERTIES_STATE_EFFECTS)
		if StateEffects.size() >= 2:
			Game.Statistics.WelaKills(RParam.AsInteger(KillerCommanderID), "with_two_state_effects", 1)
		Game.Statistics.GlobalKills(RParam.AsInteger(KillerCommanderID))
		for Commander in Game.Commanders:
			if Owner.HasUnitProperty(C.upBase) and Commander.TeamID() != Owner.TeamID() \
					and Commander.HasUnitProperty(C.upHasEchoesOfTheFuture):
				Game.Statistics.WelaKills(Commander.ID, "basebuildingwhileeotfactive", 1)
	return true


func OnDoneDamage(Amount, DamageType, TargetEntity) -> bool:
	var Stats := Statistics()
	if Stats != null:
		if RParam.AsSet(DamageType).has(C.dtRanged) and TargetEntity.HasUnitProperty(C.upRooted):
			Stats.WelaDealtDamage(Owner.CommanderID(), "rootbyranged", L.Round(RParam.AsSingle(Amount)))
	return true


func OnHeal(Amount, HealModifier, _InflictorID, Previous):
	var Stats := Statistics()
	if Stats != null:
		var DamageTypeSet := RParam.AsSet(HealModifier)
		if DamageTypeSet.has(C.dtFlatHeal):
			Stats.WelaDamage(Owner.CommanderID(), "FlatHeal", L.Round(RParam.AsSingle(Amount)))
		if DamageTypeSet.has(C.dtHoT):
			Stats.WelaDamage(Owner.CommanderID(), "HoT", L.Round(RParam.AsSingle(Amount)))
	return Previous


func OnInstaDie(_KillerID, KillerCommanderID) -> bool:
	var Stats := Statistics()
	if Stats != null:
		Stats.GlobalInstaDeaths(Owner.CommanderID())
		Stats.GlobalInstaKills(RParam.AsInteger(KillerCommanderID))
	return true


func OnOverheal(Amount, _HealModifier, _InflictorID) -> bool:
	var Stats := Statistics()
	if Stats != null:
		Stats.WelaDamage(Owner.CommanderID(), "Overheal", L.Round(RParam.AsSingle(Amount)))
	return true


func OnTakeDamage(Amount, DamageType, _InflictorID, Previous):
	var Stats := Statistics()
	if Stats != null:
		FGainedDamage = RParam.ToSingle(FGainedDamage + RParam.AsSingle(Amount))
		Stats.WelaDamageMax(Owner.CommanderID(), "max", L.Round(FGainedDamage))
		Stats.GlobalDamage(Owner.CommanderID(), L.Round(FGainedDamage))
		var DamageTypeSet := RParam.AsSet(DamageType)
		if DamageTypeSet.has(C.dtRanged) and not DamageTypeSet.has(C.dtTrue):
			Stats.WelaDamage(Owner.CommanderID(), "Ranged", L.Round(RParam.AsSingle(Amount)))
		if DamageTypeSet.has(C.dtTrue) and Owner.UnitProperties().has(C.upRooted):
			Stats.WelaDamage(Owner.CommanderID(), "RootByBasebuilding", L.Round(RParam.AsSingle(Amount)))
		if Owner.UnitProperties().has(C.upLegendary):
			Stats.WelaDamage(Owner.CommanderID(), "upLegendary", L.Round(RParam.AsSingle(Amount)))
	return Previous


func OnYouHaveKilledMeShameOnYou(KilledUnitID) -> bool:
	var Stats := Statistics()
	# we don't want to count suicide as kill
	if Stats != null and RParam.AsInteger(KilledUnitID) != Owner.ID:
		Stats.UnitKills(Owner.CommanderID(), Owner.ScriptFileName())
		var Props: Array = Owner.UnitProperties()
		if Props.has(C.upBuilding) and not Props.has(C.upBase):
			Stats.WelaKills(Owner.CommanderID(), "upBuilding", 1)
		if Props.has(C.upLegendary):
			Stats.WelaKills(Owner.CommanderID(), "upLegendary", 1)
	return true
