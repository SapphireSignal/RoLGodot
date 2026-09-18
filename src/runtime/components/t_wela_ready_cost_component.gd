class_name TWelaReadyCostComponent
extends TWelaReadyComponent
## Port of TWelaReadyCostComponent (BaseConflict.EntityComponents.Shared.Wela.pas:605, implementation :1843).
## Ready while the payer can pay every eiResourceCost of ValueGroup (eiResourceSubtraction read in the paying group
## of that resource). The payer is the owner, or its commander (CommanderPays, paying group []). CostsCap: every
## cost except level and tier is the payer's current cap.

var FPayingGroup := {}  # EnumResource -> SetComponentGroup
var FDefaultPayingGroup: Array = []
var FValueGroup: Array = []
var FRedirectToCommander := false
var FCostsCap := false


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FValueGroup = ComponentGroup
	FPayingGroup = {}
	FDefaultPayingGroup = ComponentGroup
	return self


func GetPayingGroup(ResType: int) -> Array:
	return FPayingGroup.get(ResType, FDefaultPayingGroup)


func IsReady() -> bool:
	var Result := true
	var Costs := RParam.AsArray(Eventbus().Read(C.eiResourceCost, [], FValueGroup))
	if not Costs.is_empty():
		var PayingEntity = Owner
		if FRedirectToCommander:
			var game = GlobalEventbus().Game
			PayingEntity = game.EntityManager.GetOwningCommander(Owner) if game != null else null
		# the original asserts a payer here (debug builds only)
		if PayingEntity != null:
			for Cost in Costs:
				var Amount = Cost.Amount  # a copy of the record in the original: the cost list stays unchanged
				if FCostsCap and not (Cost.ResourceType in [C.reLevel, C.reTier]):
					Amount = PayingEntity.Cap(Cost.ResourceType, GetPayingGroup(Cost.ResourceType))
				Result = Result and RParam.AsBoolean(PayingEntity.Eventbus.Read(C.eiResourceSubtraction,
						[Cost.ResourceType, Amount], GetPayingGroup(Cost.ResourceType)))
	return Result


## Set a special group for paying the resources. Default is the ComponentGroup of this component.
func SetPayingGroup(Group: Array) -> TWelaReadyCostComponent:
	FDefaultPayingGroup = DSet.Make(Group)
	return self


## Set a special group for paying a certain Resource.
func SetPayingGroupForType(ResourceType: int, Group: Array) -> TWelaReadyCostComponent:
	FPayingGroup[ResourceType] = DSet.Make(Group)
	return self


## The commander pays for this effect. Changes paying group to []!
func CommanderPays() -> TWelaReadyCostComponent:
	FDefaultPayingGroup = []
	FRedirectToCommander = true
	return self


## Costs the current cap.
func CostsCap() -> TWelaReadyCostComponent:
	FCostsCap = true
	return self


## Determines the group where the costs are fetched from. Defaults to ComponentGroup.
func ValueGroup(Group: Array) -> TWelaReadyCostComponent:
	FValueGroup = DSet.Make(Group)
	return self
