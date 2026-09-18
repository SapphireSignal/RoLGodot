class_name TWelaEffectFireComponent
extends TWelaEffectComponent
## Port of TWelaEffectFireComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:494,
## implementation :2814), server only. On fire fires another wela: in its target group, if eiIsReady there is true
## or empty, eiFire [one target] for each target that passes eiWelaTargetPossible of that group. MultiTargetGroup:
## tries the groups in order and stops after the first that fired. RedirectToSelf: the owner is the only target.
## RedirectToGround: the ground at the first target's position (jittered by RandomizeGroundtarget, then clamped
## into the walk zone), without target checks. FireInCreator: eiFire [all targets] on the entity of eiCreator in
## its eiCreatorGroup (never groupless), ignoring the rest.
## Quirk kept: RedirectToLinkSource / RedirectToLinkDestination only set flags nothing reads.
## Port: RedirectToGround with no targets reports an error and fires nothing (the original read past the array).

var FRedirectToSelf := false
var FRedirectToSource := false
var FRedirectToDestination := false
var FRedirectToGround := false
var FFireInCreator := false
var FGroundJitterMinRange := 0.0
var FGroundJitterMaxRange := 0.0
var FTargetGroup: Array = []
var FMultitargetGroup: Array = []  # of SetComponentGroup


func _CheckAndFireInGroup(Targets: Array, TargetGroup: Array) -> bool:
	var Result := false
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], TargetGroup)):
		for Item in Targets:
			var Target := ATarget.ToRParam(ATarget.Make(Item))
			if FRedirectToGround or RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible, [Target], TargetGroup)).IsValid():
				Eventbus().Trigger(C.eiFire, [Target], TargetGroup)
				Result = true
	return Result


func Fire(Targets: Array) -> void:
	var game = GlobalEventbus().Game
	if FFireInCreator:
		var CreatorID := RParam.AsInteger(Eventbus().Read(C.eiCreator, [], ComponentGroup))
		var Creator = game.EntityManager.TryGetEntityByID(CreatorID) if game != null else null
		if Creator != null:
			var CreatorGroup := RParam.AsSet(Eventbus().Read(C.eiCreatorGroup, [], ComponentGroup))
			# don't make a global fire as it would trigger all welas on that entity
			if not CreatorGroup.is_empty():
				Creator.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(Targets)], CreatorGroup)
		return
	if FTargetGroup.is_empty() and FMultitargetGroup.is_empty():
		push_error("TWelaEffectFireComponent.Fire: No target group set!")
		return
	if FRedirectToSelf:
		Targets = ATarget.Make(Owner)
	if FRedirectToGround:
		if Targets.is_empty():
			push_error("TWelaEffectFireComponent.Fire: RedirectToGround without a target!")
			return
		var TargetPosition := ATarget.First(Targets).GetTargetPosition(game)
		var Jitter := Vector2(0, FGroundJitterMinRange + randf() * (FGroundJitterMaxRange - FGroundJitterMinRange))
		TargetPosition += Jitter.rotated(randf() * 2 * PI)
		if game != null and game.Map != null:
			TargetPosition = game.Map.ClampToZone(C.ZONE_WALK, TargetPosition)
		Targets = ATarget.Make(TargetPosition)
	if FMultitargetGroup.is_empty():
		_CheckAndFireInGroup(Targets, FTargetGroup)
	else:
		for Group in FMultitargetGroup:
			if _CheckAndFireInGroup(Targets, Group):
				break


func FireInCreator() -> TWelaEffectFireComponent:
	FFireInCreator = true
	return self


func TargetGroup(Group = []) -> TWelaEffectFireComponent:
	FTargetGroup = DSet.Make(Group)
	return self


## Check each target group and fire in the first possible one.
func MultiTargetGroup(Group = []) -> TWelaEffectFireComponent:
	FMultitargetGroup.append(DSet.Make(Group))
	return self


## Changes the fire target to the ground and disable target checks. Overwrites other redirections.
## Does not work with FireInCreator.
func RedirectToGround() -> TWelaEffectFireComponent:
	FRedirectToGround = true
	return self


## Redirected targets to ground are jittered within range. Ensures target to be inside of WALK_ZONE.
func RandomizeGroundtarget(MinRange: float = 0.0, MaxRange: float = 0.0) -> TWelaEffectFireComponent:
	FGroundJitterMinRange = MinRange
	FGroundJitterMaxRange = MaxRange
	return self


## Changes the fire target and checks to the entity itself. Overwrites other redirections.
func RedirectToSelf() -> TWelaEffectFireComponent:
	FRedirectToSelf = true
	return self


## Changes the fire target and checks to the link source. Overwrites other redirections.
func RedirectToLinkSource() -> TWelaEffectFireComponent:
	FRedirectToSource = true
	return self


## Changes the fire target and checks to the link destination. Overwrites other redirections.
func RedirectToLinkDestination() -> TWelaEffectFireComponent:
	FRedirectToDestination = true
	return self
