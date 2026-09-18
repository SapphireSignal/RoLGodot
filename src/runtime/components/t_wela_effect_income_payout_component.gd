class_name TWelaEffectIncomePayoutComponent
extends TWelaEffectComponent
## Port of TWelaEffectIncomePayoutComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.Special.pas:29,
## implementation :80), server only. Gives each commander its income: on fire, for every commander in
## Game.Commanders order, reads the global eiIncome [CommanderID] (no income components: 0 / 0) and books its gold
## and wood on the commander (eiResourceTransaction, groupless).


func Fire(_Targets: Array) -> void:
	for Commander in GlobalEventbus().Game.Commanders:
		var Income := RIncome.FromRParam(GlobalEventbus().Read(C.eiIncome, [Commander.ID]))
		Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, RParam.ToSingle(Income.Gold)])
		Commander.Eventbus.Trigger(C.eiResourceTransaction, [C.reWood, RParam.ToSingle(Income.Wood)])
