class_name TServerCollisionManagerComponent
extends TCollisionManagerComponent
## Port of TServerCollisionManagerComponent (GameServer/BaseConflict.EntityComponents.Server.pas:346,
## implementation :1582): the server's Game.CollisionManager. Adds eiEnemiesInRangeEfficiency: the entities in
## range (team constraint as in eiEntitiesInRange) rated by Filter, a Callable(Entity) -> float
## (ProcFilterFunction) or null (every entity rates 1). Entities rated below 0 are left out. Returns an Array of
## RTargetWithEfficiency in tree order, or null when nothing is left.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnEnemiesInRangeOf", C.eiEnemiesInRangeEfficiency, C.epFirst, C.etRead, C.esGlobal))


## Return all matching enemies.
func OnEnemiesInRangeOf(Position, Range, SourceTeamID, TargetTeamConstraint, Filter):
	var nearby := FQuadTree.GetEntityIntersections(RParam.AsVector2(Position), RParam.AsSingle(Range),
		RParam.AsInteger(SourceTeamID), RParam.AsInteger(TargetTeamConstraint))
	var EntitiesFound: Array = []
	for element in nearby:
		var e = element.Data
		var Efficiency := 1.0
		if Filter != null:
			Efficiency = RParam.ToSingle(Filter.call(e))
		if Efficiency >= 0:
			EntitiesFound.append(RTargetWithEfficiency.Create(RTarget.Create(e), Efficiency))
	if EntitiesFound.is_empty():
		return null
	return EntitiesFound
