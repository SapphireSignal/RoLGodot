class_name TProjectileEventRedirecter
extends TGDEntityComponent
## Port of TProjectileEventRedirecter (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:660, implementation
## :2626), server only. A projectile notifies its creator (eiCreator) of some things, like dealt damage for life
## leech: eiWillDealDamage asks the creator (a non-empty answer replaces the previous value), eiDamageDone and
## eiYouHaveKilledMeShameOnYou are passed on. If the creator is gone the kill is counted for the projectile's
## commander under the creator's script file name (Game.Statistics, when the game has one).
## TWelaEffectProjectileComponent adds it to every projectile it spawns.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWillDealDamage", C.eiWillDealDamage, C.epLast, C.etRead))
	e.append(XEvent("OnDoneDamage", C.eiDamageDone, C.epLast, C.etTrigger))
	e.append(XEvent("OnYouHaveKilledMeShameOnYou", C.eiYouHaveKilledMeShameOnYou, C.epLast, C.etTrigger))


func GetCreator():
	var Game = GlobalEventbus().Game
	if Game == null:
		return null
	return Game.EntityManager.GetEntityByID(RParam.AsInteger(Eventbus().Read(C.eiCreator, [])))


func GetCreatorScriptFileName() -> String:
	return RParam.AsString(Eventbus().Read(C.eiCreatorScriptFileName, []))


func OnWillDealDamage(Amount, DamageTypes, TargetEntity, Previous):
	var Result = Previous
	var Creator = GetCreator()
	if Creator != null:
		var temp = Creator.Eventbus.Read(C.eiWillDealDamage, [Amount, DamageTypes, TargetEntity])
		if not RParam.IsEmpty(temp):
			Result = temp
	return Result


func OnDoneDamage(Amount, DamageType, TargetEntity) -> bool:
	var Creator = GetCreator()
	if Creator != null:
		Creator.Eventbus.Trigger(C.eiDamageDone, [Amount, DamageType, TargetEntity])
	return true


func OnYouHaveKilledMeShameOnYou(KilledUnitID) -> bool:
	var Creator = GetCreator()
	if Creator != null:
		Creator.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [KilledUnitID])
	else:
		# creator is already dead, so we have to count statistic here manually
		var Game = GlobalEventbus().Game
		var Statistics = Game.get("Statistics") if Game != null else null
		if Statistics != null:
			Statistics.UnitKills(Owner.CommanderID(), GetCreatorScriptFileName())
	return true
