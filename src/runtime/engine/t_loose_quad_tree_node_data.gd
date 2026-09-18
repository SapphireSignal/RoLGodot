class_name TLooseQuadTreeNodeData
extends RefCounted
## Port of TLooseQuadTreeNodeData<T> (Engine.Collision.pas:25, implementation :104): an item of a loose quadtree,
## a circle (Boundaries: Center + Radius) carrying Data. Only TEntityLooseQuadtreeData uses it.
## Port notes: the original's destructor removes the item from its tree; here call Remove() before dropping it.
## FOwner (the node) and FOwningTree are strong references, cleared when the item leaves the tree.

var FOwner = null  # TLooseQuadTreeNode
var FOwningTree = null  # TLooseQuadTree
var Center := Vector2.ZERO  # Boundaries.Center
var Radius := 0.0  # Boundaries.Radius
var Data = null


func Create(Center_: Vector2, Radius_: float, Data_) -> TLooseQuadTreeNodeData:
	Center = Center_
	Radius = Radius_
	Data = Data_
	return self


func Remove() -> void:
	if FOwningTree != null:
		FOwningTree.RemoveItem(self)


## Updates this item in the tree. Should be used after Boundaries are changed.
func UpdateInTree() -> void:
	if FOwningTree != null:
		FOwningTree.UpdateItem(self)
