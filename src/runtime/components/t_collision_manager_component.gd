class_name TCollisionManagerComponent
extends TGDEntityComponent
## Port of TCollisionManagerComponent (BaseConflict.EntityComponents.Shared.pas:443, implementation :1659): the
## spatial index of the game (Game.CollisionManager, on the game entity). TCollisionComponent registers every
## unit as a circle in a loose quadtree over Game.Map.MapBoundaries (min node width 16); the global reads
## eiEntitiesInRange / eiClosestEntityInRange answer range queries with a team constraint and an optional filter.
## Port notes: Filter is a Callable(Entity) -> bool or null (ProcEntityFilterFunction / RPARAM_EMPTY);
## eiEntitiesInRange returns an Array of TEntity in tree order, or null when nothing matched (the original frees
## the empty list). Distances are doubles here, singles in the original (ties between near-equal distances may
## break differently).

const MIN_NODE_WIDTH = 16

var FQuadTree: TEntityLooseQuardtree


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnClosestEntityInRange", C.eiClosestEntityInRange, C.epFirst, C.etRead, C.esGlobal))
	e.append(XEvent("OnEntitiesInRangeOf", C.eiEntitiesInRange, C.epFirst, C.etRead, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FQuadTree = TEntityLooseQuardtree.new().Create(GlobalEventbus().Game.Map.MapBoundaries, MIN_NODE_WIDTH)
	return self


func Destroy() -> void:
	if FQuadTree != null:
		FQuadTree.Free()
	FQuadTree = null
	super()


## Return the closest matching entity (the first found wins a tie), or null.
func OnClosestEntityInRange(Pos, Range, SourceTeamID, TargetTeamConstraint, Filter):
	var Result = null
	var MyPos := RParam.AsVector2(Pos)
	var nearby := FQuadTree.GetEntityIntersections(MyPos, RParam.AsSingle(Range), RParam.AsInteger(SourceTeamID),
		RParam.AsInteger(TargetTeamConstraint))
	var HasBest := false
	var bestdist := 0.0
	for element in nearby:
		var e = element.Data
		var dist: float = element.Center.distance_to(MyPos)
		if (Filter == null or Filter.call(e)) and (not HasBest or dist < bestdist):
			HasBest = true
			bestdist = dist
			Result = e
	return Result


## Return all matching entities, or null if none.
func OnEntitiesInRangeOf(Pos, Range, SourceTeamID, TargetTeamConstraint, Filter):
	var nearby := FQuadTree.GetEntityIntersections(RParam.AsVector2(Pos), RParam.AsSingle(Range),
		RParam.AsInteger(SourceTeamID), RParam.AsInteger(TargetTeamConstraint))
	var EntitiesFound: Array = []
	for element in nearby:
		var e = element.Data
		if Filter == null or Filter.call(e):
			EntitiesFound.append(e)
	if EntitiesFound.is_empty():
		return null
	return EntitiesFound


func RegisterCollidable(Collidable: TLooseQuadTreeNodeData) -> void:
	if Collidable != null:
		FQuadTree.AddItem(Collidable)


func RemoveCollidable(Collidable: TLooseQuadTreeNodeData) -> void:
	if Collidable != null:
		FQuadTree.RemoveItem(Collidable)
