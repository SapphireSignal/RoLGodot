extends "res://tests/test_case.gd"
## The loose quadtree (Engine.Collision.pas, BaseConflict.Classes.Shared.pas:65-94 / :349-458) and
## TCollisionManagerComponent / TCollisionComponent (BaseConflict.EntityComponents.Shared.pas:443-495, :1659-1802),
## TServerCollisionManagerComponent (Server.pas:346, :1582), TWelaReadyEnemiesNearbyComponent (Wela.pas:685,
## :3107). The world is the Single map's MapBoundaries (-150..150 on both axes, src/content/maps/Single.json);
## with MinWidth 16 the nodes are 300, 150, 75, 37.5, 18.75 and 9.375 (leaves) wide.

const C = preload("res://src/runtime/dws/dws_const.gd")
const WORLD = Rect2(-150, -150, 300, 300)

var _free: Array = []
var _game_entity: TEntity
var _bus: TEventbus
var _last_collision: TCollisionComponent


class FakeData:
	extends RefCounted
	var Team := 0
	var Name := ""

	func _init(team: int, name: String) -> void:
		Team = team
		Name = name

	func TeamID() -> int:
		return Team


class FakeMap:
	extends RefCounted
	var MapBoundaries := WORLD


class FakeEntityManager:
	extends RefCounted
	var Entities := {}

	func GetEntityByID(ID: int):
		return Entities.get(ID)


class FakeGame:
	extends RefCounted
	var IsShuttingDown := false
	var Map := FakeMap.new()
	var EntityManager := FakeEntityManager.new()
	var CollisionManager = null

	# what the Lanetower script asks the Game global
	func IsDuo() -> bool:
		return false

	func IsPvP() -> bool:
		return true

	func IsOneLane() -> bool:
		return false

	func HasShowdown() -> bool:
		return false


## Records eiRemoveComponent on the global bus.
class RemoveProbe:
	extends TEntityComponent
	var Removed: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnRemoveComponent", C.eiRemoveComponent, C.epLast, C.etTrigger, C.esGlobal))

	func OnRemoveComponent(EntityID, ComponentID) -> bool:
		Removed.append([EntityID, ComponentID])
		return true


func after_each() -> void:
	for o in _free:
		o.Free()
	_free.clear()
	_last_collision = null
	if _game_entity != null:
		_game_entity.Free()
		_game_entity = null
	if _bus != null:
		_bus.Game = null
		_bus.Free()
		_bus = null
	TEntity.LastScriptError = ""
	super()


## A global bus with a game entity carrying the (server) collision manager as Game.CollisionManager.
func _game(side: int = C.nsServer, server_manager: bool = false) -> TEventbus:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = side
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	var manager = TServerCollisionManagerComponent.new() if server_manager else TCollisionManagerComponent.new()
	_bus.Game.CollisionManager = manager.Create(_game_entity)
	return _bus


func _unit(id: int, pos: Vector2, team: int, radius: float = 0.5) -> TEntity:
	var e := TEntity.new().Create(_bus, id)
	_free.push_front(e)
	e.Position = pos
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.CollisionRadius = radius
	_last_collision = TCollisionComponent.new().Create(e)
	_bus.Game.EntityManager.Entities[id] = e
	return e


func _in_range(pos: Vector2, range_: float, team: int, constraint: int, filter = null):
	return _bus.Read(C.eiEntitiesInRange, [pos, range_, team, constraint, filter])


func _ids(entities) -> Array:
	return [] if entities == null else entities.map(func(e): return e.ID)


func _tree() -> TEntityLooseQuardtree:
	return TEntityLooseQuardtree.new().Create(WORLD, 16)


func _item(tree: TEntityLooseQuardtree, pos: Vector2, radius: float, team: int, name: String) -> TEntityLooseQuadtreeData:
	var item := TEntityLooseQuadtreeData.new().Create(pos, radius, FakeData.new(team, name)) as TEntityLooseQuadtreeData
	tree.AddItem(item)
	return item


