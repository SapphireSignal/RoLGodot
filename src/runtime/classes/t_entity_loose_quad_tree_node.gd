class_name TEntityLooseQuadTreeNode
extends TLooseQuadTreeNode
## Port of TEntityLooseQuadTreeNode (BaseConflict.Classes.Shared.pas:75, implementation :367): a loose quadtree
## node that counts, per team, the entities in it and beneath it, so team-constrained queries skip whole subtrees.
## Port note: an item whose center lies outside every child is counted but not stored and never uncounted (as in
## the original; removing it finds no owner node).

const C = preload("res://src/runtime/dws/dws_const.gd")
const MAX_TEAMS = 6

var FTeamCount: Array = [0, 0, 0, 0, 0, 0]


func NewChild(SubRect: Rect2) -> TLooseQuadTreeNode:
	return TEntityLooseQuadTreeNode.new().Create(SubRect, FMinWidth, self)


func AddItemRecursive(Item: TLooseQuadTreeNodeData) -> void:
	super(Item)
	# add item to this node, need to increment counter
	FTeamCount[Item.TeamID] += 1


func RemoveItemRecursive(Item: TLooseQuadTreeNodeData) -> void:
	if Item == null:
		return
	super(Item)
	FTeamCount[Item.TeamID] -= 1


## Collects, in tree order, the items intersecting the circle that pass the team constraint (tcAll, tcEnemies:
## another team than SourceTeamID, tcAllies: the same team).
func GetEntityIntersections(Center: Vector2, Radius: float, SourceTeamID: int, TargetTeamConstraint: int,
		Intersections: Array) -> void:
	# target contraint to any type (enemies or allies), test if node can fulfill this constraint
	var nodeCanFulfillConstraint := false
	match TargetTeamConstraint:
		C.tcAll:
			nodeCanFulfillConstraint = HasItems
		C.tcEnemies:
			# any entity in node or subnodes that not match sourceteam?
			for i in MAX_TEAMS:
				if i != SourceTeamID:
					nodeCanFulfillConstraint = nodeCanFulfillConstraint or FTeamCount[i] > 0
		C.tcAllies:
			# any entity in node or subnodes that match sourceteam?
			nodeCanFulfillConstraint = FTeamCount[SourceTeamID] > 0
	if not nodeCanFulfillConstraint:
		return
	# node lies in area of interest?
	if not CircleIntersectsRect(Center, Radius, FLooseRect):
		return
	for Item in FItems:
		if CircleIntersectsCircle(Center, Radius, Item) and (TargetTeamConstraint == C.tcAll
				or (TargetTeamConstraint == C.tcEnemies and SourceTeamID != Item.TeamID)
				or (TargetTeamConstraint == C.tcAllies and SourceTeamID == Item.TeamID)):
			Intersections.append(Item)
	if HasChildren:
		for i in CHILDCOUNT:
			FChildren[i].GetEntityIntersections(Center, Radius, SourceTeamID, TargetTeamConstraint, Intersections)
