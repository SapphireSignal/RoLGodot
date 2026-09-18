class_name TWarheadSplashComponent
extends TWarheadComponent
## Port of TWarheadSplashComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:222, implementation
## :655), server only. Master class of the warheads that hit every entity within eiWelaAreaOfEffect (of its value
## group) around each target: the global eiEntitiesInRange query (all teams) filtered by
## - IgnoreMainTargets: not the entity target itself;
## - unless TargetsGroundAndAir: only the target's layer (ground units when the target is a ground unit or no entity,
##   flyers when it is a flyer);
## - LineFromOwner(Width): a line from the owner towards the target, eiWelaAreaOfEffect long, Width wide (the query
##   circle is around its centre); else a cone of eiWelaAreaOfEffectCone (> 0) from the owner towards the target;
## - eiWelaTargetPossible of its validate group.
## ApplyEffect(Array of TEntity) gets the entities of one target if there are any. An empty target stops the whole
## fire (exit, as in the original). Validate and value group default to its own group.

var FLineWidth := 0.0
var FTargetsGroundAndAir := false
var FIgnoreMainTargets := false
var FValidateGroup: Array = []
var FValueGroup: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FValidateGroup = ComponentGroup
	FValueGroup = ComponentGroup
	return self


## Abstract. Targets: Array of TEntity, never empty.
func ApplyEffect(_Targets: Array) -> void:
	pass


func FireWarhead(Targets: Array) -> void:
	var Game = GlobalEventbus().Game
	for i in Targets.size():
		var Target: RTarget = Targets[i].Clone()
		if Target.IsEmpty():
			return

		var Cone := RParam.AsSingle(Eventbus().Read(C.eiWelaAreaOfEffectCone, [], FValueGroup))
		var Position := Target.GetTargetPosition(Game)
		var Front := TWelaTargetingRadialComponent.Normalize(Position - Owner.Position)
		if Cone > 0:
			Position = Owner.Position
		var Range := RParam.AsSingle(Eventbus().Read(C.eiWelaAreaOfEffect, [], FValueGroup))
		var TargetsFlying := false
		if not FTargetsGroundAndAir and Target.IsEntity():
			var TargetEntity = Target.TryGetTargetEntity(Game)
			if TargetEntity != null:
				TargetsFlying = not RParam.AsSet(TargetEntity.Eventbus.Read(C.eiUnitProperties, [])).has(C.upGround)

		# doing line damage
		var Line: RLine2D = null
		if FLineWidth > 0:
			Line = RLine2D.Create(Owner.Position, Front * Range)
			Position = Line.Center
			Range = RParam.ToSingle(Line.Length() / 2)

		var ConePosition := Position
		var Filter := func(Entity) -> bool:
			return _Filter(Entity, Target, TargetsFlying, Line, Cone, ConePosition, Front)

		var FilteredTargets = GlobalEventbus().Read(C.eiEntitiesInRange, [Position, Range, Owner.TeamID(), C.tcAll, Filter])
		if FilteredTargets is Array and FilteredTargets.size() > 0:
			ApplyEffect(FilteredTargets)


func _Filter(Entity, Target: RTarget, TargetsFlying: bool, Line: RLine2D, Cone: float, Position: Vector2, Front: Vector2) -> bool:
	var Result := true
	if FIgnoreMainTargets and Target.IsEntity() and Entity.ID == Target.EntityID:
		return false
	if not FTargetsGroundAndAir and TargetsFlying == Entity.UnitProperties().has(C.upGround):
		return false
	# doing line damage
	if FLineWidth > 0:
		var entityRadius: float = Entity.CollisionRadius
		var entityPosition: Vector2 = Entity.Position
		Result = Line.DistanceToPoint(entityPosition) - entityRadius <= FLineWidth / 2
	# doing splash damage in a cone
	elif Cone > 0:
		var entityRadius: float = Entity.CollisionRadius
		var entityPosition: Vector2 = Entity.Position
		var entityFront := TWelaTargetingRadialComponent.Normalize(entityPosition - Position)
		var entityWidthAngle := RParam.ToSingle(atan(entityRadius / maxf(0.01, RParam.ToSingle(entityPosition.distance_to(Position)))))
		Result = TWelaTargetingRadialComponent.InnerAngle(Front, entityFront) - entityWidthAngle <= Cone / 2
	return Result and RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible,
		[ATarget.ToRParam(ATarget.Make(Entity))], FValidateGroup)).IsValid()


## This warhead deals damage along the line from owner to target. Linelength = eiWelaAreaOfEffect.
func LineFromOwner(LineWidth: float) -> TWarheadSplashComponent:
	FLineWidth = RParam.ToSingle(LineWidth)
	return self


func IgnoreMainTargets() -> TWarheadSplashComponent:
	FIgnoreMainTargets = true
	return self


func TargetsGroundAndAir() -> TWarheadSplashComponent:
	FTargetsGroundAndAir = true
	return self


func SetValidateGroup(Group = []) -> TWarheadSplashComponent:
	FValidateGroup = DSet.Make(Group)
	return self


func SetValueGroup(Group = []) -> TWarheadSplashComponent:
	FValueGroup = DSet.Make(Group)
	return self
