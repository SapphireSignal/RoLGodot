extends "res://tests/test_case.gd"
## The game server <-> client link (phase 3 network): TLoopbackSocket, TCommandSequence, TNetworkComponent (raw
## parameters, NET_EVENT), TServerNetworkComponent (players, handshake, world, entities, events), TClientNetworkComponent
## and TClientGame.JoinLocal, TGameThread's player state machine.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const FRAME = 32.0
const TOKEN = "1"  # CreateTestserverGameInfo's secret key

var _thread: TGameThread = null
var _client: TClientGame = null


func after_each() -> void:
	if _client != null:
		_client.Free()
	_client = null
	if _thread != null:
		_thread.Free()
	_thread = null
	TTimeManager.SetFakeTime(null)
	super()


func _sandbox_client_info() -> TGameInformation:
	var info := TGameInformation.new().Create()
	info.ScenarioUID = BC.TESTSERVER_SCENARIO_UID
	info.League = BC.TESTSERVER_SENARIO_LEAGUE
	info.Scenario = HScenario.ResolveScenario(info.ScenarioUID, info.League)
	return info


## One frame of both: the server's (DoComputeGame), then the client's (TickTack, eiIdle, ready check, Game.Idle).
func _frame() -> void:
	TTimeManager.SetFakeTime(TTimeManager.GetFakeTime() + FRAME)
	_thread.DoComputeGame()
	TThreadContext.Current().GameTimeManager.TickTack()
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	_client.ReadyWhenLoaded()
	_client.Idle()


func _run_for(ms: float) -> void:
	var until: float = TTimeManager.GetFakeTime() + ms
	while TTimeManager.GetFakeTime() + FRAME <= until:
		_frame()


func _joined_sandbox() -> void:
	TTimeManager.SetFakeTime(1000.0)
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	_client = TClientGame.JoinLocal(_thread, _sandbox_client_info(), TOKEN)


func _card_group(commander: TEntity, pattern: String) -> int:
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == pattern:
			return g
	return -1


## Packets arrive in send order as copies; a close disconnects both ends, what was sent stays readable.
func test_loopback_socket() -> String:
	var pair := TLoopbackSocket.CreatePair()
	var server: TLoopbackSocket = pair[0]
	var client: TLoopbackSocket = pair[1]
	check(not client.IsDataPacketAvailable(), "nothing yet")
	var first := TCommandSequence.new().Create(BC.NET_EVENT)
	first.AddData(5)
	server.SendData(first)
	first.AddData(6)  # after sending: not on the wire
	server.SendCommand(BC.NET_CLIENT_READY)
	check(client.IsDataPacketAvailable(), "arrived")
	var got := client.ReceiveDataPacket()
	check_eq(got.Command, BC.NET_EVENT, "first packet first")
	check_eq(got.Read(), 5, "its data")
	check_eq(got.Data.size(), 1, "a copy of what was sent")
	server.CloseConnection()
	check(client.IsDisconnected() and server.IsDisconnected(), "both ends closed")
	check_eq(client.Status, TLoopbackSocket.TCPStDisconnected, "status")
	check_eq(client.ReceiveDataPacket().Command, BC.NET_CLIENT_READY, "still readable")
	server.SendCommand(BC.NET_EVENT)
	check(not client.IsDataPacketAvailable(), "nothing goes over a closed connection")
	return take_failure()


## The parameters as they come off the wire: empty strings and arrays (size 0) arrive empty, records are copies.
func test_raw_parameters() -> String:
	var target := RTarget.Create(7)
	var raw := TNetworkComponent.RawParameters([3, 1.5, true, "", [], Vector2(1, 2), target, [1, 2], "text"])
	check_eq(raw.slice(0, 6), [3, 1.5, true, null, null, Vector2(1, 2)], "values, empties")
	check(raw[6] is RTarget and raw[6] != target, "the record is a copy")
	check_eq(raw[6].EntityID, 7, "with its data")
	check_eq(raw[7], [1, 2], "array")
	check_eq(raw[8], "text", "a string")
	return take_failure()


## An unknown token is refused (NET_SECURITY_ERROR 409): no client game.
func test_unknown_token_is_refused() -> String:
	TTimeManager.SetFakeTime(1000.0)
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	var client := TClientGame.JoinLocal(_thread, _sandbox_client_info(), "not a token")
	check(client == null, "refused")
	check_eq(_thread.NetworkComponent.ConnectedPlayerCount(), 0, "nobody connected")
	return take_failure()


