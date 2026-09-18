class_name TCommanderIncomeDefaultComponent
extends TCommanderIncomeComponent
## Port of TCommanderIncomeDefaultComponent (BaseConflict.EntityComponents.Shared.pas:543, implementation :2505).
## Gold income = its group's eiResourceCost gold + eiWelaDamage (gold per income upgrade) * reIncomeUpgrade balance.
## Reads eiIncome first (epFirst).


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	ChangeEventPriority(C.eiIncome, C.etRead, C.epFirst, C.esGlobal)
	return self


func AdjustIncome(Income: RIncome) -> RIncome:
	var Result := super(Income)
	# default income
	var Cost := RParam.AsArray(Eventbus().Read(C.eiResourceCost, [], ComponentGroup))
	var Found: Array = RResourceCost.TryGetValue(Cost, C.reGold)
	if not Found[0]:
		push_error("TCommanderIncomeComponent.OnReadIncome: eiResourceCost does not exist or contain RES_GOLD!")
	var GoldIncome := RParam.AsSingle(Found[1])
	# income per IncomeUpgrade
	var GoldIncomePerIncomeUpgrade := RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup))
	var CurrentGoldIncomeUpgrades := RParam.AsInteger(Owner.Balance(C.reIncomeUpgrade))
	GoldIncome = RParam.ToSingle(GoldIncome + RParam.ToSingle(GoldIncomePerIncomeUpgrade * CurrentGoldIncomeUpgrades))

	Result.Gold = RParam.ToSingle(Result.Gold + GoldIncome)
	return Result