func _names(items: Array) -> Array:
	return items.map(func(i): return i.Data.Name)


## TLooseQuadTreeNode.AddItemRecursive: small items sink to a leaf, an item with radius >= half a node's width
## stays there; a center on a split line goes to the first child whose closed rect holds it (top-left first).
func test_quadtree_placement() -> void:
	var tree := _tree()
	var small := _item(tree, Vector2(1, 1), 0.5, 1, "small")
	check_eq(small.FOwner.FRealRect, Rect2(0, 0, 9.375, 9.375), "small item in the leaf holding (1,1)")
	var mid := _item(tree, Vector2(1, 1), 5, 1, "mid")
	check_eq(mid.FOwner.FRealRect.size.x, 9.375, "radius 5 < 18.75/2: still a leaf")
	var big := _item(tree, Vector2(1, 1), 10, 1, "big")
	check_eq(big.FOwner.FRealRect, Rect2(0, 0, 18.75, 18.75), "radius 10 >= 18.75/2: stays in the 18.75 node")
	var huge := _item(tree, Vector2(1, 1), 150, 1, "huge")
	check(huge.FOwner == tree.FRoot, "radius 150 >= 300/2: root")
	var edge := _item(tree, Vector2(0, 0), 0.5, 1, "edge")
	check_eq(edge.FOwner.FRealRect, Rect2(-9.375, -9.375, 9.375, 9.375), "(0,0) goes top-left")
	check_eq(tree.FRoot.FLooseRect, Rect2(-300, -300, 600, 600), "loose rect: half the width more on each side")
	tree.Free()


## TEntityLooseQuadTreeNode.GetIntersections: team constraint and the tree order (child 0..3, items in list order).
func test_quadtree_team_queries() -> void:
	var tree := _tree()
	_item(tree, Vector2(5, 0), 0.5, 1, "ally_right")  # y = 0 is on the split line: top-right quadrant
	_item(tree, Vector2(0, 0), 0.5, 1, "ally_center")  # top-left quadrant
	_item(tree, Vector2(3, 1), 0.5, 2, "enemy_near")  # bottom-right quadrant
	_item(tree, Vector2(50, 50), 0.5, 2, "enemy_far")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 6, 1, C.tcAll)),
		["ally_center", "ally_right", "enemy_near"], "tcAll in tree order")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 6, 1, C.tcEnemies)), ["enemy_near"], "tcEnemies")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 6, 1, C.tcAllies)),
		["ally_center", "ally_right"], "tcAllies")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 6, 3, C.tcAllies)), [], "no team 3")
	# (5,0) with radius 0.5 is 5 away: a query of radius 4.5 touches it (<=), 4.4 does not
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 4.5, 1, C.tcAllies)), ["ally_center", "ally_right"],
		"circles touch at 4.5 + 0.5")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 4.4, 1, C.tcAllies)), ["ally_center"], "just out")
	tree.Free()


## TLooseQuadTreeNode.RemoveItem swaps the last item into the gap; UpdateItem re-adds at the end.
func test_quadtree_item_order() -> void:
	var tree := _tree()
	var a := _item(tree, Vector2(1, 1), 0.5, 1, "a")
	var b := _item(tree, Vector2(2, 2), 0.5, 1, "b")
	var c := _item(tree, Vector2(3, 3), 0.5, 1, "c")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 10, 1, C.tcAll)), ["a", "b", "c"], "insertion order")
	a.UpdateInTree()
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 10, 1, C.tcAll)), ["c", "b", "a"],
		"a removed (c swapped in), re-added last")
	b.Remove()
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 10, 1, C.tcAll)), ["c", "a"], "b removed")
	check(b.FOwner == null and b.FOwningTree == null, "removed item is detached")
	check_eq(c.FOwner, a.FOwner, "same leaf")
	tree.Free()


