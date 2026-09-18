class_name TWelaLinkEffectUnitPropertyComponent
extends TEntityComponent
## Port of TWelaLinkEffectUnitPropertyComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:643,
## implementation :2063), server only. Gives a linked unit a property while the link lasts: eiLinkEstablish (epLast)
## adds it to the destination entity's blackboard eiUnitProperties, eiLinkBreak (epLower) removes it from the broken
## target (written straight into the blackboard, so no eiUnitPropertyChanged). A property the unit already had is
## removed at the break too (as noted in the original).

var FGivenUnitProperty := 0


func CreateGrouped(Owner = null, Group = [], GivenUnitProperty = 0) -> TEntityComponent:
	super(Owner, Group)
	FGivenUnitProperty = GivenUnitProperty
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnBreak", C.eiLinkBreak, C.epLower, C.etTrigger))
	e.append(XEvent("OnEstablishLink", C.eiLinkEstablish, C.epLast, C.etTrigger))


## Removes the unit property from the target.
func OnBreak(LinkTarget) -> bool:
	_Change(LinkTarget, false)
	return true


## Gives the dest the unit property.
func OnEstablishLink(_Source, Dest) -> bool:
	_Change(Dest, true)
	return true


func _Change(Target: RTarget, Give: bool) -> void:
	if Target.IsEntity():
		var TargetEntity = Target.GetTargetEntity(GlobalEventbus().Game)
		if TargetEntity != null:
			# get/set value direct in blackboard, as we don't want to save temporary properties introduced by
			# components as permanent
			var TargetUnitProperties := RParam.AsSet(TargetEntity.Blackboard.GetValue(C.eiUnitProperties, []))
			if Give:
				TargetUnitProperties = DSet.Make(TargetUnitProperties + [FGivenUnitProperty])
			else:
				TargetUnitProperties = DSet.Difference(TargetUnitProperties, [FGivenUnitProperty])
			TargetEntity.Blackboard.SetValue(C.eiUnitProperties, [], TargetUnitProperties)
