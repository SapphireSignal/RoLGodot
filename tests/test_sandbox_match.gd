extends "res://tests/test_case.gd"
## The phase 3 goal: a headless sandbox match (TGameManager.CreateTestserverGameInfo run by TGameThread at 32 ms
## frames). Both players play their FootmanDrop; the squads meet on the lane and trade hits.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const FRAME = 32.0

var _thread: TGameThread
var _probes := {}  # entity ID -> HitProbe


## On a unit: records the damage it takes (after armor and health handlers) with the game time.
class HitProbe:
	extends TGDEntityComponent
	var Log: Array = []
	var Team := 0
	var ScriptFile := ""

	func CreateGroupedAll(Owner = null) -> TEntityComponent:
		super(Owner)
		Team = Owner.TeamID()
		ScriptFile = Owner.ScriptFile
		return self

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnTakeDamageLast", C.eiTakeDamage, C.epLast, C.etRead))
		e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
		e.append(XEvent("OnPreFire", C.eiPreFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))

	func _health() -> float:
		return snappedf(RParam.AsSingle(Owner.Blackboard.GetIndexedValue(C.eiResourceBalance, [], C.reHealth)), 0.001)

	func OnTakeDamageLast(Amount, _DamageType, InflictorID, Previous):
		Log.append(["Hit", TTimeManager.GetFakeTime(), snappedf(RParam.AsSingle(Amount), 0.001), RParam.AsInteger(InflictorID),
			_health()])
		return Previous

	func OnPreFire(_Targets) -> bool:
		Log.append(["PreFire", TTimeManager.GetFakeTime(), TEventbus.GetCurrentEvent_CalledToGroup().duplicate()])
		return true

	func OnFire(_Targets) -> bool:
		Log.append(["Fire", TTimeManager.GetFakeTime(), TEventbus.GetCurrentEvent_CalledToGroup().duplicate()])
		return true

	func OnDie(_KillerID, _KillerCommanderID) -> bool:
		Log.append(["Die", TTimeManager.GetFakeTime()])
		return true


func after_each() -> void:
	_probes = {}
	if _thread != null:
		_thread.Free()
	_thread = null
	TTimeManager.SetFakeTime(null)
	super()


func _frame() -> void:
	TTimeManager.SetFakeTime(TTimeManager.GetFakeTime() + FRAME)
	_thread.DoComputeGame()
	for entity: TEntity in _thread.InternalGame.EntityManager.FilterEntities([C.upUnit], []):
		if not _probes.has(entity.ID):
			_probes[entity.ID] = HitProbe.new().CreateGroupedAll(entity)


func _run_for(ms: float) -> void:
	var until: float = TTimeManager.GetFakeTime() + ms
	while TTimeManager.GetFakeTime() + FRAME <= until:
		_frame()


func _card_group(commander: TEntity, pattern: String) -> int:
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == pattern:
			return g
	return -1


func _play(commander: TEntity, pattern: String, position: Vector2) -> bool:
	var group := _card_group(commander, pattern)
	var targets := RCommanderAbilityTarget.ArrayToRParam([RCommanderAbilityTarget.Create(position)])
	var can := RParam.AsBoolean(commander.Eventbus.Read(C.eiCanUseAbility, [targets], [group]))
	commander.Eventbus.Trigger(C.eiUseAbility, [targets], [group])
	return can


func _started_sandbox() -> TServerGame:
	TTimeManager.SetFakeTime(1000.0)
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	_thread.SetAllPlayersPlaying()
	_frame()
	_run_for(BC.GAME_WARMING_DURATION + FRAME)
	return _thread.InternalGame


## The entries of one kind in a probe log, optionally only those called to a group.
func _entries(log: Array, kind: String, group = null) -> Array:
	return log.filter(func(x): return x[0] == kind and (group == null or x[2] == group))


