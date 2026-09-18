class_name TWelaTargetingRadialComponent
extends TWelaTargetingComponent
## Port of TWelaTargetingRadialComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:116,
## implementation :1653), server only. Fills the free target slots (eiWelaTargetCount, default 1) with the best
## targets within eiWelaRange (or RangeFromEvent) + own collision radius: highest efficiency, then not upLowPrio,
## then nearest (or most distant, or nearest to half the range). Current targets are kept. Every new entity target
## gets eiWelaYoureMyTarget [Owner]. With PicksRandomTargets the in-range targets are picked at random instead.
## Cone(Direction, Angle) only takes targets whose circle reaches into the cone.
## Port notes: sorted with DelphiSort (ties keep the original's order); distances are rounded to singles as the
## original's RVector2 methods return them.

var FIgnoreOwnCollisionradius := false
var FPrioritizeMostDistant := false
var FPrioritizeMiddleDistant := false
var FConeDir := Vector2.ZERO
var FCone := 0.0
var FRangeEvent: int = C.eiWelaRange


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FRangeEvent = C.eiWelaRange
	return self


func RangeFromEvent(EventIdentifier: int) -> TWelaTargetingRadialComponent:
	FRangeEvent = EventIdentifier
	return self


func PrioritizeMostDistant() -> TWelaTargetingRadialComponent:
	FPrioritizeMostDistant = true
	return self


func PrioritizeMiddleDistant() -> TWelaTargetingRadialComponent:
	FPrioritizeMiddleDistant = true
	return self


func IgnoreOwnCollisionradius() -> TWelaTargetingRadialComponent:
	FIgnoreOwnCollisionradius = true
	return self


## Cone(Direction: Vector2, Angle) or Cone(DirectionX, DirectionZ, Angle).
func Cone(DirectionOrX, AngleOrZ, Angle = null) -> TWelaTargetingRadialComponent:
	if Angle == null:
		FConeDir = DirectionOrX
		FCone = RParam.ToSingle(AngleOrZ)
	else:
		FConeDir = Vector2(RParam.ToSingle(DirectionOrX), RParam.ToSingle(AngleOrZ))
		FCone = RParam.ToSingle(Angle)
	return self


## RVector2.Normalize: the zero vector stays zero.
static func Normalize(v: Vector2) -> Vector2:
	if v.x == 0 and v.y == 0:
		return Vector2.ZERO
	return v / v.length()


## RVector2.InnerAngle: 0 if either vector is zero.
static func InnerAngle(a: Vector2, b: Vector2) -> float:
	if (b.x == 0 and b.y == 0) or (a.x == 0 and a.y == 0):
		return 0.0
	return RParam.ToSingle(acos(maxf(-1, minf(1, a.dot(b) / b.length() / a.length()))))


func _ConeFilter(Entity, EntityPos: Vector2) -> float:
	var Result := FetchEfficiency(Entity, ComponentGroup)
	if Result >= 0 and FCone > 0:
		var entityRadius: float = Entity.CollisionRadius
		var entityPosition: Vector2 = Entity.Position
		var entityFront := Normalize(entityPosition - EntityPos)
		var entityWidthAngle := RParam.ToSingle(atan(entityRadius / maxf(0.01, RParam.ToSingle(entityPosition.distance_to(EntityPos)))))
		var angleBetween := InnerAngle(FConeDir, entityFront)
		if not (angleBetween - entityWidthAngle <= FCone / 2):
			Result = -1
	return Result


func _IsLowPrio(Target: RTarget) -> bool:
	return RParam.AsSet(Target.GetTargetEntity(TargetGame()).Eventbus.Read(C.eiUnitProperties, [])).has(C.upLowPrio)


