class_name TEntityLooseQuardtree
extends TLooseQuadTree
## Port of TEntityLooseQuardtree (BaseConflict.Classes.Shared.pas:89, implementation :349; the typo is the
## original's): the loose quadtree of TCollisionManagerComponent, with team-constrained queries.


func NewRoot(WorldRect: Rect2, MinWidth: float) -> TLooseQuadTreeNode:
	return TEntityLooseQuadTreeNode.new().Create(WorldRect, MinWidth, null)


## GetIntersections(Intersector, SourceTeamID, TargetTeamConstraint): the matching TEntityLooseQuadtreeData.
func GetEntityIntersections(Center: Vector2, Radius: float, SourceTeamID: int, TargetTeamConstraint: int) -> Array:
	var Result: Array = []
	FRoot.GetEntityIntersections(Center, Radius, SourceTeamID, TargetTeamConstraint, Result)
	return Result
