class_name TEntityManagerComponent
extends TEntityComponent
## Port of TEntityManagerComponent (BaseConflict.EntityComponents.Shared.pas:276, implementation :1282).
## Manages all deployed entities (eiNewEntity registers them) and frees entities, components and component groups
## deferred, at the next Idle. Reached as Game.EntityManager.
## Port notes: FEntities is a Dictionary in insertion order (the original's TDictionary iterates in hash order;
## only GetEntityByUID's first match, FilterEntities and GetDeployedEntityList see the order). The nexus list is
## an Array. InvokeEventOnEntity needs TEventbus.InvokeWithRawData and comes with the network sync (phase 3).

var FEntities := {}  # ID -> TEntity
var FComponentGroupsToKill: Array = []  # of [EntityID, SetComponentGroup]
var FComponentsToKill: Array = []  # of [EntityID, ComponentID]
var FIDCounter := 0
var FNexusList: Array = []
var FEntitiesToFree: Array = []

var DeployedEntityCount: int:
	get:
		return GetDeployedEntityCount()


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnNewEntity", C.eiNewEntity, C.epMiddle, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnRemoveComponent", C.eiRemoveComponent, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnRemoveComponentGroup", C.eiRemoveComponentGroup, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnKillEntity", C.eiKillEntity, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnSetGridFieldBlocking", C.eiSetGridFieldBlocking, C.epLast, C.etWrite, C.esGlobal))
	e.append(XEvent("OnReplaceEntity", C.eiReplaceEntity, C.epLower, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FEntitiesToFree = []
	FEntities = {}
	FComponentsToKill = []
	FComponentGroupsToKill = []
	FIDCounter = 1  # 1 is reserved for game entity
	FNexusList = []
	return self


func Destroy() -> void:
	KillDeferred()
	var Entities: Array = FEntities.values()
	FEntities.clear()
	for Entity in Entities:
		Entity.Free()
	# killed entities can defer killed other entites
	KillDeferred()
	FNexusList = []
	FEntitiesToFree = []
	FComponentGroupsToKill = []
	FComponentsToKill = []
	super()


func BeforeComponentFree() -> void:
	super()
	KillDeferred()


func NewEntity(Entity) -> void:
	assert(Entity.ID != 0)
	if FEntities.has(Entity.ID):
		push_error("TEntityManagerComponent.NewEntity: duplicate entity ID %d" % Entity.ID)  # TDictionary.Add raises
		return
	FEntities[Entity.ID] = Entity


func KillDeferred() -> void:
	for Entry in FComponentGroupsToKill:
		var Entity = TryGetEntityByID(Entry[0])
		if Entity != null:
			Entity.FreeGroups(Entry[1])
	FComponentGroupsToKill.clear()

	# components should not free other component, but for safety
	var ComponentsToFree: Array = FComponentsToKill.duplicate()
	FComponentsToKill.clear()
	for Entry in ComponentsToFree:
		var Entity = TryGetEntityByID(Entry[0])
		if Entity != null:
			Entity.Eventbus.Trigger(C.eiBeforeFree, [], [], Entry[1])
			Entity.Eventbus.Trigger(C.eiFree, [], [], Entry[1])

	# entities can free other entities, so preserve list
	var EntitiesToFree: Array = FEntitiesToFree.duplicate()
	FEntitiesToFree.clear()
	for Entity in EntitiesToFree:
		FEntities.erase(Entity.ID)
		Entity.Free()


## Called by the game loop every frame.
func Idle() -> void:
	KillDeferred()


func OnNewEntity(Entity) -> bool:
	NewEntity(Entity)
	return true


func OnRemoveComponent(EntityID, ComponentID) -> bool:
	FreeComponent(RParam.AsInteger(EntityID), RParam.AsInteger(ComponentID))
	return true


func OnRemoveComponentGroup(EntityID, ComponentGroup) -> bool:
	FreeComponentGroup(RParam.AsInteger(EntityID), RParam.AsSet(ComponentGroup))
	return true


func OnKillEntity(EntityID) -> bool:
	var ID := RParam.AsInteger(EntityID)
	var Entity = FEntities.get(ID)
	if Entity != null:
		FEntities.erase(ID)
		FEntitiesToFree.append(Entity)
	return true


func OnSetGridFieldBlocking(GridID, GridCoord, BlockingEntityID) -> bool:
	var BuildZone = GlobalEventbus().Game.Map.BuildZones.GetBuildZone(RParam.AsInteger(GridID))
	BuildZone.SetFieldID(RParam.AsIntVector2(GridCoord), RParam.AsInteger(BlockingEntityID))
	return true


func OnReplaceEntity(oldEntityID, newEntityID, isSameEntity) -> bool:
	var OldID := RParam.AsInteger(oldEntityID)
	var NewID := RParam.AsInteger(newEntityID)
	if RParam.AsBoolean(isSameEntity):
		var Entity = TryGetEntityByID(OldID)
		if Entity != null:
			Entity.ID = NewID
			FEntities.erase(OldID)
			FEntities[Entity.ID] = Entity
			for Entry in FComponentGroupsToKill:
				if Entry[0] == OldID:
					Entry[0] = NewID
			for Entry in FComponentsToKill:
				if Entry[0] == OldID:
					Entry[0] = NewID
		else:
			push_warning("TEntityManagerComponent.OnReplaceEntity: Entity to replace not found!")
	GlobalEventbus().Game.Map.BuildZones.UpdateEntityIDInBuildZones(OldID, NewID)
	return true


## Returns a list of all deployed entities.
func GetDeployedEntityList() -> Array:
	return FEntities.values()


## Generate unique EntityID. IDs starting at 2 (IDs < 0 are invalid, 0 is global eventbus, 1 is game entity) and
## increasing one by one.
func GenerateUniqueID() -> int:
	FIDCounter += 1
	return FIDCounter


func HasEntityByID(ID: int) -> bool:
	return FEntities.has(ID)


## Return the Entity to the ID if found, otherwise null.
func GetEntityByID(ID: int):
	return FEntities.get(ID)


## Return the Entity to the UID if found, otherwise null.
func GetEntityByUID(UID: String):
	if UID != "":
		for Entity in FEntities.values():
			if Entity.UID == UID:
				return Entity
	return null


## Frees the given componentgroup of the entity at the beginning of the next frame.
func FreeComponentGroup(EntityID: int, Group: Array) -> void:
	FComponentGroupsToKill.append([EntityID, Group])


## FreeComponent(EntityID, ComponentID) or FreeComponent(Component).
func FreeComponent(EntityIDOrComponent, ComponentID: int = 0) -> void:
	if EntityIDOrComponent is TEntityComponent:
		FreeComponent(EntityIDOrComponent.Owner.ID, EntityIDOrComponent.UniqueID)
	else:
		FComponentsToKill.append([EntityIDOrComponent, ComponentID])


## A safe way to free entities without being in a event stack.
func FreeEntity(Entity) -> void:
	if not FEntitiesToFree.has(Entity):
		FEntitiesToFree.append(Entity)


func FilterEntities(MustHave: Array, MustNotHave: Array) -> Array:
	var Result: Array = []
	for Entity in FEntities.values():
		var Props: Array = Entity.UnitProperties()
		if not DSet.Intersects(Props, MustNotHave) and (MustHave.is_empty() or DSet.Intersects(Props, MustHave)):
			Result.append(Entity)
	return Result


## Rebuilds the list from the global eiEnumerateNexus read on every call.
func NexusList() -> Array:
	var List = GlobalEventbus().Read(C.eiEnumerateNexus, [])
	FNexusList = List if List is Array else []
	return FNexusList


func NexusByTeamID(TeamID: int):
	return TryGetNexusByTeamID(TeamID)


func TryGetNexusByTeamID(TeamID: int):
	for itemNexus in NexusList():
		if itemNexus.TeamID() == TeamID:
			return itemNexus
	return null


## Retrieves the next hostile nexus: NexusNextEnemy(Position, MyTeamID).
## Note: like the original, it keeps the nexus with the *largest* distance (`bestDistance < distance`).
func NexusNextEnemy(Position: Vector2, MyTeamID: int):
	return TryGetNexusNextEnemy(Position, MyTeamID)


## Same bug as NexusNextEnemy: returns the farthest nexus.
func NexusNext(Position: Vector2):
	var Result = null
	var bestDistance := -1.0
	for itemNexus in NexusList():
		var distance: float = itemNexus.Position.distance_to(Position)
		if bestDistance < 0 or bestDistance < distance:
			bestDistance = distance
			Result = itemNexus
	return Result


## TryGetNexusNextEnemy(Position, MyTeamID) or TryGetNexusNextEnemy(reference: TEntity).
func TryGetNexusNextEnemy(PositionOrReference, MyTeamID: int = 0):
	var Position: Vector2
	if PositionOrReference is TEntity:
		Position = PositionOrReference.Position
		MyTeamID = PositionOrReference.TeamID()
	else:
		Position = PositionOrReference
	var Nexus = null
	var bestDistance := -1.0
	for itemNexus in NexusList():
		if itemNexus.TeamID() != MyTeamID:
			var distance: float = itemNexus.Position.distance_to(Position)
			if bestDistance < 0 or bestDistance < distance:
				bestDistance = distance
				Nexus = itemNexus
	return Nexus


func TryGetEntityByID(ID: int):
	return GetEntityByID(ID)


func TryGetEntityByUID(UID: String):
	return GetEntityByUID(UID)


## Return the owning commander of the entity if found, otherwise null.
func GetOwningCommander(Entity):
	return GetEntityByID(RParam.AsInteger(Entity.Eventbus.Read(C.eiOwnerCommander, [])))


func TryGetOwningCommander(Entity):
	return GetOwningCommander(Entity)


## Returns the number of existing entities with the given unitproperties and matching the team constraint.
func EntityCountByUnitProperty(UnitProperties: Array, CountTeamConstraint: int = C.tcAll, TeamID: int = -1) -> int:
	var Result := 0
	for Entity in FEntities.values():
		var Props: Array = RParam.AsSet(Entity.Eventbus.Read(C.eiUnitProperties, []))
		if DSet.Difference(UnitProperties, Props).is_empty() and (
				CountTeamConstraint == C.tcAll
				or (CountTeamConstraint == C.tcEnemies and Entity.TeamID() != TeamID)
				or (CountTeamConstraint == C.tcAllies and Entity.TeamID() == TeamID)):
			Result += 1
	return Result


func GetDeployedEntityCount() -> int:
	return FEntities.size()
