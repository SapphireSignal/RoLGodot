class_name TWelaEffectLinkPayCostMyselfComponentServer
extends TWelaReadyCostComponent
## Port of TWelaEffectLinkPayCostMyselfComponentServer (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:613,
## implementation :2251), server only. A ready component (TWelaReadyCostComponent: ready while the costs can be paid)
## that also pays: links cost eiResourceCost of its group per second of uptime, paid by the owner (paying group per
## resource). The first link pays once at once and starts the clock; each eiThinkChain (epFirst, so it needs a think
## impulse in its group) pays one cost per whole second passed (the rest carries over); breaking the last link pays
## the seconds passed first. A payment that empties a resource (balance > 0 before, <= 0 after) fires eiFire [owner]
## in FireOnEmpty's group. The clock is TTimeManager's until the game clock (GameTimeManager) is ported.
## Kept: the link count drops on every eiLinkBreak it sees, also for targets that had no link (it can go negative;
## the next establish resets it to 1).

var FLastAppliedTimestamp := 0
var FLinkCount := 0
var FOnEmptyTargetGroup: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnLinkEstablish", C.eiLinkEstablish, C.epLast, C.etTrigger))
	e.append(XEvent("OnLinkBreak", C.eiLinkBreak, C.epLast, C.etTrigger))
	e.append(XEvent("OnThink", C.eiThinkChain, C.epFirst, C.etTrigger))


func ApplyResources() -> void:
	# no links no resource is used
	if FLinkCount > 0:
		var CurrentTime := TTimeManager.GetTimeStamp()
		var LastedTime := CurrentTime - FLastAppliedTimestamp
		Pay(LastedTime / 1000)
		FLastAppliedTimestamp = CurrentTime - (LastedTime % 1000)


func FireOnEmpty(TargetGroup: Array) -> TWelaEffectLinkPayCostMyselfComponentServer:
	FOnEmptyTargetGroup = DSet.Make(TargetGroup)
	return self


## End resource consumption.
func OnLinkBreak(_Target) -> bool:
	# if last link is going to be broken, refresh resource consumption, to be adequate
	if FLinkCount == 1:
		ApplyResources()
	FLinkCount -= 1
	return true


## Start resource consumption.
func OnLinkEstablish(_Source, _Dest) -> bool:
	if FLinkCount <= 0:
		FLinkCount = 1
		FLastAppliedTimestamp = TTimeManager.GetTimeStamp()
		# links cost initial for building
		Pay(1)
	else:
		FLinkCount += 1
	return true


## Apply resource consumption.
func OnThink() -> bool:
	ApplyResources()
	return true


func Pay(Times: int) -> void:
	var Cost := RParam.AsArray(Eventbus().Read(C.eiResourceCost, [], ComponentGroup))
	if not Cost.is_empty():
		var HasBeenDepleted := false
		for i in Cost:
			var CostToPay
			if BC.IsFloatResource(i.ResourceType):
				CostToPay = RParam.ToSingle(-RParam.AsSingle(i.Amount) * Times)
			else:
				CostToPay = -RParam.AsInteger(i.Amount) * Times

			var Balance = Owner.Balance(i.ResourceType, GetPayingGroup(i.ResourceType))
			var WasDepleted := BC.ResourceCompare(i.ResourceType, Balance, C.coLowerEqual, 0)

			Eventbus().Trigger(C.eiResourceTransaction, [i.ResourceType, CostToPay], GetPayingGroup(i.ResourceType))

			Balance = Owner.Balance(i.ResourceType, GetPayingGroup(i.ResourceType))
			var IsDepleted := BC.ResourceCompare(i.ResourceType, Balance, C.coLowerEqual, 0)
			if not WasDepleted and IsDepleted:
				HasBeenDepleted = true
		if HasBeenDepleted and not FOnEmptyTargetGroup.is_empty():
			Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], FOnEmptyTargetGroup)