## TEntityLooseQuadtreeData.SetTeamID re-adds the item; the per-team counts follow; an emptied tree has no items.
func test_quadtree_team_counts() -> void:
	var tree := _tree()
	var a := _item(tree, Vector2(1, 1), 0.5, 1, "a")
	var root: TEntityLooseQuadTreeNode = tree.FRoot
	check_eq(root.FTeamCount, [0, 1, 0, 0, 0, 0], "counted at the root")
	check_eq(a.FOwner.FTeamCount, [0, 1, 0, 0, 0, 0], "and at the leaf")
	a.TeamID = 2
	check_eq(root.FTeamCount, [0, 0, 1, 0, 0, 0], "team change moves the count")
	check_eq(_names(tree.GetEntityIntersections(Vector2.ZERO, 5.0, 1, C.tcEnemies)), ["a"], "now an enemy of 1")
	var leaf: TEntityLooseQuadTreeNode = a.FOwner
	a.Remove()
	check_eq(root.FTeamCount, [0, 0, 0, 0, 0, 0], "uncounted")
	check(not leaf.HasItems and not leaf.Parent().HasItems, "leaf and its parent empty")
	# quirk: RemoveItemRecursive updates a node after its ancestors, so nodes above the parent keep HasItems
	check(root.HasItems and leaf.Parent().Parent().HasItems, "the root still claims items")
	# quirk: a center outside the root is counted at the root but stored nowhere, and removing it does nothing
	var outside := _item(tree, Vector2(200, 0), 0.5, 1, "outside")
	check(outside.FOwner == null, "not stored")
	outside.Remove()
	check_eq(root.FTeamCount, [0, 1, 0, 0, 0, 0], "still counted")
	check_eq(tree.GetEntityIntersections(Vector2(200, 0), 5, 2, C.tcEnemies), [], "never found")
	tree.Free()


## eiEntitiesInRange / eiClosestEntityInRange through the components; the tree follows eiPosition and eiTeamID.
func test_range_queries() -> void:
	_game()
	var me := _unit(10, Vector2(0, 0), 1)
	var e1 := _unit(11, Vector2(4, 0), 2)
	var e2 := _unit(12, Vector2(-3, 0), 2)
	var ally := _unit(13, Vector2(1, 0), 1)
	check_eq(_ids(_in_range(me.Position, 5.0, 1, C.tcEnemies)), [12, 11], "enemies in tree order")
	check_eq(_ids(_in_range(me.Position, 5.0, 1, C.tcAllies)), [10, 13], "allies incl. itself")
	check(_in_range(Vector2(100, 100), 5.0, 1, C.tcAll) == null, "nothing found: null")
	check_eq(_ids(_in_range(me.Position, 5.0, 1, C.tcEnemies, func(e): return e.ID != 12)), [11], "filter")
	check(_in_range(me.Position, 5.0, 1, C.tcEnemies, func(_e): return false) == null, "all filtered: null")
	check_eq(_bus.Read(C.eiClosestEntityInRange, [me.Position, 5.0, 1, C.tcEnemies, null]), e2, "closest enemy")
	check_eq(_bus.Read(C.eiClosestEntityInRange, [me.Position, 5.0, 1, C.tcEnemies, func(e): return e != e2]), e1,
		"closest passing the filter")
	check(_bus.Read(C.eiClosestEntityInRange, [me.Position, 1.0, 1, C.tcEnemies, null]) == null, "none in range")
	e2.Position = Vector2(30, 30)
	check_eq(_ids(_in_range(me.Position, 5.0, 1, C.tcEnemies)), [11], "moved away")
	ally.Eventbus.Write(C.eiTeamID, [2])
	check_eq(_ids(_in_range(me.Position, 5.0, 1, C.tcEnemies)), [11, 13], "team change (13 re-added last)")


## Equal distances: the first found stays closest (strict <).
func test_closest_tie() -> void:
	_game()
	var a := _unit(11, Vector2(3, 0), 2)  # top-right quadrant, found second
	var b := _unit(12, Vector2(-3, 0), 2)  # top-left quadrant, found first
	check_eq(_ids(_in_range(Vector2.ZERO, 5.0, 1, C.tcEnemies)), [12, 11], "tree order")
	check_eq(_bus.Read(C.eiClosestEntityInRange, [Vector2.ZERO, 5.0, 1, C.tcEnemies, null]), b, "first found wins")
	check(a != null, "a exists")


