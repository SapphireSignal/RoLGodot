class_name TClientGame
extends TGame
## Part of TClientGame (BaseConflict.Game.Client.pas:36, implementation :79): the client's game on its own global
## bus (client side): the client map (with its decorations), collision and entity manager, then Initialize runs the
## scenario scripts' client parts (e.g. the PvE scenarios' Game.ClientMap.AddDecoEntity). Entities come from the
## server (TClientNetworkComponent.DeserializeEntity): here AddServerEntity takes a server entity's TEntityStream.
## Not ported yet: network, input, camera, GUI, sound, commander manager, decay / trace managers, minimap and the
## build grid manager.

var FClientMap: TClientMap = null

var ClientMap: TClientMap:
	get:
		return FClientMap


func Create(GameInfo_ = null, _GlobalEventbus = null) -> TGame:
	var Bus := TEventbus.new().Create(null)
	Bus.ApplicationType = C.nsClient
	super(GameInfo_, Bus)
	# the client's EntityDataCache is per process (BaseConflictMainUnit); the port keeps it on the global bus
	FGlobalEventbus.EntityDataCache = TEntityDataCache.new().Create(FGlobalEventbus)
	if FGameInfo.Scenario.MapName == "":
		push_error("TClientGame.Create: Mapname should not be empty!")
	else:
		FClientMap = TClientMap.CreateFromFile(FGameInfo.Scenario.MapName, FGlobalEventbus)
	CollisionManager = TCollisionManagerComponent.new().Create(GameEntity)
	FEntityManager = TEntityManagerComponent.new().Create(GameEntity)
	Initialize()
	return self


func Destroy() -> void:
	var Bus := FGlobalEventbus
	if FClientMap != null:
		FClientMap.FreeDecorations()
		if FClientMap.is_inside_tree():
			FClientMap.queue_free()
		else:
			FClientMap.free()
		FClientMap = null
	super()
	Bus.Free()


## TClientGame.Idle: the map, then TGame.Idle.
func Idle() -> void:
	super()


## Network stand-in for joining a game: TServerNetworkComponent.SendWorld (every deployed entity with a script, in
## the entity manager's order) received by TClientNetworkComponent (NET_NEW_ENTITY -> DeserializeEntity).
## Returns the client entities made.
func ReceiveWorld(ServerGame: TGame) -> Array:
	var Result: Array = []
	for Entity: TEntity in ServerGame.EntityManager.GetDeployedEntityList():
		if Entity.ScriptFile == "":
			continue
		var Stream := TEntityStream.new()
		Entity.Serialize(Stream)
		var Copy := AddServerEntity(Stream)
		if Copy != null:
			Result.append(Copy)
	return Result


## TClientNetworkComponent.DeserializeEntity: a server entity's stream (TEntity.Serialize) becomes the client's
## copy of it with a TLogicToWorldComponent, eiAfterCreate and Deploy. Returns it (null if it exists already).
func AddServerEntity(Stream: TEntityStream) -> TEntity:
	var EntityID: int = Stream.Read()
	if FEntityManager.HasEntityByID(EntityID):
		return null
	var Entity := TEntity.Deserialize(EntityID, Stream, FGlobalEventbus)
	if Entity == null:
		return null
	TLogicToWorldComponent.new().Create(Entity)
	Entity.Eventbus.Trigger(C.eiAfterCreate, [])
	Entity.Deploy()
	return Entity