## The handshake: the token's commanders come back (NET_ASSIGNED_PLAYER), the world follows the client's
## NET_CLIENT_ENTER_CORE (every scripted entity, the same IDs), then the client is ready and the server starts.
func test_join_receives_world_and_starts_the_game() -> String:
	_joined_sandbox()
	check(_client != null, "joined")
	if _client == null:
		return take_failure()
	var commander_ids: Array = _thread.InternalGame.Commanders.slice(0, 15).map(func(e: TEntity) -> int: return e.ID)
	check_eq(_client.FTokenMapping, commander_ids, "the token's commanders (slots 0..14)")
	check_eq(_client.GameState, TClientGame.gsPreparing, "preparing")
	check_eq(_thread.NetworkComponent.FPlayers[0].State, TServerNetworkComponent.psPreparing, "server: player preparing")
	_frame()
	check_eq(_client.GameState, TClientGame.gsRunning, "world received: running")
	var server_ids: Array = []
	for entity: TEntity in _thread.InternalGame.EntityManager.GetDeployedEntityList():
		if entity.ScriptFile != "":
			server_ids.append(entity.ID)
	var client_ids: Array = _client.EntityManager.GetDeployedEntityList().map(func(e: TEntity) -> int: return e.ID)
	server_ids.sort()
	client_ids.sort()
	check(server_ids.size() > 10, "a world")
	check_eq(client_ids, server_ids, "the client has every scripted server entity")
	check_eq(_thread.State, TGameThread.gsWaitingForPlayers, "server still waits")
	_frame()  # the server gets NET_CLIENT_READY
	check_eq(_thread.NetworkComponent.FPlayers[0].State, TServerNetworkComponent.psPlaying, "player playing")
	check_eq(_thread.State, TGameThread.gsRunning, "game started")
	check_eq(TEntity.GetLastScriptError(), "", "no script error")
	return take_failure()


## Live: a card the client plays goes to the server (eiUseAbility is a client event); the squad the server drops
## comes back as new entities, the units' moves and deaths as events: the client's copies follow the server's.
func test_played_cards_come_back_as_units_that_walk_and_fight() -> String:
	_joined_sandbox()
	_run_for(BC.GAME_WARMING_DURATION + 3 * FRAME)
	check(_thread.InternalGame.HasStarted(), "started")
	var commanders: Array = []
	for entity: TEntity in _client.EntityManager.GetDeployedEntityList():
		if entity.ID in _client.FTokenMapping:
			commanders.append(entity)
	check(commanders.size() >= 2, "the client has the commanders")
	if commanders.size() < 2:
		return take_failure()
	var positions := [Vector2(-20, -23), Vector2(20, -23)]
	for i in 2:
		var commander: TEntity = commanders[i]
		var group := _card_group(commander, "Units\\White\\FootmanDrop")
		check(group >= 0, "commander %d has the FootmanDrop" % i)
		var targets := RCommanderAbilityTarget.ArrayToRParam([RCommanderAbilityTarget.Create(positions[i])])
		commander.Eventbus.Trigger(C.eiUseAbility, [targets], [group])
	_run_for(3000.0)
	var server_units: Array = _thread.InternalGame.EntityManager.FilterEntities([C.upUnit], [])
	check_eq(server_units.size(), 8, "two squads on the server")
	var matched := 0
	for unit: TEntity in server_units:
		var copy: TEntity = _client.EntityManager.GetEntityByID(unit.ID)
		if copy == null:
			continue
		matched += 1
		check_eq(copy.ScriptFile, unit.ScriptFile, "same unit")
		check_eq(copy.TeamID(), unit.TeamID(), "same team")
		check(copy.Position.distance_to(unit.Position) < 1.5, "unit %d where the server has it: %s vs %s" % [unit.ID, copy.Position, unit.Position])
	check_eq(matched, 8, "every unit on the client")
	_run_for(27000.0)
	check_eq(_thread.InternalGame.EntityManager.FilterEntities([C.upUnit], []).size(), 0, "all fell on the server")
	var left := _client.EntityManager.GetDeployedEntityList().filter(func(e: TEntity) -> bool: return e.ScriptFile.ends_with("Footman"))
	check_eq(left.size(), 0, "and on the client")
	check_eq(TEntity.GetLastScriptError(), "", "no script error")
	return take_failure()
