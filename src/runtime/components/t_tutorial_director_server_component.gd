class_name TTutorialDirectorServerComponent
extends TEntityComponent
## Port of TTutorialDirectorServerComponent (GameServer/BaseConflict.EntityComponents.Server.pas:452, implementation
## :3688), server only: handles all actions in the tutorial, driven by game events (the client sends them as
## eiClientCommand [ccTutorialGameEvent, Eventname]). Freezing blocks the thinking (TThinkBlockComponent + eiStand)
## of every unit and building, also of new entities, and stops the global eiGameTick (epFirst); unfreezing frees
## every think block. It can stop wave spawns (eiWaveSpawn, epFirst), zero the income (eiIncome read, epLast), refill
## gold and charges, switch card costs off (TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES), give / set gold and
## wood ('give_gold_<n>' etc., n defaults to 100) and skip the warming (one eiGameTick).
## Port notes: HString.StrToInt = DelphiRtl.StrToIntDef.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FFrozen := false
var FNoWaveSpawn := false
var FIncomeDisabled := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnReadIncome", C.eiIncome, C.epLast, C.etRead, C.esGlobal))
	e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epFirst, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnNewEntity", C.eiNewEntity, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnGameTick", C.eiGameTick, C.epFirst, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnClientCommand", C.eiClientCommand, C.epLast, C.etTrigger, C.esGlobal))


func OnClientCommand(Command, Eventname) -> bool:
	if RParam.AsInteger(Command) == BC.ccTutorialGameEvent:
		GlobalEventbus().Trigger(C.eiGameEvent, [Eventname])
	return true


func OnGameEvent(Eventname) -> bool:
	var ServerGame = GlobalEventbus().Game
	var RealEventname: String = Eventname
	if RealEventname == C.GAME_EVENT_FREEZE_GAME:
		if not FFrozen:
			for Entity: TEntity in ServerGame.EntityManager.FilterEntities([C.upUnit, C.upBuilding], []):
				TThinkBlockComponent.new().Create(Entity)
				Entity.Eventbus.Trigger(C.eiStand, [])
		FFrozen = true
	elif RealEventname == C.GAME_EVENT_UNFREEZE_GAME:
		FFrozen = false
		var FreeThinkBlocks := func(Component) -> void:
			if Component is TThinkBlockComponent:
				Component.Free()
		for Entity: TEntity in ServerGame.EntityManager.FilterEntities([], []):
			Entity.Eventbus.Trigger(C.eiEnumerateComponents, [FreeThinkBlocks])
	elif RealEventname == C.GAME_EVENT_DEACTIVATE_SPAWNER:
		FNoWaveSpawn = true
	elif RealEventname == C.GAME_EVENT_ACTIVATE_SPAWNER:
		FNoWaveSpawn = false
	elif RealEventname == C.GAME_EVENT_DEACTIVATE_INCOME:
		FIncomeDisabled = true
	elif RealEventname == C.GAME_EVENT_ACTIVATE_INCOME:
		FIncomeDisabled = false
	elif RealEventname == C.GAME_EVENT_REFRESH_GOLD:
		for Commander: TEntity in ServerGame.Commanders:
			Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, 10000.0])
	elif RealEventname == C.GAME_EVENT_REFRESH_CHARGES:
		for Commander: TEntity in ServerGame.Commanders:
			for j in 256:  # 0..MAXBYTE
				var Cap = Commander.Blackboard.GetIndexedValue(C.eiResourceCap, [j], C.reCharge)
				if Cap != null:
					Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reCharge, 10000], [j])
				var DamageType = Commander.Blackboard.GetValue(C.eiDamageType, [j])
				if (DamageType if DamageType != null else []) == [C.dtCharge]:
					Commander.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(ATarget.CreateEmpty())], [j])
	elif RealEventname == C.GAME_EVENT_ACTIVATE_CARD_COST:
		TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES.duplicate()
	elif RealEventname == C.GAME_EVENT_DEACTIVATE_CARD_COST:
		TWelaEffectPayCostComponent.NOT_PAYED_RESOURCES = DSet.Union(
			TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES, [C.reCharge, C.reWood, C.reGold])
	elif RealEventname.begins_with(C.GAME_EVENT_GIVE_GOLD_PREFIX):
		var Amount := float(DelphiRtl.StrToIntDef(RealEventname.replace(C.GAME_EVENT_GIVE_GOLD_PREFIX, ""), 100))
		for Commander: TEntity in ServerGame.Commanders:
			Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, Amount])
	elif RealEventname.begins_with(C.GAME_EVENT_GIVE_WOOD_PREFIX):
		var Amount := float(DelphiRtl.StrToIntDef(RealEventname.replace(C.GAME_EVENT_GIVE_WOOD_PREFIX, ""), 100))
		for Commander: TEntity in ServerGame.Commanders:
			Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reWood, Amount])
	elif RealEventname.begins_with(C.GAME_EVENT_SET_GOLD_PREFIX):
		var Amount := float(DelphiRtl.StrToIntDef(RealEventname.replace(C.GAME_EVENT_SET_GOLD_PREFIX, ""), 100))
		for Commander: TEntity in ServerGame.Commanders:
			Commander.Eventbus.Write(C.eiResourceBalance, [C.reGold, Amount])
	elif RealEventname.begins_with(C.GAME_EVENT_SET_WOOD_PREFIX):
		var Amount := float(DelphiRtl.StrToIntDef(RealEventname.replace(C.GAME_EVENT_SET_WOOD_PREFIX, ""), 100))
		for Commander: TEntity in ServerGame.Commanders:
			Commander.Eventbus.Write(C.eiResourceBalance, [C.reWood, Amount])
	elif RealEventname == C.GAME_EVENT_SKIP_WARMING:
		GlobalEventbus().Trigger(C.eiGameTick, [])
	return true


## Frozen: no game tick reaches the later handlers.
func OnGameTick() -> bool:
	return not FFrozen


func OnNewEntity(NewEntity) -> bool:
	if FFrozen:
		TThinkBlockComponent.new().Create(NewEntity)
		NewEntity.Eventbus.Trigger(C.eiStand, [])
	return true


func OnReadIncome(_CommanderID, Previous):
	if FIncomeDisabled:
		return RIncome.Create(0, 0).ToRParam()
	return Previous


func OnWaveSpawn(_GridID, _Coordinate) -> bool:
	return not FNoWaveSpawn
