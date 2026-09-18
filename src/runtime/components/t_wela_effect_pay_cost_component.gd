class_name TWelaEffectPayCostComponent
extends TWelaEffectComponent
## Port of TWelaEffectPayCostComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:306,
## implementation :1949), server only. On fire pays every eiResourceCost of the group the fire was called to
## (except NOT_PAYED_RESOURCES) with eiResourceSubtraction [Resource, Amount] on the payer (owner, or its owning
## commander with CommanderPays) in the paying group of that resource (default: its own group; CommanderPays: []).
## ConsumesAll pays the payer's whole balance instead; ConvertResource refunds the paid amount as another resource
## (eiResourceTransaction). Costs are paid in the order eiResourceCost returns them (sorted by resource in the port).
## NOT_PAYED_RESOURCES: a threadvar per game thread in the original, set to the default at game start and changed
## by the card-cost game events; one static var here (the game sets it, phase 3).

const DEFAULT_NOT_PAYED_RESOURCES = [C.reLevel, C.reTier]
static var NOT_PAYED_RESOURCES: Array = DEFAULT_NOT_PAYED_RESOURCES.duplicate()

## EnumResource -> SetComponentGroup
var FPayingGroup := {}
var FDefaultPayingGroup: Array = []
var FRedirectToCommander := false
var FConsumesAll := false
## EnumResource -> EnumResource
var FResourceConversion := {}


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FPayingGroup = {}
	FDefaultPayingGroup = ComponentGroup
	FResourceConversion = {}
	return self


func GetPayingGroup(ResType: int) -> Array:
	return FPayingGroup.get(ResType, FDefaultPayingGroup)


func Fire(_Targets: Array) -> void:
	var Cost: Array = RParam.AsArray(Eventbus().Read(C.eiResourceCost, [], TEventbus.CurrentEvent_CalledToGroup))
	if Cost.is_empty():
		push_error("TWelaEffectPayCostComponent: Found paying component, but no cost! Added TResourceManagerComponent to calling entity?")
		return
	var PayingEntity = null
	if FRedirectToCommander:
		var game = GlobalEventbus().Game
		PayingEntity = game.EntityManager.GetOwningCommander(Owner) if game != null else null
	else:
		PayingEntity = Owner
	if PayingEntity == null:
		push_error("TWelaEffectPayCostComponent.Fire: Could not find payer, should never happen!")
		return
	for i in Cost:
		if not NOT_PAYED_RESOURCES.has(i.ResourceType):
			var Amount
			# if consuming all, ignore amount and take whole balance
			if FConsumesAll:
				Amount = PayingEntity.Eventbus.Read(C.eiResourceBalance, [i.ResourceType], GetPayingGroup(i.ResourceType))
			else:
				Amount = i.Amount
			# pay
			PayingEntity.Eventbus.Trigger(C.eiResourceSubtraction, [i.ResourceType, Amount], GetPayingGroup(i.ResourceType))
			# refund resources optionally
			if FResourceConversion.has(i.ResourceType):
				PayingEntity.Eventbus.Trigger(C.eiResourceTransaction, [FResourceConversion[i.ResourceType], Amount], GetPayingGroup(i.ResourceType))


## Set a special group for paying the resources. Default is the ComponentGroup of this component.
func SetPayingGroup(Group = []) -> TWelaEffectPayCostComponent:
	FDefaultPayingGroup = DSet.Make(Group)
	return self


## Set a special group for paying a certain Resource.
func SetPayingGroupForType(ResourceType: int = 0, Group = []) -> TWelaEffectPayCostComponent:
	FPayingGroup[ResourceType] = DSet.Make(Group)
	return self


## All resources of chosen costs are payed disregarding the amount of the costs.
func ConsumesAll() -> TWelaEffectPayCostComponent:
	FConsumesAll = true
	return self


## The commander pays for this effect. Changes paying group to []!
func CommanderPays() -> TWelaEffectPayCostComponent:
	FDefaultPayingGroup = []
	FRedirectToCommander = true
	return self


func ConvertResource(FromResource: int = 0, ToResource: int = 0) -> TWelaEffectPayCostComponent:
	FResourceConversion[FromResource] = ToResource
	return self
