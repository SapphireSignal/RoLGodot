extends "res://tests/test_case.gd"
## The game-end and statistics family: TPrimaryTargetComponent (BaseConflict.EntityComponents.Shared.pas:620),
## TServerPrimaryTargetComponent (GameServer/...Server.pas:139), TSuicideOnGameEndComponent (...Client.pas:462),
## TServerCardPlayStatisticsComponent (...Server.pas:330) + TGameStatisticManager.CardPlayed, TWelaEffect{IncomePayout,
## WaveSpawn}Component (...Server.Welas.Special.pas), TWelaEffectStatisticsComponent (...Server.Statistics.pas:60).
## TStatisticsUnitComponent runs in the real golem kill of test_warheads.gd.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

var _bus: TEventbus
var _entities: Array = []
var _log: GlobalLog


class FakeEntityManager:
	extends RefCounted
	var Entities := {}
	var Freed: Array = []

	func GetEntityByID(ID: int):
		return Entities.get(ID)

	func TryGetEntityByID(ID: int):
		return Entities.get(ID)

	func FreeEntity(Entity) -> void:
		Freed.append(Entity.ID)


class FakeGameInformation:
	extends RefCounted
	var Tutorial := false

	func IsTutorial() -> bool:
		return Tutorial


class FakeMap:
	extends RefCounted
	var BuildZones := TBuildZoneManager.new()


class FakeGame:
	extends RefCounted
	var EntityManager := FakeEntityManager.new()
	var Statistics := TGameStatisticManager.new().Create()

	func IsShuttingDown() -> bool:
		return false

	var Commanders: Array = []
	var Map := FakeMap.new()
	var GameInformation := FakeGameInformation.new()


## Global traffic: [name, parameters...] in call order. Wave spawns are seen after the filter (epLast).
class GlobalLog:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnLose", C.eiLose, C.epFirst, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epLast, C.etTrigger, C.esGlobal))

	func Named(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry.slice(1))
		return Result

	func OnLose(TeamID) -> bool:
		Log.append(["Lose", TeamID])
		return true

	func OnWaveSpawn(GridID, Coordinate) -> bool:
		Log.append(["WaveSpawn", GridID, Coordinate])
		return true


## Local traffic of an entity.
class LocalProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnDieLast", C.eiDie, C.epLast, C.etTrigger))
		e.append(XEvent("OnTransaction", C.eiResourceTransaction, C.epFirst, C.etTrigger))

	func OnDieLast(_KillerID, _KillerCommanderID) -> bool:
		Log.append(["DieLast"])
		return true

	func OnTransaction(Res, Amount) -> bool:
		Log.append(["Transaction", Res, Amount])
		return true


## Answers the global eiIncome read with a fixed income per commander ID.
class IncomeSource:
	extends TEntityComponent
	var Incomes := {}

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnIncome", C.eiIncome, C.epMiddle, C.etRead, C.esGlobal))

	func OnIncome(CommanderID, Previous):
		if Incomes.has(RParam.AsInteger(CommanderID)):
			return Incomes[RParam.AsInteger(CommanderID)].Copy()
		return Previous


func _setup(side: int = C.nsServer) -> void:
	TTimeManager.SetFakeTime(0.0)
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = side
	_bus.Game = FakeGame.new()
	var global := _entity(1)
	_log = GlobalLog.new().Create(global)


func _entity(id: int, team: int = 1, commander: int = 0) -> TEntity:
	var e := TEntity.new().Create(_bus, id)
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiOwnerCommander, [], commander)
	_bus.Game.EntityManager.Entities[id] = e
	_entities.append(e)
	return e


func _stats() -> TGameStatisticManager:
	return _bus.Game.Statistics


func after_each() -> void:
	for e in _entities:
		e.Free()
	_entities = []
	if _bus != null:
		_bus.Game = null
		_bus.Free()
		_bus = null
	TTimeManager.SetFakeTime(null)


# --- primary target, game end ---

func test_primary_target_enumerates_nexus() -> void:
	_setup()
	var a := _entity(10, 1)
	var b := _entity(11, 2)
	TPrimaryTargetComponent.new().Create(a)
	TServerPrimaryTargetComponent.new().Create(b)
	var List = _bus.Read(C.eiEnumerateNexus, [])
	check(List is Array and List.size() == 2 and List.has(a) and List.has(b), "both nexus in the list")


