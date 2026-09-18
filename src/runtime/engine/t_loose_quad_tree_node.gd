class_name TLooseQuadTreeNode
extends RefCounted
## Port of TLooseQuadTreeNode<T> (Engine.Collision.pas:40, implementation :163). A node covers the square
## FRealRect; its items may reach out into FLooseRect (FRealRect grown by half its width on each side). An item
## stays in the first node whose half width is <= its radius, or in a leaf; otherwise it goes to the first child
## (top-left, top-right, bottom-left, bottom-right) whose closed FRealRect holds its center.
## Rects are Rect2 (position = Left/Top, end = Right/Bottom). Query order = items in list order (removal swaps the
## last item into the gap), then children 0..3; callers see this order.

const CHILDCOUNT = 4
const LOOSEMODIFIER = 2

var FChildren: Array = []
var FRealRect := Rect2()
var FLooseRect := Rect2()
var FBorderSizeHalf := 0.0
var FMinWidth := 0.0
var FHasChildren := false
var FHasItems := false
var FItems: Array = []  # of TLooseQuadTreeNodeData
var FParent = null  # weak in spirit: children never outlive the tree

var HasItems: bool:
	get:
		return FHasItems
var HasChildren: bool:
	get:
		return FHasChildren


## Opens up a new node. Subrect must be square.
func Create(SubRect: Rect2, MinWidth: float, Parent) -> TLooseQuadTreeNode:
	assert(IsSquare(SubRect), "Loose Quadtrees need a square shaped area!")
	FParent = weakref(Parent) if Parent != null else null
	FRealRect = SubRect
	var Grow := SubRect.size.x * LOOSEMODIFIER / 4.0
	FLooseRect = Rect2(SubRect.position - Vector2(Grow, Grow), SubRect.size + Vector2(Grow, Grow) * 2)
	FItems = []
	FBorderSizeHalf = SubRect.size.x * (LOOSEMODIFIER - 1) / 2.0
	FMinWidth = MinWidth
	if MinWidth < FRealRect.size.x:
		Split()
	return self


## RRectFloat.IsSquare (Engine.Math.Collision2D.pas:963, EPSILON = 1E-7 from Engine.Helferlein.Windows).
static func IsSquare(Rect: Rect2) -> bool:
	return absf(Rect.size.y - Rect.size.x) < 1e-7


## RRectFloat.ContainsPoint: closed on all sides (Rect2.has_point is open at the end).
static func ContainsPoint(Rect: Rect2, Point: Vector2) -> bool:
	return Rect.position.x <= Point.x and Point.x <= Rect.end.x and Rect.position.y <= Point.y and Point.y <= Rect.end.y


## RCircle.IntersectRect (Engine.Math.Collision2D.pas:1361).
static func CircleIntersectsRect(Center: Vector2, Radius: float, Rect: Rect2) -> bool:
	var dist := (Center - Rect.get_center()).abs()
	var half := Rect.size / 2.0
	if dist.x > half.x + Radius:
		return false
	if dist.y > half.y + Radius:
		return false
	if dist.x <= half.x:
		return true
	if dist.y <= half.y:
		return true
	return (dist.x - half.x) ** 2 + (dist.y - half.y) ** 2 <= Radius * Radius


## RCircle.IntersectCircle (Engine.Math.Collision2D.pas:1351).
static func CircleIntersectsCircle(Center: Vector2, Radius: float, Other: TLooseQuadTreeNodeData) -> bool:
	return (Other.Center - Center).length_squared() <= (Other.Radius + Radius) ** 2


func Parent():
	return FParent.get_ref() if FParent != null else null


## Makes a child node; TEntityLooseQuadTreeNode overrides it (its Split creates its own class).
func NewChild(SubRect: Rect2) -> TLooseQuadTreeNode:
	return TLooseQuadTreeNode.new().Create(SubRect, FMinWidth, self)


## Split this node into 4 childs.
func Split() -> void:
	FHasChildren = true
	var Half := FRealRect.size / 2.0
	var Left := FRealRect.position.x
	var Top := FRealRect.position.y
	FChildren = [
		NewChild(Rect2(Left, Top, Half.x, Half.y)),
		NewChild(Rect2(Left + Half.x, Top, Half.x, Half.y)),
		NewChild(Rect2(Left, Top + Half.y, Half.x, Half.y)),
		NewChild(Rect2(Left + Half.x, Top + Half.y, Half.x, Half.y)),
	]


func UpdateEmptyness() -> void:
	FHasItems = FItems.size() > 0 or (HasChildren and (FChildren[0].HasItems or FChildren[1].HasItems
		or FChildren[2].HasItems or FChildren[3].HasItems))


func AddItem(Item: TLooseQuadTreeNodeData) -> void:
	Item.FOwner = self
	FItems.append(Item)
	FHasItems = true


## Adds an item recursive. Searching for the correct spot to insert. An item whose center lies outside every
## child is dropped (the tree's assert is the only guard in the original).
func AddItemRecursive(Item: TLooseQuadTreeNodeData) -> void:
	if Item.Radius >= FBorderSizeHalf or not HasChildren:
		AddItem(Item)
	else:
		for i in CHILDCOUNT:
			if ContainsPoint(FChildren[i].FRealRect, Item.Center):
				FChildren[i].AddItemRecursive(Item)
				break
	FHasItems = true


func RemoveItem(Item: TLooseQuadTreeNodeData) -> void:
	var pos := FItems.find(Item)
	if pos >= 0:
		FItems[pos] = FItems[FItems.size() - 1]
		FItems.remove_at(FItems.size() - 1)
		Item.FOwner = null
		Item.FOwningTree = null
		UpdateEmptyness()


## Removes an item recursive: at its node, then up to the root.
func RemoveItemRecursive(Item: TLooseQuadTreeNodeData) -> void:
	if Item == null:
		return
	if Item.FOwner == self:
		RemoveItem(Item)
	var P = Parent()
	if P != null:
		P.RemoveItemRecursive(Item)
	UpdateEmptyness()


## Returns recursivly all intersection items.
func GetIntersections(Center: Vector2, Radius: float, Intersections: Array) -> void:
	if not CircleIntersectsRect(Center, Radius, FLooseRect):
		return
	for Item in FItems:
		if CircleIntersectsCircle(Center, Radius, Item):
			Intersections.append(Item)
	if HasChildren:
		for i in CHILDCOUNT:
			FChildren[i].GetIntersections(Center, Radius, Intersections)


## Destructor: detaches the items and drops the children.
func Destroy() -> void:
	for Item in FItems:
		Item.FOwner = null
		Item.FOwningTree = null
	FItems = []
	for Child in FChildren:
		Child.Destroy()
	FChildren = []
