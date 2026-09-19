class_name TCommanderIncomeComponent
extends TGDEntityComponent
## Port of TCommanderIncomeComponent (BaseConflict.EntityComponents.Shared.pas:531, implementation :2490).
## Manages the default income of a commander. WARNING: Component only for commander!
## eiIncome (global read, [CommanderID]) returns an RIncome; each income component of that commander adjusts it.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnReadIncome", C.eiIncome, C.epMiddle, C.etRead, C.esGlobal))


## Virtual: the income after this component. Works on the copy it gets.
func AdjustIncome(Income: RIncome) -> RIncome:
	return Income


## Set up default income.
func OnReadIncome(CommanderID, Previous):
	if Owner.CommanderID() == RParam.AsInteger(CommanderID):
		return AdjustIncome(RIncome.FromRParam(Previous)).ToRParam()
	return Previous