func test_nexus_death_loses_the_game() -> void:
	_setup()
	var enemy_eotf := _entity(20, 2, 20)
	enemy_eotf.Blackboard.SetValue(C.eiUnitProperties, [], [C.upHasEchoesOfTheFuture])
	var enemy := _entity(21, 2, 21)
	var ally := _entity(22, 1, 22)
	ally.Blackboard.SetValue(C.eiUnitProperties, [], [C.upHasEchoesOfTheFuture])
	_bus.Game.Commanders = [enemy_eotf, enemy, ally]
	var nexus := _entity(10, 1)
	nexus.Blackboard.SetValue(C.eiUnitProperties, [], [C.upBase])
	var probe: LocalProbe = LocalProbe.new().Create(nexus)
	TServerPrimaryTargetComponent.new().Create(nexus)
	nexus.Eventbus.Trigger(C.eiDie, [5, 21])
	check_eq(_log.Named("Lose"), [[1]], "the nexus' team loses")
	check_eq(probe.Log, [], "eiDie stops at the nexus' handler")
	check_eq(_stats().GetCount(20, "wela_kills_basebuildingwhileeotfactive"), 1, "the enemy with EotF counts")
	check_eq(_stats().GetCount(21, "wela_kills_basebuildingwhileeotfactive"), 0, "no EotF, no count")
	check_eq(_stats().GetCount(22, "wela_kills_basebuildingwhileeotfactive"), 0, "allies never count")


func test_suicide_on_game_end() -> void:
	_setup(C.nsClient)
	var link := _entity(30)
	TSuicideOnGameEndComponent.new().Create(link)
	check_eq(_bus.Game.EntityManager.Freed, [], "alive during the game")
	_bus.Trigger(C.eiLose, [2])
	check_eq(_bus.Game.EntityManager.Freed, [30], "freed on eiLose, whichever team lost")


# --- card plays ---

func test_card_type_and_colors_from_file_name() -> void:
	check_eq(BC.ScriptFilenameToCardType("Units\\Green\\SaplingSpawner.ets"), C.ctSpawner, "spawner")
	check_eq(BC.ScriptFilenameToCardType("Units\\Blue\\BallistaBuilding.ets"), C.ctBuilding, "building")
	check_eq(BC.ScriptFilenameToCardType("Spells\\Black\\Freeze.sps"), C.ctSpell, "spell by extension")
	check_eq(BC.ScriptFilenameToCardType("units\\white\\healingspell.ets"), C.ctSpell, "identifiers ignore case")
	check_eq(BC.ScriptFilenameToCardType("Units\\Red\\FootmanDrop.ets"), C.ctDrop, "drop")
	check_eq(BC.ScriptFilenameToCardType("Units\\Red\\Footman.ets"), C.ctDrop, "anything else is a drop")
	check_eq(BC.ScriptFilenameToCardColors("Units\\Black\\VoidSkeletonDrop.ets"), [C.ecBlack], "black")
	check_eq(BC.ScriptFilenameToCardColors("units\\GOLEMS\\x.ets"), [C.ecColorless], "golems: colorless")
	check_eq(BC.ScriptFilenameToCardColors("Units\\Scenario\\Boss.ets"), [C.ecColorless], "scenario: colorless")
	check_eq(BC.ScriptFilenameToCardColors("Units\\GreenWhite\\x.ets"), [C.ecWhite], "greenwhite\\ hits white\\ first")
	check_eq(BC.ScriptFilenameToCardColors("Units\\BlackGreen\\x.ets"), [C.ecGreen], "blackgreen\\ hits green\\ first")
	check_eq(BC.ScriptFilenameToCardColors("Commander\\x.ets"), [], "no color folder")


func test_card_play_statistics() -> void:
	_setup()
	var commander := _entity(40, 1, 40)
	TServerCardPlayStatisticsComponent.new().CreateGrouped(commander, [5], "Spells\\Black\\Freeze.sps")
	TServerCardPlayStatisticsComponent.new().CreateGrouped(commander, [6], "Units\\Green\\SaplingSpawner_Green.ets")
	commander.Eventbus.Trigger(C.eiUseAbility, [[]], [5])
	commander.Eventbus.Trigger(C.eiUseAbility, [[]], [5])
	commander.Eventbus.Trigger(C.eiUseAbility, [[]], [6])
	check_eq(_stats().GetCount(40, "global_spells"), 2, "two spells")
	check_eq(_stats().GetCount(40, "global_spawners"), 1, "one spawner")
	check_eq(_stats().GetCount(40, "card_play_color_black"), 2, "black twice")
	check_eq(_stats().GetCount(40, "card_play_color_green"), 1, "green once")
	check_eq(_stats().GetCount(40, "card_play_Freeze"), 2, "per card, without path and .sps")
	check_eq(_stats().GetCount(40, "card_play_SaplingSpawner.ets"), 1, "per card, color suffix removed")
	check_eq(_stats().GetCount(40, "card_play_countoftype"), 2, "the most played card")


