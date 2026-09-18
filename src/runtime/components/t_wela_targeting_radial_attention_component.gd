class_name TWelaTargetingRadialAttentionComponent
extends TWelaTargetingComponent
## Port of TWelaTargetingRadialAttentionComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:82,
## implementation :1567), server only. Replaces the targets with the one entity to approach: among the possible
## targets (efficiency >= 0) within eiAttentionrange × 1.2, the one with the least weighted lane distance
## (TLane.GetWeightedDistance of eiGetLane, preferring enemies straight along the lane) or, without a lane or with
## DisableStraightPreference, the nearest; kept only if it is within eiAttentionrange itself. Approach brains use it.
## Validation: efficiency > 0 and the target position within eiAttentionrange (no collision radii).
## Port note: TAdvancedList.Min keeps the first of equal minima; the mapped values are singles, as in the original.

const RANGE_EXTENSION_FACTOR = 1.2  # single in the original: rounded where used

var FDisableStraightPreference := false


func DisableStraightPreference() -> TWelaTargetingRadialAttentionComponent:
	FDisableStraightPreference = true
	return self


func _PossibleFilter(Entity) -> bool:
	return FetchEfficiency(Entity, ComponentGroup) >= 0


## TAdvancedList<TEntity>.Min(Mapping): the first entity with the least mapped value, or null.
static func _MinEntity(List: Array, Mapping: Callable):
	if List.is_empty():
		return null
	var minI := 0
	var currentMin := RParam.ToSingle(Mapping.call(List[0]))
	for i in range(1, List.size()):
		var Value := RParam.ToSingle(Mapping.call(List[i]))
		if currentMin > Value:
			minI = i
			currentMin = Value
	return List[minI]


func UpdateTargets(CurrentList: Array) -> void:
	CurrentList.clear()
	var AttentionRange := RParam.AsSingle(Eventbus().Read(C.eiAttentionrange, [], ComponentGroup))
	var MyPos: Vector2 = Owner.Position
	var Enemies = GlobalEventbus().Read(C.eiEntitiesInRange, [MyPos,
		RParam.ToSingle(AttentionRange * RParam.ToSingle(RANGE_EXTENSION_FACTOR)), Owner.TeamID(),
		FTargetTeamConstraint, _PossibleFilter])
	if Enemies == null:
		return
	var Enemy
	var Lane = Eventbus().Read(C.eiGetLane, [])
	if Lane != null and not FDisableStraightPreference:
		# take lane into account to prefer enemies in lane direction
		Enemy = _MinEntity(Enemies, func(ent): return Lane.GetWeightedDistance(MyPos, ent.Position))
	else:
		# no lane => plain looking in direct surroundings
		Enemy = _MinEntity(Enemies, func(ent): return MyPos.distance_to(ent.Position))
	if Enemy != null and RParam.ToSingle(Enemy.Position.distance_to(MyPos)) > AttentionRange:
		Enemy = null
	# only if best target is in real attention range start to approach
	if Enemy != null:
		CurrentList.append(RTarget.Create(Enemy))


func ValidateTarget(Target: RTarget) -> bool:
	var Game = TargetGame()
	var EntityPos: Vector2 = Owner.Position
	var Efficiency := FetchEfficiency(Target.GetTargetEntity(Game), FValidateGroup)
	var AttentionRange := RParam.AsSingle(Eventbus().Read(C.eiAttentionrange, [], ComponentGroup))
	if Efficiency <= 0 or RParam.ToSingle(Target.GetTargetPosition(Game).distance_to(EntityPos)) > AttentionRange:
		return false
	return true
