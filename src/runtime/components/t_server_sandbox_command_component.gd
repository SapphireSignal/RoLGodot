class_name TServerSandboxCommandComponent
extends TGDEntityComponent
## Port of TServerSandboxCommandComponent (GameServer/BaseConflict.EntityComponents.Server.pas:443, implementation
## :3482), server only: the sandbox commands a client sends (global eiClientCommand [Command, Param1], BC.cc*).
## Kills go through eiDelayedKillEntity (next Idle). Clearing lane or golem towers respawns neutral lane nodes at the
## three lane spots (both lanes on the Classic map); the base building levels respawn the nexus, and outside PvE
## scenarios lane towers of that level and the middle capture point (else three lane nodes).
## Port notes: the sandbox overwatch globals are Game.Overwatch / Game.OverwatchClearable (see
## TServerEntityManagerComponent). The camera commands are client side.

const BC = preload("res://src/runtime/base_conflict_constants.gd")


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnClientCommand", C.eiClientCommand, C.epLast, C.etTrigger, C.esGlobal))


func OnClientCommand(Command, _Param1) -> bool:
	var ServerGame = GlobalEventbus().Game
	match RParam.AsInteger(Command):
		BC.ccClearUnits:
			_KillAll(ServerGame.EntityManager.FilterEntities([C.upUnit, C.upBuilding, C.upCharm], [C.upBase, C.upGolem]))
		BC.ccClearAllUnits:
			_KillAll(ServerGame.EntityManager.FilterEntities([C.upUnit, C.upBuilding, C.upCharm], [C.upBase]))
		BC.ccClearSpawners:
			_KillAll(ServerGame.EntityManager.FilterEntities([C.upSpawner, C.upBuilding], [C.upBase, C.upGolem]))
		BC.ccClearLaneTowers:
			_KillAll(ServerGame.EntityManager.FilterEntities([C.upLanetower, C.upLaneNode], [C.upGolem]))
			_SpawnLaneNodes(ServerGame)
		BC.ccClearGolemTowers:
			_KillAll(ServerGame.EntityManager.FilterEntities([C.upLanetower, C.upLaneNode], []))
			_SpawnLaneNodes(ServerGame)
		BC.ccBaseBuildingsLevel1:
			_BaseBuildings(ServerGame, 1)
		BC.ccBaseBuildingsLevel2:
			_BaseBuildings(ServerGame, 2)
		BC.ccBaseBuildingsLevel3:
			_BaseBuildings(ServerGame, 3)
		BC.ccBaseBuildingsIndestructible:
			for Entity: TEntity in ServerGame.EntityManager.FilterEntities([C.upBase], [C.upGolem]):
				Entity.Eventbus.Trigger(C.eiResourceCapTransaction, [C.reHealth, 1000000.0, true])
				Entity.Eventbus.Trigger(C.eiResourceTransaction, [C.reHealth, 1000000.0])
				Entity.Eventbus.Trigger(C.eiResourceCapTransaction, [C.reMana, 10000, true])
				Entity.Eventbus.Trigger(C.eiResourceTransaction, [C.reMana, 10000])
		BC.ccToggleOverwatch:
			ServerGame.Overwatch = not ServerGame.Overwatch
		BC.ccToggleOverwatchSandbox:
			ServerGame.OverwatchClearable = not ServerGame.OverwatchClearable
		BC.ccClearOverwatch:
			var FreeOverwatch := func(Component) -> void:
				if Component is TBrainOverwatchSandboxComponent:
					Component.Free()
			for Entity: TEntity in ServerGame.EntityManager.FilterEntities([], []):
				Entity.Eventbus.Trigger(C.eiEnumerateComponents, [FreeOverwatch])
		BC.ccForceGameTick:
			GlobalEventbus().Trigger(C.eiGameTick, [])
	return true


func _KillAll(Entities: Array) -> void:
	for Entity: TEntity in Entities:
		GlobalEventbus().Trigger(C.eiDelayedKillEntity, [Entity.ID])


func _IsClassic(ServerGame) -> bool:
	return ServerGame.GameInformation.Scenario.MapName == BC.MAP_DOUBLE


func _SpawnLaneNodes(ServerGame) -> void:
	var Manager = ServerGame.ServerEntityManager
	Manager.SpawnUnit(-48, -23, "Units\\Neutral\\LaneNode", 0)
	Manager.SpawnUnit(0, -23, "Units\\Neutral\\LaneNode", 0)
	Manager.SpawnUnit(48, -23, "Units\\Neutral\\LaneNode", 0)
	if _IsClassic(ServerGame):
		Manager.SpawnUnit(-48, 23, "Units\\Neutral\\LaneNode", 0)
		Manager.SpawnUnit(0, 23, "Units\\Neutral\\LaneNode", 0)
		Manager.SpawnUnit(48, 23, "Units\\Neutral\\LaneNode", 0)


## ccBaseBuildingsLevel1..3: the three branches differ only in the level of the nexus and lane tower scripts.
func _BaseBuildings(ServerGame, Level: int) -> void:
	var Manager = ServerGame.ServerEntityManager
	var Nexus := "Units\\Neutral\\NexusLevel%d" % Level
	var Lanetower := "Units\\Neutral\\LanetowerLevel%d" % Level
	_KillAll(ServerGame.EntityManager.FilterEntities([C.upBase], [C.upGolem]))
	if _IsClassic(ServerGame):
		Manager.SpawnUnit(-92, 0, Nexus, 1)  # Blue Nexus
	else:
		Manager.SpawnUnit(-96, -23, Nexus, 1)  # Blue Nexus
	if not ServerGame.GameInformation.ScenarioUID.contains(BC.SCENARIO_PVE_DEFAULT_PREFIX):
		Manager.SpawnUnit(-48, -23, Lanetower, 1)
		Manager.SpawnUnit(0, -23, "Units\\Neutral\\LaneNode", 0)  # right capture point
		Manager.SpawnUnit(48, -23, Lanetower, 2)
		if _IsClassic(ServerGame):
			Manager.SpawnUnit(-48, 23, Lanetower, 1)
			Manager.SpawnUnit(0, 23, "Units\\Neutral\\LaneNode", 0)  # left capture point
			Manager.SpawnUnit(48, 23, Lanetower, 2)
			Manager.SpawnUnit(92, 0, Nexus, 2)  # Red Nexus
		else:
			Manager.SpawnUnit(96, -23, Nexus, 2)  # Red Nexus
	else:
		_SpawnLaneNodes(ServerGame)