# --- income payout ---

func test_income_payout() -> void:
	_setup()
	var a := _entity(50, 1, 50)
	var b := _entity(51, 2, 51)
	var pa: LocalProbe = LocalProbe.new().Create(a)
	var pb: LocalProbe = LocalProbe.new().Create(b)
	_bus.Game.Commanders = [a, b]
	var source: IncomeSource = IncomeSource.new().Create(_entities[0])
	source.Incomes[50] = RIncome.Create(12.5, 3.0)
	var game_entity := _entity(52)
	TWelaEffectIncomePayoutComponent.new().CreateGrouped(game_entity, [0])
	game_entity.Eventbus.Trigger(C.eiFire, [[]], [0])
	check_eq(pa.Log, [["Transaction", C.reGold, 12.5], ["Transaction", C.reWood, 3.0]], "gold, then wood")
	check_eq(pb.Log, [["Transaction", C.reGold, 0.0], ["Transaction", C.reWood, 0.0]], "no income: 0")
	check_eq(RParam.AsSingle(a.Balance(C.reGold)), 12.5, "booked on the commander")


# --- wave spawn ---

func _wave_spawner(tutorial: bool) -> TWelaEffectWaveSpawnComponent:
	_bus.Game.GameInformation.Tutorial = tutorial
	_bus.Game.Map.BuildZones.AddBuildZone(TBuildZone.new().Create(1)).AddBuildZone(TBuildZone.new().Create(0))
	var e := _entity(60)
	var w: TWelaEffectWaveSpawnComponent = TWelaEffectWaveSpawnComponent.new().CreateGrouped(e, [1])
	e.Eventbus.Trigger(C.eiAfterCreate, [])
	return w


func test_wave_spawn_tutorial_order() -> void:
	_setup()
	var w := _wave_spawner(true)
	var e: TEntity = w.Owner
	e.Eventbus.Trigger(C.eiFire, [[]], [1])
	# fields x then y without corners: index 6 = (2, 2), 19 = (7, 1), 13 = (5, 0)
	check_eq(_log.Named("WaveSpawn"), [[0, Vector2i(2, 2)], [1, Vector2i(2, 2)]], "zones in hash order 0, 1")
	e.Eventbus.Trigger(C.eiFire, [[]], [1])
	e.Eventbus.Trigger(C.eiFire, [[]], [1])
	var zone0: Array = _log.Named("WaveSpawn").filter(func(x): return x[0] == 0).map(func(x): return x[1])
	check_eq(zone0, [Vector2i(2, 2), Vector2i(7, 1), Vector2i(5, 0)], "the fixed tutorial order")


func test_wave_spawn_cycle_and_filter() -> void:
	_setup()
	seed(4711)
	var w := _wave_spawner(false)
	var e: TEntity = w.Owner
	for i in BC.BUILDGRID_SLOTS:
		e.Eventbus.Trigger(C.eiFire, [[]], [1])
	var zone1: Array = _log.Named("WaveSpawn").filter(func(x): return x[0] == 1).map(func(x): return x[1])
	check_eq(zone1.size(), 20, "20 wave spawns")
	var unique: Array = []
	for f in zone1:
		if not unique.has(f):
			unique.append(f)
	check_eq(unique.size(), 20, "every field once per cycle")
	check(not unique.has(Vector2i(0, 0)) and not unique.has(Vector2i(7, 2)), "never a corner")
	var last: Vector2i = zone1[19]
	_log.Log.clear()
	# the cycle is empty now: a spawner's own request refills it first
	_bus.Trigger(C.eiWaveSpawn, [1, last])
	check_eq(_log.Named("WaveSpawn"), [[1, last]], "the field spawned last passes")
	var other := Vector2i(3, 1) if last != Vector2i(3, 1) else Vector2i(4, 1)
	var third := Vector2i(5, 1) if last != Vector2i(5, 1) else Vector2i(6, 1)
	_bus.Trigger(C.eiWaveSpawn, [1, other])
	_bus.Trigger(C.eiWaveSpawn, [1, other])
	check_eq(_log.Named("WaveSpawn").size(), 3, "a field of the refilled cycle passes, and again as the last one")
	_bus.Trigger(C.eiWaveSpawn, [1, Vector2i(0, 0)])
	_bus.Trigger(C.eiWaveSpawn, [7, other])
	check_eq(_log.Named("WaveSpawn").size(), 3, "a corner and a zone without rotation are stopped")
	_bus.Trigger(C.eiWaveSpawn, [1, last])
	check_eq(_log.Named("WaveSpawn").size(), 3, "used in this cycle and no longer the last one: stopped")
	_bus.Trigger(C.eiWaveSpawn, [1, third])
	check_eq(_log.Named("WaveSpawn").size(), 4, "a field still in the cycle passes")
	_bus.Trigger(C.eiWaveSpawn, [1, other])
	check_eq(_log.Named("WaveSpawn").size(), 4, "a used field that is not the last one is stopped")


