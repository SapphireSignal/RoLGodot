class_name TWarheadSpottyResourceComponent
extends TWarheadSpottyComponent
## Port of TWarheadSpottyResourceComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:159,
## implementation :383), server only. Changes a resource (default reGold) of each target entity (TargetsOwningCommander:
## of its owning commander, skipped if none) in the target group (default [], plus the groups its eiWelaSearch finds
## for SearchForWelaBeacon).
## Amount: from SetResourceSource (default eiWeladamage of its group, rounded for int resources; eiResourceCost:
## that resource's cost on its owner, no group; eiNone: 1) × SetFactor (rounded for int resources);
## AmountIsPercentage: that fraction of the target's cap (rounded for int resources). Delphi Round = banker's.
## Then: ChangesMax: eiResourceCapTransaction [Res, Amount, DontFillCap] (SetsResourceToValue: write eiResourceCap);
## ChangesCost: adds to the blackboard cost and writes eiResourceCost; else eiResourceTransaction (SetsResourceToValue:
## write the balance 0 first; ResetResource: eiResourceReset instead).

const BC = preload("res://src/runtime/base_conflict_constants.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")

var FFactor := 1.0
var FSource := C.eiWelaDamage
var FResType := C.reGold
var FResetResource := false
var FSetResource := false
var FTargetsOwningCommander := false
var FTargetsCost := false
var FTargetsMax := false
var FDontFillCap := false
var FAmountIsPercentage := false
var FTargetGroup: Array = []
var FLookForGroup: Array = []  # SetUnitProperty


func ApplyEffect(Entity: TEntity) -> void:
	# remap target to owning commander
	if FTargetsOwningCommander:
		var game = GlobalEventbus().Game
		Entity = game.EntityManager.GetOwningCommander(Entity) if game != null else null
		if Entity == null:
			return
	var IsInt := BC.IsIntResource(FResType)
	var Res = 0.0
	# take amount from chosen source
	match FSource:
		C.eiNone:
			Res = 1 if IsInt and not FAmountIsPercentage else 1.0
		C.eiWelaDamage:
			var Damage := RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup))
			Res = L.Round(Damage) if IsInt and not FAmountIsPercentage else Damage
		C.eiResourceCost:
			var Cost := RParam.AsArray(Eventbus().Read(C.eiResourceCost, []))
			var Found := RResourceCost.TryGetValue(Cost, FResType)
			if Found[0]:
				Res = Found[1]
			else:
				push_error("TWarheadSpottyResourceComponent.ApplyEffect: eiResourceCost does not exist or contain the target resource type!")
		_:
			push_error("TWarheadSpottyResourceComponent.ApplyEffect: event %d not supported atm!" % FSource)
	# set target group
	var TargetGroup: Array = FTargetGroup
	if not FLookForGroup.is_empty():
		TargetGroup = DSet.Union(TargetGroup, RParam.AsSet(Entity.Eventbus.Read(C.eiWelaSearch, [FLookForGroup.duplicate()])))
	# apply factor for increase/decrease amount
	var Amount
	if IsInt and not FAmountIsPercentage:
		Amount = L.Round(RParam.AsInteger(Res) * FFactor)
	else:
		Amount = RParam.ToSingle(RParam.AsSingle(Res) * FFactor)
	if FAmountIsPercentage:
		Amount = RParam.ToSingle(BC.ResourceAsSingle(FResType, Entity.Eventbus.Read(C.eiResourceCap, [FResType], TargetGroup)) * RParam.AsSingle(Amount))
		if IsInt:
			Amount = L.Round(RParam.AsSingle(Amount))
	# not set or add resource
	if FTargetsMax:
		if FSetResource:
			Entity.Eventbus.Write(C.eiResourceCap, [FResType, Amount], TargetGroup)
		else:
			Entity.Eventbus.Trigger(C.eiResourceCapTransaction, [FResType, Amount, FDontFillCap], TargetGroup)
	elif FTargetsCost:
		if IsInt:
			Amount = RParam.AsInteger(Entity.Blackboard.GetIndexedValue(C.eiResourceCost, TargetGroup, FResType)) + RParam.AsInteger(Amount)
		else:
			Amount = RParam.ToSingle(RParam.AsSingle(Entity.Blackboard.GetIndexedValue(C.eiResourceCost, TargetGroup, FResType)) + RParam.AsSingle(Amount))
		Entity.Eventbus.Write(C.eiResourceCost, [FResType, Amount], TargetGroup)
	elif FSetResource:
		Entity.Eventbus.Write(C.eiResourceBalance, [FResType, 0 if IsInt else 0.0], TargetGroup)
		Entity.Eventbus.Trigger(C.eiResourceTransaction, [FResType, Amount], TargetGroup)
	elif FResetResource:
		Entity.Eventbus.Trigger(C.eiResourceReset, [FResType], TargetGroup)
	else:
		Entity.Eventbus.Trigger(C.eiResourceTransaction, [FResType, Amount], TargetGroup)


## All Resourcetypes are constants defined in BaseConflict.Constants.pas. Defaults to RES_GOLD.
func SetResourceType(ResType: int = 0) -> TWarheadSpottyResourceComponent:
	FResType = ResType
	return self


## Instead of adding the resource, it will be set to the value.
func SetsResourceToValue() -> TWarheadSpottyResourceComponent:
	FSetResource = true
	return self


## Specify the event (eiWeladamage or eiResourceCost) to retrieve the amount. If set to eiNone 1 is taken.
func SetResourceSource(Eventname: int = 0) -> TWarheadSpottyResourceComponent:
	FSource = Eventname
	return self


func ResetResource() -> TWarheadSpottyResourceComponent:
	FResetResource = true
	return self


## The amount describes a percentage.
func AmountIsPercentage() -> TWarheadSpottyResourceComponent:
	FAmountIsPercentage = true
	return self


## Sets a factor to be multiplied with the amount.
func SetFactor(Factor: float = 1.0) -> TWarheadSpottyResourceComponent:
	FFactor = RParam.ToSingle(Factor)
	return self


## Set the group where the resources are applied to. Default is [].
func TargetGroup(Group = []) -> TWarheadSpottyResourceComponent:
	FTargetGroup = DSet.Make(Group)
	return self


## Set target group to look for beacon.
func SearchForWelaBeacon(Properties = []) -> TWarheadSpottyResourceComponent:
	FLookForGroup = DSet.Make(Properties)
	return self


## Remaps the target of the resource adjustment to the owning commander of the actual target.
func TargetsOwningCommander() -> TWarheadSpottyResourceComponent:
	FTargetsOwningCommander = true
	return self


## Instead of eiResourceBalance the eiResourceCost will be changed.
func ChangesCost() -> TWarheadSpottyResourceComponent:
	FTargetsCost = true
	return self


## Instead of eiResourceBalance the eiResourceCap will be changed.
func ChangesMax() -> TWarheadSpottyResourceComponent:
	FTargetsMax = true
	return self


## If this component changes the maximum, it dont fill the balance according to the cap change.
func DontFillCap() -> TWarheadSpottyResourceComponent:
	FDontFillCap = true
	return self
