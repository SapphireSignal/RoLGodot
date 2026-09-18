class_name TWarheadLinkApplyScriptComponent
extends TWarheadApplyScriptComponent
## Port of TWarheadLinkApplyScriptComponent (BaseConflict.EntityComponents.Shared.Wela.pas:918, implementation :2552).
## On a link entity: at eiAfterCreate it applies the script (ApplyScriptReturnGroups) to the link's first eiLinkDest
## if eiWelaTargetPossible of its group allows it, and gives the new groups the link's eiCreator / eiCreatorGroup.
## When freed (not at game shutdown) and on eiReplaceEntity of that target it removes those groups again
## (eiRemoveComponentGroup on the global bus). Never applies on eiFireWarhead.

var FSavedScriptGroup: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnReplaceEntity", C.eiReplaceEntity, C.epLast, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = [], ScriptToApply = "") -> TEntityComponent:
	super(Owner, Group, ScriptToApply)
	FNotAtFire = true
	return self


## Remove the components of the linktarget.
func BeforeComponentFree() -> void:
	# if Game is been closed some other entites might already been freed, as all entities are freed we don't need to deregister
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	if not (game != null and not game.IsShuttingDown()):
		return
	var Targets := ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
	if not ATarget.HasIndex(Targets, 0):
		# the original raises here
		MakeException("Destroy: No destinations are set!")
		return
	var Entity = Targets[0].TryGetTargetEntity(game)
	if Entity != null and not FSavedScriptGroup.is_empty():
		GlobalEventbus().Trigger(C.eiRemoveComponentGroup, [Entity.ID, FSavedScriptGroup])
	super()


## Apply the script to the Linktarget.
func OnAfterCreate() -> bool:
	var Targets := ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
	if not ATarget.HasIndex(Targets, 0):
		# the original raises here
		MakeException("Destroy: No destinations are set!")
		return true
	var Entity = Targets[0].TryGetTargetEntity(GlobalEventbus().Game)
	if Entity != null and RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible, [ATarget.ToRParam(ATarget.Make(Entity))], ComponentGroup)).IsValid():
		FSavedScriptGroup = Entity.ApplyScriptReturnGroups(FScriptName)
		assert(not FSavedScriptGroup.is_empty(), "TWarheadLinkApplyScriptComponent.OnAfterCreate: (SavedGroup = [])! Error or intended?")
		Entity.Eventbus.Write(C.eiCreator, [Eventbus().Read(C.eiCreator, [])], FSavedScriptGroup)
		Entity.Eventbus.Write(C.eiCreatorGroup, [Eventbus().Read(C.eiCreatorGroup, [])], FSavedScriptGroup)
	else:
		FSavedScriptGroup = []
	return true


## Removes script from unit if replaced.
func OnReplaceEntity(OldEntityID, NewEntityID, IsSameEntity) -> bool:
	var Targets := ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
	assert(Targets.size() == 1 and Targets[0].IsEntity())
	if Targets[0].EntityID == RParam.AsInteger(OldEntityID) and RParam.AsBoolean(IsSameEntity):
		GlobalEventbus().Trigger(C.eiRemoveComponentGroup, [RParam.AsInteger(NewEntityID), FSavedScriptGroup])
	return true