# --- wela statistics ---

func test_wela_statistics_fire_and_targets() -> void:
	_setup()
	var owner := _entity(70, 1, 70)
	var ally := _entity(71, 1, 71)
	ally.Blackboard.SetValue(C.eiUnitProperties, [], [C.upUnit, C.upGround])
	var flyer := _entity(72, 1, 72)
	flyer.Blackboard.SetValue(C.eiUnitProperties, [], [C.upUnit, C.upFlying])
	owner.Blackboard.SetValue(C.eiWelaTargetCount, [3], 3)
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [3]).Name("Heal").Name("Heal2").TriggerOnFire() \
		.CheckUnitPropertyMustHave([C.upGround]).TakeOwnerFromTarget().CheckMaxTargets()
	var targets := [RTarget.Create(ally), RTarget.Create(flyer), RTarget.Create(Vector2(1, 1))]
	owner.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(targets)], [3])
	check_eq(_stats().GetCount(70, "wela_triggers_Heal"), 1, "a trigger for the owner")
	check_eq(_stats().GetCount(70, "wela_triggers_Heal2"), 1, "for every name")
	check_eq(_stats().GetCount(71, "wela_targets_Heal"), 1, "the ground target, for its own commander")
	check_eq(_stats().GetCount(72, "wela_targets_Heal"), 0, "the flyer fails MustHave")
	check_eq(_stats().GetCount(70, "wela_targets_Heal"), 0, "a coordinate fails the unit property check")
	owner.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(targets.slice(0, 2))], [3])
	check_eq(_stats().GetCount(70, "wela_triggers_Heal"), 1, "fewer targets than eiWelaTargetCount: nothing")
	owner.Eventbus.Trigger(C.eiFire, [ATarget.ToRParam(targets)], [4])
	check_eq(_stats().GetCount(70, "wela_triggers_Heal"), 1, "another group's fire: nothing")


func test_wela_statistics_nth_and_times() -> void:
	_setup()
	var owner := _entity(80, 1, 80)
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [2], C.reCharge, 3)
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [2]).Name("Charge").TriggerOnFire().CheckNth(2) \
		.TriggerTimesByResource(C.reCharge)
	for i in 5:
		owner.Eventbus.Trigger(C.eiFire, [[]], [2])
	check_eq(_stats().GetCount(80, "wela_triggers_Charge"), 6, "every 2nd of 5 fires, 3 times each")


func test_wela_statistics_resource_checks() -> void:
	_setup()
	var owner := _entity(81, 1, 81)
	owner.Blackboard.SetIndexedValue(C.eiResourceCap, [2], C.reCharge, 3)
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [2], C.reCharge, 2)
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [2]).Name("Full").TriggerOnFire().CheckResourceMax(C.reCharge)
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [2]).Name("Empty").TriggerOnFire() \
		.CheckResourceEmpty(C.reCharge)
	owner.Eventbus.Trigger(C.eiFire, [[]], [2])
	check_eq([_stats().GetCount(81, "wela_triggers_Full"), _stats().GetCount(81, "wela_triggers_Empty")], [0, 0],
		"2 of 3: neither full nor empty")
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [2], C.reCharge, 3)
	owner.Eventbus.Trigger(C.eiFire, [[]], [2])
	owner.Blackboard.SetIndexedValue(C.eiResourceBalance, [2], C.reCharge, 0)
	owner.Eventbus.Trigger(C.eiFire, [[]], [2])
	check_eq([_stats().GetCount(81, "wela_triggers_Full"), _stats().GetCount(81, "wela_triggers_Empty")], [1, 1],
		"at the cap: full; at 0: empty")


