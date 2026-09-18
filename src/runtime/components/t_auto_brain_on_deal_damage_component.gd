class_name TAutoBrainOnDealDamageComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnDealDamageComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:670,
## implementation :2734), server only. At eiDamageDone [Amount, DamageType, TargetEntity] (epLast), if the brain can
## think and eiIsReady of FireInGroup allows, picks the targets (the damaged entity; RedirectToSelf: the owner;
## RedirectToSource: eiLinkSource) and, if eiWelaTargetPossible there allows: WriteAmountTo(Event) writes the
## amount into that event of the fire group (AddAmountAtWrite: amount × eiWelaModifier of its own group (default
## 1) + the value already there), then fires eiFire at them (unless DontFire).
## Port note: the original's Fire(Amount, TargetEntity) (reintroduce) is FireDamage here.

var FWriteAmount := false
var FRedirectToSelf := false
var FRedirectToSource := false
var FDontFire := false
var FAddAmountAtWrite := false
var FWriteAmountTo: int = 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epLast, C.etTrigger))


func FireDamage(Amount: float, TargetEntity) -> void:
	if not CanThink() or not RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FFireGroup)):
		return

	var Targets
	if FRedirectToSource:
		Targets = Eventbus().Read(C.eiLinkSource, [])
	elif FRedirectToSelf:
		Targets = ATarget.ToRParam(ATarget.Make(Owner))
	else:
		Targets = ATarget.ToRParam(ATarget.Make(TargetEntity))

	if _TargetsPossible(Targets, FFireGroup):
		if FWriteAmount:
			if FAddAmountAtWrite:
				Amount = RParam.ToSingle(Amount * RParam.AsSingleDefault(
					Eventbus().Read(C.eiWelaModifier, [], ComponentGroup), 1.0))
				Amount = RParam.ToSingle(Amount + RParam.AsSingle(Owner.Blackboard.GetValue(FWriteAmountTo, FFireGroup)))
			Eventbus().Write(FWriteAmountTo, [Amount], FFireGroup)
		if not FDontFire:
			Eventbus().Trigger(C.eiFire, [Targets], FFireGroup)


func OnDamageDone(Amount, _DamageType, TargetEntity) -> bool:
	FireDamage(RParam.AsSingle(Amount), TargetEntity)
	return true


## For links.
func RedirectToSource() -> TAutoBrainOnDealDamageComponent:
	FRedirectToSource = true
	return self


func RedirectToSelf() -> TAutoBrainOnDealDamageComponent:
	FRedirectToSelf = true
	return self


func WriteAmountTo(Event: int) -> TAutoBrainOnDealDamageComponent:
	FWriteAmount = true
	FWriteAmountTo = Event
	return self


func AddAmountAtWrite() -> TAutoBrainOnDealDamageComponent:
	FAddAmountAtWrite = true
	return self


func DontFire() -> TAutoBrainOnDealDamageComponent:
	FDontFire = true
	return self