func _Compare(L: RTargetWithEfficiency, R: RTargetWithEfficiency, EntityPos: Vector2, Range: float) -> int:
	# the higher the better
	var Result := -int(signf(L.Efficiency - R.Efficiency))
	if Result == 0:
		if _IsLowPrio(L.Target):
			Result += 1
		if _IsLowPrio(R.Target):
			Result -= 1
		if Result == 0:
			var Game = TargetGame()
			if FPrioritizeMiddleDistant:
				# prefer unit nearest to half range
				var DL := RParam.ToSingle(L.Target.GetTargetPosition(Game).distance_to(EntityPos))
				var DR := RParam.ToSingle(R.Target.GetTargetPosition(Game).distance_to(EntityPos))
				Result = int(signf(absf(DL - Range / 2) - absf(DR - Range / 2)))
			else:
				# the lower the better
				var DL := RParam.ToSingle(L.Target.GetTargetPosition(Game).distance_squared_to(EntityPos))
				var DR := RParam.ToSingle(R.Target.GetTargetPosition(Game).distance_squared_to(EntityPos))
				Result = int(signf(DL - DR))
				if FPrioritizeMostDistant:
					Result = -Result
	return Result


func UpdateTargets(CurrentList: Array) -> void:
	var MaxTargets := RParam.AsIntegerDefault(Eventbus().Read(C.eiWelaTargetCount, [], ComponentGroup), 1)
	if MaxTargets <= 0:
		return
	var MaxNew := 10000 if FMaxNewTargetCount <= 0 else FMaxNewTargetCount
	if CurrentList.size() >= MaxTargets:
		return
	var EntityPos: Vector2 = Owner.Position
	var Filter := _ConeFilter.bind(EntityPos)
	# Range = WeaponRange + OwnSize + OpponentSize
	var Range := RParam.AsSingle(Eventbus().Read(FRangeEvent, [], ComponentGroup))
	if not FIgnoreOwnCollisionradius:
		Range = RParam.ToSingle(Range + Owner.CollisionRadius)

	var Enemies = GlobalEventbus().Read(C.eiEnemiesInRangeEfficiency, [EntityPos, Range, Owner.TeamID(),
		FTargetTeamConstraint, Filter])
	if Enemies == null:
		return
	if FPickRandom:
		var PossibleTargets: Array = []
		for Target in Enemies:
			assert(Target.Target.IsEntity(), "TWelaTargetingRadialComponent.UpdateTargets: Random picks of non-entities not implemented yet!")
			PossibleTargets.append(Target.Target.GetTargetEntity(TargetGame()))
		PickRandomTargets(CurrentList, PossibleTargets)
	else:
		# only prioritize if not all targets are taken anyway
		if MaxTargets < Enemies.size():
			DelphiSort.Sort(Enemies, _Compare.bind(EntityPos, Range))
		var i := 0
		while i < Enemies.size() and CurrentList.size() < MaxTargets and MaxNew > 0:
			var Target: RTarget = Enemies[i].Target
			if not ContainsTarget(CurrentList, Target):
				CurrentList.append(Target)
				var Entity = Target.TryGetTargetEntity(TargetGame())
				if Entity != null:
					Entity.Eventbus.Trigger(C.eiWelaYoureMyTarget, [Owner])
				MaxNew -= 1
			i += 1


func ValidateTarget(Target: RTarget) -> bool:
	var Game = TargetGame()
	var EntityPos: Vector2 = Owner.Position
	var Efficiency := FetchEfficiency(Target.GetTargetEntity(Game), FValidateGroup)
	if Efficiency >= 0:
		var Weaponrange := RParam.AsSingle(Eventbus().Read(FRangeEvent, [], ComponentGroup))
		if not FIgnoreOwnCollisionradius:
			Weaponrange = RParam.ToSingle(Weaponrange + Owner.CollisionRadius)
		if Target.IsEntity():
			Weaponrange = RParam.ToSingle(Weaponrange + Target.GetTargetEntity(Game).CollisionRadius)
		var Distance := RParam.ToSingle(Target.GetTargetPosition(Game).distance_to(EntityPos))
		if Distance <= Weaponrange:
			return true
	return false