func test_wela_statistics_damage_heal_death() -> void:
	_setup()
	var owner := _entity(90, 1, 90)
	var target := _entity(91, 2, 91)
	target.Blackboard.SetValue(C.eiUnitProperties, [], [C.upUnit])
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Shield").TriggerOnTakeDamage() \
		.CheckDamageType(C.dtRanged)
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Regen").TriggerOnHeal()
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Axe").TriggerOnDamageDone() \
		.TriggerOnDamageDoneTargets().CheckUnitPropertyMustHaveAny([C.upUnit, C.upBuilding])
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Life").TriggerOnHealDone()
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Soul").TriggerOnDie().TriggerOnKilled()
	owner.Eventbus.Read(C.eiTakeDamage, [10.5, [C.dtRanged], 91])
	owner.Eventbus.Read(C.eiTakeDamage, [7.0, [C.dtMelee], 91])
	check_eq(_stats().GetCount(90, "wela_gain_damage_Shield"), 10, "ranged only, round(10.5) = 10")
	owner.Eventbus.Read(C.eiHeal, [4.5, [], 91])
	check_eq(_stats().GetCount(90, "wela_gain_damage_Regen"), 4, "round(4.5) = 4")
	owner.Eventbus.Trigger(C.eiDamageDone, [5.5, [C.dtMelee], target])
	owner.Eventbus.Trigger(C.eiDamageDone, [5.5, [C.dtMelee], owner])
	check_eq(_stats().GetCount(90, "wela_dealt_damage_Axe"), 6, "a unit target only, round(5.5) = 6")
	check_eq(_stats().GetCount(90, "wela_targets_Axe"), 1, "one target")
	owner.Eventbus.Trigger(C.eiHealDone, [2.0, [], target])
	check_eq(_stats().GetCount(90, "wela_dealt_damage_Life"), 2, "heal done")
	owner.Eventbus.Trigger(C.eiDie, [90, 90])
	check_eq(_stats().GetCount(90, "wela_deaths_Soul"), 1, "died")
	check_eq(_stats().GetCount(90, "wela_kills_Soul"), 0, "suicide is no kill")
	owner.Eventbus.Trigger(C.eiDie, [91, 91])
	check_eq(_stats().GetCount(91, "wela_kills_Soul"), 1, "the killer's commander counts the kill")


func test_wela_statistics_kills() -> void:
	_setup()
	var owner := _entity(100, 1, 100)
	var building := _entity(101, 2, 101)
	building.Blackboard.SetValue(C.eiUnitProperties, [], [C.upBuilding])
	var unit := _entity(102, 2, 102)
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Siege").TriggerOnKill() \
		.CheckUnitPropertyMustHave([C.upBuilding])
	TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [1]).Name("Blow").TriggerOnKillDone() \
		.TriggerGlobalOnKillDone()
	owner.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [101])
	owner.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [102])
	owner.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [100])
	check_eq(_stats().GetCount(100, "wela_kills_Siege"), 1, "the building only, no suicide")
	owner.Eventbus.Trigger(C.eiKillDone, [102], [1])
	owner.Eventbus.Trigger(C.eiKillDone, [102], [2])
	owner.Eventbus.Trigger(C.eiKillDone, [100], [1])
	check_eq(_stats().GetCount(100, "wela_kills_Blow"), 1, "a local kill, not another group's, no suicide")
	check_eq(_stats().GetCount(100, "global_kills"), 1, "and a global kill")
	check(unit != null, "unit")


func test_wela_statistics_duration_and_create() -> void:
	_setup()
	var owner := _entity(110, 1, 110)
	var group := owner.ReserveFreeGroup()
	var s: TWelaEffectStatisticsComponent = TWelaEffectStatisticsComponent.new().CreateGrouped(owner, [group]) \
		.Name("Frenzy").TriggerOnDuration().TriggerOnCreate()
	owner.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(_stats().GetCount(110, "wela_triggers_Frenzy"), 1, "counted at create")
	TTimeManager.SetFakeTime(3999.0)
	owner.FreeGroups([group])
	check(s.Owner == null, "the component is freed with its group")
	check_eq(_stats().GetCount(110, "wela_duration_Frenzy"), 3, "3 whole seconds")
