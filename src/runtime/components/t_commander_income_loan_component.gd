class_name TCommanderIncomeLoanComponent
extends TCommanderIncomeComponent
## Port of TCommanderIncomeLoanComponent (BaseConflict.EntityComponents.Shared.pas:553, implementation :2557).
## Multiplies the gold income by Factor for Duration ms; the first read after that restarts the timer for
## Duration * Factor / 2 ms with factor 0 (no gold income: the loan is paid back).

const L = preload("res://src/runtime/dws/dws_lib.gd")

var FFactor := 0.0  # single
var FTimer: TTimer


func Destroy() -> void:
	if FTimer != null:
		FTimer.Free()
	FTimer = null
	super()


func AdjustIncome(Income: RIncome) -> RIncome:
	var Result := super(Income)
	if not FTimer.Expired or FFactor > 0:
		Result.Gold = RParam.ToSingle(Result.Gold * FFactor)

		if FTimer.Expired:
			FTimer.SetIntervalAndStart(L.Round(FTimer.Interval * FFactor / 2))
			FFactor = 0.0
	return Result


## Time of income increase. Will reduce transform gold income for the duration * factor / 2 afterwards.
func Duration(DurationMs: int) -> TCommanderIncomeLoanComponent:
	FTimer = TTimer.new().CreateAndStart(DurationMs)
	return self


## Rate of income increase.
func Factor(NewFactor: float) -> TCommanderIncomeLoanComponent:
	FFactor = RParam.ToSingle(NewFactor)
	return self
