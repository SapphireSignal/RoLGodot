class_name RResourceCost
extends RefCounted
## Port of RResourceCost and the AResourceCostHelper (BaseConflict.Types.Shared.pas:32, implementation :183).
## An AResourceCost is an Array of RResourceCost; RParam.FromArray (ToRParam) keeps it as that Array.

var ResourceType := 0  # EnumResource
var Amount = null  # RParam


func _init(resource_type: int = 0, amount = null) -> void:
	ResourceType = resource_type
	Amount = amount


## AResourceCostHelper.Count
static func Count(Cost: Array) -> int:
	return Cost.size()


## AResourceCostHelper.GetValue: the first entry of that type, or RPARAM_EMPTY.
static func GetValue(Cost: Array, ResourceType: int):
	for c in Cost:
		if c.ResourceType == ResourceType:
			return c.Amount
	return RParam.RPARAMEMPTY


## AResourceCostHelper.TryGetValue(ResourceType, out Amount): returns [found, Amount].
static func TryGetValue(Cost: Array, ResourceType: int) -> Array:
	for c in Cost:
		if c.ResourceType == ResourceType:
			return [true, c.Amount]
	return [false, RParam.RPARAMEMPTY]


## AResourceCostHelper.ToRParam
static func ToRParam(Cost: Array):
	return Cost
