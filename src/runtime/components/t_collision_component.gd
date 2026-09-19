class_name TCollisionComponent
extends TGDEntityComponent
## Port of TCollisionComponent (BaseConflict.EntityComponents.Shared.pas:474, implementation :1744): keeps the
## owner in Game.CollisionManager's quadtree as a circle of its collision radius (0.5 if it has none), following
## its position and team. Dying removes the component (and so the unit from the tree); exiled units leave the tree
## until they return.
## Port note: without a Game or a CollisionManager (tests, no game) the element is kept but never registered.

var FRegistered := false
var FElement: TEntityLooseQuadtreeData
var FRadius := 0.0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWritePosition", C.eiPosition, C.epLast, C.etWrite))
	e.append(XEvent("OnWriteTeamID", C.eiTeamID, C.epLast, C.etWrite))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnExiled", C.eiExiled, C.epLast, C.etWrite))


## reintroduce Create(Owner): no component group.
func Create(Owner = null) -> TEntityComponent:
	super(Owner)
	FRadius = Owner.CollisionRadius
	if not (FRadius > 0):
		push_error("TCollisionComponent.Create: Missing collision radius!")  # HLog.AssertAndLog
		FRadius = 0.5
	FElement = TEntityLooseQuadtreeData.new().Create(Owner.Position, FRadius, Owner)
	var Manager = _CollisionManager()
	if Manager != null:
		Manager.RegisterCollidable(FElement)
	FRegistered = true
	return self


func Destroy() -> void:
	var Manager = _CollisionManager()
	if FRegistered and Manager != null:
		Manager.RemoveCollidable(FElement)
	if FElement != null:
		FElement.Remove()  # the element's destructor
		FElement.Data = null
	FElement = null
	super()


## Game.CollisionManager, or null without a game or manager.
func _CollisionManager():
	var Game = GlobalEventbus().Game
	return Game.get("CollisionManager") if Game != null else null


## Dead units don't have any repulsioneffect on other units.
func OnDie(_KillerID, _KillerCommanderID) -> bool:
	GlobalEventbus().Trigger(C.eiRemoveComponent, [Owner.ID, FUniqueID])
	return true


## Exiled units are not on the battlefield anymore.
func OnExiled(IsExiled) -> bool:
	var Manager = _CollisionManager()
	if not RParam.AsBoolean(IsExiled):
		if not FRegistered and Manager != null:
			Manager.RegisterCollidable(FElement)
		FRegistered = true
	else:
		if FRegistered and Manager != null:
			Manager.RemoveCollidable(FElement)
		FRegistered = false
	return true


## Updates the collidable.
func OnWritePosition(Position) -> bool:
	FElement.Center = RParam.AsVector2(Position)
	if FRegistered:
		FElement.UpdateInTree()
	return true


## Updates the LooseQuadtreeData (setting the team re-adds it to the tree).
func OnWriteTeamID(TeamID) -> bool:
	FElement.TeamID = RParam.AsInteger(TeamID)
	return true
