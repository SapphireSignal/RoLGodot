class_name TEntityLooseQuadtreeData
extends TLooseQuadTreeNodeData
## Port of TEntityLooseQuadtreeData (BaseConflict.Classes.Shared.pas:65, implementation :441): a quadtree item for
## an entity, with the team the queries filter on. Setting another TeamID re-adds the item so the nodes' team
## counts stay right (it moves to the end of its node's item list).

var FTeamID := 0

var TeamID: int:
	get:
		return FTeamID
	set(value):
		SetTeamID(value)


func Create(Center_: Vector2, Radius_: float, Data_) -> TLooseQuadTreeNodeData:
	super(Center_, Radius_, Data_)
	TeamID = Data_.TeamID()
	return self


func SetTeamID(Value: int) -> void:
	if Value != FTeamID:
		var owningTree = FOwningTree
		if owningTree != null:
			owningTree.RemoveItem(self)
		FTeamID = Value
		if owningTree != null:
			owningTree.AddItem(self)
