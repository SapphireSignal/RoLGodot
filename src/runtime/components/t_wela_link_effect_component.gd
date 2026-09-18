class_name TWelaLinkEffectComponent
extends TWelaEfficiencyEffectComponent
## Port of TWelaLinkEffectComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:570, implementation
## :1417), server only. Establishes and breaks links: eiFire triggers eiLinkEstablish [owner, target] per target in
## its group. eiLinkEstablish (epFirst) to a target already linked returns False (the event stops); else, with
## eiWelaTargetCount > 0 links already, the oldest link breaks first (eiLinkBreak), then the link entity
## (eiLinkPattern of the group) spawns at (0, 0) facing (0, 1) with the owner's team, commander (eiOwnerCommander) and
## card league / level; before its script finishes it gets upLink, eiLinkSource / eiLinkDest (an ATarget each),
## eiCreatorGroup (CreatorGroup), a TLinkEventRedirecter (ALLGROUP) and the group's skin. eiLinkBreak (epLast) kills
## the link entity (eiDelayedKillEntity). Death, exile (eiExiled True), the global eiLose and freeing break all links.
## Efficiency: the group's eiWelaDamage; to a target: 1 unless upUntargetable, else -1.
## The links are a Delphi TDictionary (DelphiDictionary, keyed by RTarget.Hash / Equal): breaking all walks it in
## slot order while each break removes its entry, so, as in the original, a link shifted back into a visited slot is
## skipped and stays up.

var FCurrentLinks: DelphiDictionary = null  # RTarget -> link entity ID
var FLinkOrder: Array = []  # of RTarget
var FCreatorGroup: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FCurrentLinks = DelphiDictionary.new().Create(func(Key: RTarget) -> int: return Key.Hash(),
		func(Left: RTarget, Right: RTarget) -> bool: return Left.Equal(Right))
	FLinkOrder = []
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnBreak", C.eiLinkBreak, C.epLast, C.etTrigger))
	e.append(XEvent("OnEstablishLink", C.eiLinkEstablish, C.epFirst, C.etTrigger))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnExiled", C.eiExiled, C.epLast, C.etWrite))
	e.append(XEvent("OnLose", C.eiLose, C.epMiddle, C.etTrigger, C.esGlobal))


func Destroy() -> void:
	if FCurrentLinks != null:
		BreakAllLinks()
	FCurrentLinks = null
	FLinkOrder = []
	super()


func CreatorGroup(Group: Array) -> TWelaLinkEffectComponent:
	FCreatorGroup = DSet.Make(Group)
	return self


## Kills the link entity to the target.
func OnBreak(LinkTarget) -> bool:
	BreakLink(LinkTarget)
	return true


## Establishes a link between Source and Dest. If the target count is exceeded, the oldest link is destroyed.
func OnEstablishLink(Source, Dest) -> bool:
	return EstablishLink(Source, Dest)


## Breaks all links on exile.
func OnExiled(Exiled) -> bool:
	if RParam.AsBoolean(Exiled):
		BreakAllLinks()
	return true


## Breaks all links on game finish.
func OnLose(_TeamID) -> bool:
	BreakAllLinks()
	return true


## Breaks all links on death.
func OnDie(_KillerID, _KillerCommanderID) -> bool:
	BreakAllLinks()
	return true


## Creates a link between self and each target.
func Fire(Targets: Array) -> void:
	for i in Targets.size():
		Eventbus().Trigger(C.eiLinkEstablish, [RTarget.Create(Owner), Targets[i]], ComponentGroup)


func GetEfficiency(_TargetsInRange: Array) -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup))


func GetEfficiencyToTarget(Entity) -> float:
	var IsPossible: bool = Entity != null and \
		not RParam.AsSet(Entity.Eventbus.Read(C.eiUnitProperties, [])).has(C.upUntargetable)
	return 1.0 if IsPossible else -1.0


## `for Link in FCurrentLinks.Keys`: a live walk over the slots (see the class comment).
func BreakAllLinks() -> void:
	var Slot := FCurrentLinks.NextSlot(-1)
	while Slot >= 0:
		Eventbus().Trigger(C.eiLinkBreak, [FCurrentLinks.KeyAt(Slot)], ComponentGroup)
		Slot = FCurrentLinks.NextSlot(Slot)


func BreakLink(LinkTarget: RTarget) -> void:
	if FCurrentLinks.ContainsKey(LinkTarget):
		GlobalEventbus().Trigger(C.eiDelayedKillEntity, [FCurrentLinks.GetItem(LinkTarget)])
		FCurrentLinks.Remove(LinkTarget)
		for i in FLinkOrder.size():
			if FLinkOrder[i].Equal(LinkTarget):
				FLinkOrder.remove_at(i)
				break


func EstablishLink(Source: RTarget, Dest: RTarget) -> bool:
	if FCurrentLinks.ContainsKey(Dest):
		return false
	var TargetCount = Eventbus().Read(C.eiWelaTargetCount, [], ComponentGroup)
	if not RParam.IsEmpty(TargetCount) and RParam.AsInteger(TargetCount) > 0 \
		and RParam.AsInteger(TargetCount) <= FLinkOrder.size():
		Eventbus().Trigger(C.eiLinkBreak, [FLinkOrder[0]], ComponentGroup)
	var SkinID: String = Owner.GetSkinID(ComponentGroup)
	var Preprocess := func(PreprocessedEntity: TEntity) -> void:
		_Preprocess(PreprocessedEntity, Source, Dest, SkinID)
	var Link = GlobalEventbus().Game.ServerEntityManager.SpawnUnit(Vector2.ZERO, Vector2(0, 1),
		RParam.AsString(Eventbus().Read(C.eiLinkPattern, [], ComponentGroup)), CardLeague(), CardLevel(),
		Owner.TeamID(), RParam.AsInteger(Eventbus().Read(C.eiOwnerCommander, [])), Owner, Callable(), Preprocess)
	if Link == null:
		# the original has no check here (a failed spawn raised before)
		push_error(BuildExceptionMessage("EstablishLink: Could not spawn the link"))
		return true
	FCurrentLinks.Add(Dest.Clone(), Link.ID)
	FLinkOrder.append(Dest.Clone())
	return true


func _Preprocess(PreprocessedEntity: TEntity, Source: RTarget, Dest: RTarget, SkinID: String) -> void:
	var UnitProperties := RParam.AsSet(PreprocessedEntity.Blackboard.GetValue(C.eiUnitProperties, []))
	UnitProperties = DSet.Make(UnitProperties + [C.upLink])
	PreprocessedEntity.Blackboard.SetValue(C.eiUnitProperties, [], UnitProperties)
	PreprocessedEntity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, CardLeague())
	PreprocessedEntity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLevel, CardLevel())
	PreprocessedEntity.Eventbus.Write(C.eiLinkSource, [ATarget.ToRParam(ATarget.Make(Source))])
	PreprocessedEntity.Eventbus.Write(C.eiLinkDest, [ATarget.ToRParam(ATarget.Make(Dest))])
	PreprocessedEntity.Eventbus.Write(C.eiCreatorGroup, [FCreatorGroup])
	TLinkEventRedirecter.new().CreateGrouped(PreprocessedEntity, [C.ALLGROUP_INDEX], ComponentGroup)
	PreprocessedEntity.SkinID = SkinID
	PreprocessedEntity.Blackboard.SetValue(C.eiSkinIdentifier, [], SkinID)
