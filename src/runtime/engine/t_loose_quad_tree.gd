class_name TLooseQuadTree
extends RefCounted
## Port of TLooseQuadTree<T> (Engine.Collision.pas:88, implementation :121). A loose quadtree over the world:
## adding, removing and updating are cheap, queries cost a little more. All nodes down to MinWidth exist from the
## start. Only TEntityLooseQuardtree uses it.

var FRoot: TLooseQuadTreeNode


## Span a loose quadtree over the world. A non-square WorldRect grows to a square at its top-left corner.
func Create(WorldRect: Rect2, MinWidth: float) -> TLooseQuadTree:
	FRoot = NewRoot(SquareRect(WorldRect), MinWidth)
	return self


static func SquareRect(WorldRect: Rect2) -> Rect2:
	if not TLooseQuadTreeNode.IsSquare(WorldRect):
		var Side := maxf(WorldRect.size.x, WorldRect.size.y)
		WorldRect.size = Vector2(Side, Side)
	return WorldRect


func NewRoot(WorldRect: Rect2, MinWidth: float) -> TLooseQuadTreeNode:
	return TLooseQuadTreeNode.new().Create(WorldRect, MinWidth, null)


## Adds an item to the tree. Nil will be ignored. An item whose center lies outside the root is not stored but
## keeps FOwningTree (the original only asserts).
func AddItem(Item: TLooseQuadTreeNodeData) -> void:
	if Item != null:
		Item.FOwningTree = self
		FRoot.AddItemRecursive(Item)


## Removes an item from the tree. Nil will be ignored.
func RemoveItem(Item: TLooseQuadTreeNodeData) -> void:
	if Item != null and Item.FOwner != null:
		Item.FOwner.RemoveItemRecursive(Item)


func UpdateItem(Item: TLooseQuadTreeNodeData) -> void:
	RemoveItem(Item)
	AddItem(Item)


## Return all items, which intersect the circle.
func GetIntersections(Center: Vector2, Radius: float) -> Array:
	var Result: Array = []
	FRoot.GetIntersections(Center, Radius, Result)
	return Result


func Free() -> void:
	FRoot.Destroy()
