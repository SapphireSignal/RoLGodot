class_name ATarget
extends RefCounted
## Port of ATarget and ATargetHelper (BaseConflict.Types.Target.pas:58, implementation :531). An ATarget is an
## Array of RTarget; these are the helper's functions. ToRParam keeps the Array (RParam.FromArray copies it: the
## port copies the Array, not the RTargets, which are treated as values).


## Create(Item): one target from an RTarget, a TEntity, an entity ID or a Vector2.
static func Make(Item) -> Array:
	if Item is RTarget:
		return [Item]
	return [RTarget.Create(Item)]


## One empty target.
static func CreateEmpty() -> Array:
	return [RTarget.CreateEmpty()]


static func Count(Targets: Array) -> int:
	return Targets.size()


static func First(Targets: Array) -> RTarget:
	return Targets[0]


static func Append(Targets: Array, Values: Array) -> void:
	Targets.append_array(Values)


## Whether the target is in the list. Only works for entity targets.
static func Contains(Targets: Array, Target: RTarget) -> bool:
	if not Target.IsEntity():
		return false
	for Item in Targets:
		if Item.IsEntity() and Item.EntityID == Target.EntityID:
			return true
	return false


static func HasIndex(Targets: Array, Index: int) -> bool:
	return Index < Targets.size() and Index >= 0


static func ToRParam(Targets: Array) -> Array:
	return Targets.duplicate()


## RParam.AsATarget: empty = [].
static func FromRParam(p) -> Array:
	return RParam.AsArray(p)