## Footman (Units\White\Footman.ets): 32 HP, medium armor, a sword hit of 13 melee damage every 2000 ms (group 1)
## landing 300 ms after the attack starts (eiWelaActionpoint), and a shield block (group 2) every 5000 ms that
## swallows a hit. Medium armor takes 80% of melee damage (TArmorComponent): 10.4 per hit; a unit dies below 1 HP
## (THealthComponent.UpdateAlive), so the third hit kills (32 - 3 * 10.4 = 0.8). At 32 ms frames the times round up
## to whole frames: the hit comes 320 ms after the attack starts and attacks repeat every 2048 ms.
## FootmanDrop drops a squad of 4 (Units\White\FootmanDrop.ets).
func test_footman_squads_trade_hits() -> void:
	var game := _started_sandbox()
	check(game.HasStarted(), "started")
	var blue: TEntity = game.Commanders[0]
	var red: TEntity = game.Commanders[1]
	check(_play(blue, "Units\\White\\FootmanDrop", Vector2(-20, -23)), "blue can drop")
	check(_play(red, "Units\\White\\FootmanDrop", Vector2(20, -23)), "red can drop")
	_run_for(30000.0)
	check_eq(TEntity.GetLastScriptError(), "", "no script error")

	var teams: Array = _probes.values().map(func(p: HitProbe) -> Array: return [p.Team, p.ScriptFile])
	teams.sort()
	var squad: Array = []
	for team in [1, 2]:
		for i in 4:
			squad.append([team, "Units\\White\\Footman"])
	check_eq(teams, squad, "two squads of 4 footmen")
	check_eq(game.EntityManager.FilterEntities([C.upUnit], []).size(), 0, "all fell within 30 s")

	for id in _probes:
		var log: Array = _probes[id].Log
		var attacks := _entries(log, "PreFire", [1])
		var swings := _entries(log, "Fire", [1])
		check(attacks.size() >= 1, "unit %d attacked" % id)
		for i in attacks.size():
			if i > 0:
				check_eq(attacks[i][1] - attacks[i - 1][1], 2048.0, "unit %d: attack every 2000 ms (2048 at 32 ms frames)" % id)
		for i in swings.size():
			check_eq(swings[i][1] - attacks[i][1], 320.0, "unit %d: hit at the action point, 300 ms (320)" % id)
		var hits := _entries(log, "Hit")
		var blocks := _entries(log, "Fire", [2])
		var damaging := hits.filter(func(x): return x[2] > 0.0)
		# singles: compared at one decimal
		check_eq(damaging.map(func(x): return "%.1f" % x[2]), ["10.4", "10.4", "10.4"],
			"unit %d: three hits of 13 x 0.8" % id)
		check_eq(damaging.map(func(x): return "%.1f" % x[4]), ["21.6", "11.2", "0.0"],
			"unit %d: health after each hit (0.8 left: dead, emptied)" % id)
		check_eq(hits.size() - damaging.size(), blocks.size(), "unit %d: every block swallows a hit" % id)
		check(blocks.size() >= 1 and hits[0][2] == 0.0, "unit %d: the first hit is blocked" % id)
		check_eq(_entries(log, "Die").size(), 1, "unit %d died once" % id)


## A spawner placed after the game start fires at once (TBrainSpawnerComponent.OnDeploy): its squad of 4
## (FootmanSpawner.ets) appears at the build zone's spawn target and walks the lane towards the enemy. Later waves
## come when the wave rotation reaches its field (one of 20 per wave, a wave every 2 ticks), not within this test.
func test_spawner_spawns_its_squad_which_walks_the_lane() -> void:
	var game := _started_sandbox()
	var blue: TEntity = game.Commanders[0]
	var group := _card_group(blue, "Units\\White\\FootmanSpawner")
	var targets := RCommanderAbilityTarget.ArrayToRParam([RCommanderAbilityTarget.CreateBuildTarget(0, Vector2i(1, 1))])
	check(RParam.AsBoolean(blue.Eventbus.Read(C.eiCanUseAbility, [targets], [group])), "can place the spawner")
	blue.Eventbus.Trigger(C.eiUseAbility, [targets], [group])
	_run_for(1000.0)
	var spawners: Array = game.EntityManager.FilterEntities([C.upSpawner], [])
	check_eq(spawners.size(), 1, "one spawner")
	var squad: Array = game.EntityManager.FilterEntities([C.upUnit], [])
	check_eq(squad.size(), 4, "its squad of 4 at once")
	var start_x: Array = squad.map(func(e: TEntity) -> float: return e.Position.x)
	_run_for(3000.0)
	for i in squad.size():
		check(squad[i].Position.x > start_x[i] + 5.0, "footman %d walks towards the enemy" % i)
		check_eq(squad[i].TeamID(), 1, "blue footman")
	check_eq(TEntity.GetLastScriptError(), "", "no script error")


## Footmen dropped in front of the red nexus attack it: 13 per hit (fortified armor takes non-siege damage as is).
func test_footmen_damage_the_nexus() -> void:
	var game := _started_sandbox()
	var nexus: TEntity = game.EntityManager.NexusByTeamID(2)
	var probe := HitProbe.new().CreateGroupedAll(nexus)
	var start: float = RParam.AsSingle(nexus.Blackboard.GetIndexedValue(C.eiResourceBalance, [], C.reHealth))
	check(_play(game.Commanders[0], "Units\\White\\FootmanDrop", Vector2(85, -23)), "drop at the nexus")
	_run_for(5000.0)
	var hits := _entries(probe.Log, "Hit")
	check(hits.size() >= 2, "the nexus is hit")
	var health := start
	for hit in hits:
		check_eq(hit[2], 13.0, "13 per hit")
		health -= 13.0
		check_eq(hit[4], health, "nexus health goes down by 13")
	check(_entries(probe.Log, "Fire", [1]).size() >= 1, "the nexus shoots back")
	check_eq(TEntity.GetLastScriptError(), "", "no script error")
