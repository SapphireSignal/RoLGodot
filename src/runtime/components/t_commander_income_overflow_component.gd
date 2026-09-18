class_name TCommanderIncomeOverflowComponent
extends TCommanderIncomeComponent
## Port of TCommanderIncomeOverflowComponent (BaseConflict.EntityComponents.Shared.pas:569, implementation :2534).
## Manages the overflow of income of a commander: gold beyond the gold cap becomes wood. Reads eiIncome last
## (epLast). WARNING: Component only for commander!


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	ChangeEventPriority(C.eiIncome, C.etRead, C.epLast, C.esGlobal)
	return self


func AdjustIncome(Income: RIncome) -> RIncome:
	var Result := super(Income)
	var GoldCap := RParam.AsSingle(Owner.Cap(C.reGold))
	var GoldBalance := minf(GoldCap, RParam.AsSingle(Owner.Balance(C.reGold)))
	var GoldIncome := Result.Gold
	if RParam.ToSingle(GoldBalance + GoldIncome) > GoldCap:
		Result.Gold = RParam.ToSingle(GoldCap - GoldBalance)
		Result.Wood = RParam.ToSingle(GoldIncome - Result.Gold)
	return Result