## eiExiled takes the unit out of the tree and back; eiDie asks the global bus to remove the component; freeing
## the component removes the unit.
func test_exile_die_free() -> void:
	_game()
	var probe := RemoveProbe.new().Create(_game_entity) as RemoveProbe
	var u := _unit(11, Vector2(2, 2), 2)
	u.Eventbus.Write(C.eiExiled, [true])
	check(_in_range(Vector2.ZERO, 5.0, 1, C.tcEnemies) == null, "exiled: gone")
	u.Position = Vector2(3, 3)
	u.Eventbus.Write(C.eiExiled, [false])
	check_eq(_ids(_in_range(Vector2.ZERO, 5.0, 1, C.tcEnemies)), [11], "back, at its new position")
	var collision := _last_collision
	u.Eventbus.Trigger(C.eiDie, [0, 0])
	check_eq(probe.Removed, [[11, collision.UniqueID]], "eiRemoveComponent for the collision component")
	collision.Free()
	check(_in_range(Vector2.ZERO, 5.0, 1, C.tcEnemies) == null, "freed: gone")


## TServerCollisionManagerComponent.OnEnemiesInRangeOf: filter rates entities, below 0 drops them.
func test_enemies_in_range_efficiency() -> void:
	_game(C.nsServer, true)
	_unit(11, Vector2(4, 0), 2)
	_unit(12, Vector2(-3, 0), 2)
	var found = _bus.Read(C.eiEnemiesInRangeEfficiency, [Vector2.ZERO, 5.0, 1, C.tcEnemies, null])
	check_eq(found.map(func(t): return [t.Target.EntityID, t.Efficiency]), [[12, 1.0], [11, 1.0]], "unfiltered: 1")
	found = _bus.Read(C.eiEnemiesInRangeEfficiency, [Vector2.ZERO, 5.0, 1, C.tcEnemies,
		func(e): return -1.0 if e.ID == 12 else 0.25])
	check_eq(found.map(func(t): return [t.Target.EntityID, t.Efficiency]), [[11, 0.25]], "rated, 12 dropped")
	check(_bus.Read(C.eiEnemiesInRangeEfficiency, [Vector2.ZERO, 5.0, 1, C.tcEnemies, func(_e): return -0.5]) == null,
		"all dropped: null")


## The real client Lanetower (Units\Neutral\Lanetower.ets:224-227): group 12 is ready while a unit or building
## of another team is within eiWelaRange of group 1 (15) and neither invisible nor banished.
func test_lanetower_enemies_nearby() -> void:
	_game(C.nsClient)
	var tower := TEntity.CreateFromScript("Units\\Neutral\\Lanetower", _bus)
	_free.push_front(tower)
	check_eq(TEntity.LastScriptError, "", "script ran")
	tower.Eventbus.Write(C.eiTeamID, [1])
	var ready := func() -> bool: return RParam.AsBoolean(tower.Eventbus.Read(C.eiIsReady, [], [12]))
	check(not ready.call(), "nobody around")
	var enemy := _unit(20, Vector2(15.4, 0), 2)
	enemy.Blackboard.SetValue(C.eiUnitProperties, [], DSet.Make([C.upUnit]))
	check(ready.call(), "enemy unit touching the range (15 + 0.5)")
	enemy.Position = Vector2(15.6, 0)
	check(not ready.call(), "just out of range")
	enemy.Position = Vector2(5, 0)
	enemy.Blackboard.SetValue(C.eiUnitProperties, [], DSet.Make([C.upUnit, C.upInvisible]))
	check(not ready.call(), "invisible")
	enemy.Blackboard.SetValue(C.eiUnitProperties, [], DSet.Make([C.upBuilding]))
	check(ready.call(), "building")
	enemy.Eventbus.Write(C.eiTeamID, [1])
	check(not ready.call(), "an ally")
