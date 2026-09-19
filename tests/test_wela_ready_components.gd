extends "res://tests/test_case.gd"
## TWelaReady*Component (BaseConflict.EntityComponents.Shared.Wela.pas:1830-2280, :3003, :3086, :3145).
## A wela in group 1: eiIsReady read in [1] is the AND of every ready component there (empty = true).

const C = preload("res://src/runtime/dws/dws_const.gd")
const F = preload("res://tests/component_fakes.gd")

var _free: Array = []


func after_each() -> void:
	TTimeManager.SetFakeTime(null)
	for o in _free:
		o.Free()
	_free.clear()


func _entity(side: int = C.nsServer, game = null) -> TEntity:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	bus.Game = game
	_free.append(bus)
	var e := TEntity.new().Create(bus)
	_free.push_front(e)
	return e


func _ready(e: TEntity, group: Array = [1]):
	return e.Eventbus.Read(C.eiIsReady, [], group)


func test_cost() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reGold, 100.0], [1])
	e.Eventbus.Write(C.eiResourceBalance, [C.reGold, 50.0], [1])
	e.Eventbus.Write(C.eiResourceCost, [C.reGold, 30.0], [1])
	var cost: TWelaReadyCostComponent = TWelaReadyCostComponent.new().CreateGrouped(e, [1])
	check_eq(_ready(e), true, "50 gold pays 30")
	e.Eventbus.Write(C.eiResourceCost, [C.reGold, 60.0], [1])
	check_eq(_ready(e), false, "50 gold can't pay 60")
	e.Eventbus.Write(C.eiResourceCost, [C.reGold, 50.0], [1])
	check_eq(_ready(e), true, "exactly the balance")
	cost.CostsCap()
	check_eq(_ready(e), false, "CostsCap: 100 (the cap) needed")
	check_eq(RResourceCost.GetValue(RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, [], [1])), C.reGold), 50.0,
			"the cost itself stays")


func test_cost_paying_group_and_commander() -> void:
	var game := F.FakeGame.new()
	var e := _entity(C.nsServer, game)
	var commander := TEntity.new().Create(e.GlobalEventbus)
	_free.push_front(commander)
	game.EntityManager.Commander = commander
	e.Eventbus.Write(C.eiResourceCost, [C.reGold, 30.0], [1])
	var cost: TWelaReadyCostComponent = TWelaReadyCostComponent.new().CreateGrouped(e, [1]).SetPayingGroup([2])
	e.Eventbus.Write(C.eiResourceCap, [C.reGold, 100.0], [2])
	e.Eventbus.Write(C.eiResourceBalance, [C.reGold, 40.0], [2])
	check_eq(_ready(e), true, "paid from group 2")
	cost.CommanderPays()
	check_eq(_ready(e), false, "commander has nothing")
	commander.Eventbus.Write(C.eiResourceCap, [C.reGold, 100.0])
	commander.Eventbus.Write(C.eiResourceBalance, [C.reGold, 30.0])
	check_eq(_ready(e), true, "commander pays from []")


func test_cooldown() -> void:
	TTimeManager.SetFakeTime(0.0)
	var e := _entity()
	e.Blackboard.SetValue(C.eiCooldown, [1], 1000)
	var cd: TWelaReadyCooldownComponent = TWelaReadyCooldownComponent.new().CreateGrouped(e, [1])
	check_eq(_ready(e), false, "starts cooling down")
	check_eq(e.Blackboard.GetValue(C.eiCooldownStartingTime, [1]), 0.0, "server writes its start")
	TTimeManager.SetFakeTime(999.0)
	check_eq(_ready(e), false, "999 ms")
	check_eq(e.Eventbus.Read(C.eiCooldownRemainingTime, [], [1]), RParam.ToSingle((1 - RParam.ToSingle(0.999)) * 1000),
			"~1 ms left (single precision, like the original)")
	TTimeManager.SetFakeTime(1000.0)
	check_eq(_ready(e), true, "1000 ms")
	TTimeManager.SetFakeTime(1500.0)
	e.Eventbus.Trigger(C.eiFire, [null], [1])
	TTimeManager.SetFakeTime(2250.0)
	check_eq(_ready(e), false, "restarted by fire")
	check_eq(e.Eventbus.Read(C.eiCooldownProgress, [], [1]), 0.75, "progress")
	TTimeManager.SetFakeTime(2500.0)
	check_eq(_ready(e), true, "ready 1000 ms after the fire")
	check_eq(_ready(e, [2]), null, "other groups: not asked")
	e.Eventbus.Write(C.eiWelaActive, [false], [1])
	TTimeManager.SetFakeTime(9000.0)
	check_eq(_ready(e), false, "inactive: paused")
	check_eq(e.Eventbus.Read(C.eiCooldownRemainingTime, [], [1]), -1.0, "paused: -1")
	cd.FireGroup([3])
	e.Eventbus.Write(C.eiWelaActive, [true], [1])
	TTimeManager.SetFakeTime(10000.0)
	e.Eventbus.Trigger(C.eiFire, [null], [1])
	check_eq(_ready(e), true, "fire outside the FireGroup doesn't restart it")


func test_cooldown_ready_at_start_once_and_reset() -> void:
	TTimeManager.SetFakeTime(0.0)
	var e := _entity()
	e.Blackboard.SetValue(C.eiCooldown, [1], 1000)
	e.Blackboard.SetValue(C.eiWelaActionpoint, [1], 200)
	var cd: TWelaReadyCooldownComponent = TWelaReadyCooldownComponent.new().CreateGrouped(e, [1], true)
	check_eq(_ready(e), true, "ReadyAtStart")
	e.Eventbus.Trigger(C.eiWelaCooldownReset, [false], [1])
	TTimeManager.SetFakeTime(799.0)
	check_eq(_ready(e), false, "reset: cooldown - actionpoint = 800 ms")
	e.Eventbus.Trigger(C.eiWelaCooldownReset, [true], [1])
	check_eq(_ready(e), true, "reset with Finish: ready")
	cd.Once()
	e.Eventbus.Trigger(C.eiFire, [null], [1])
	check_eq(_ready(e), false, "Once: not done until ready once")
	TTimeManager.SetFakeTime(2000.0)
	check_eq(_ready(e), true, "ready")
	e.Eventbus.Trigger(C.eiFire, [null], [1])
	check_eq(_ready(e), true, "Once done: stays ready")
	check_eq(e.Eventbus.Read(C.eiCooldownProgress, [], [1]), 1.0, "Once done: progress 1")


## The client takes its timer's start from eiCooldownStartingTime (sent by the server).
func test_cooldown_client() -> void:
	TTimeManager.SetFakeTime(0.0)
	var e := _entity(C.nsClient)
	e.Blackboard.SetValue(C.eiCooldown, [1], 1000)
	TWelaReadyCooldownComponent.new().CreateGrouped(e, [1])
	e.Blackboard.SetValue(C.eiCooldownStartingTime, [1], 500.0)
	TTimeManager.SetFakeTime(1400.0)
	check_eq(_ready(e), false, "server started it at 500")
	TTimeManager.SetFakeTime(1500.0)
	check_eq(_ready(e), true, "1000 ms after the server's start")


func test_after_game_start_and_ready_chain() -> void:
	var e := _entity()
	TWelaReadyAfterGameStartComponent.new().CreateGrouped(e, [1])
	check_eq(_ready(e), false, "before the first game tick")
	e.GlobalEventbus.Trigger(C.eiGameTick, [])
	check_eq(_ready(e), true, "after it")
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upBlessed])
	TWelaReadyUnitPropertyComponent.new().CreateGrouped(e, [1]).MustNotHave([C.upBlessed])
	check_eq(_ready(e), false, "one component says no: not ready")


func test_after_game_event() -> void:
	var e := _entity()
	var c: TWelaReadyAfterGameEventComponent = TWelaReadyAfterGameEventComponent.new().CreateGrouped(e, [1]).GameEvent("Boss")
	check_eq(_ready(e), false, "not fired yet")
	e.GlobalEventbus.Trigger(C.eiGameEvent, ["Other"])
	check_eq(_ready(e), false, "another event")
	e.GlobalEventbus.Trigger(C.eiGameEvent, ["Boss"])
	check_eq(_ready(e), true, "fired")
	c.FFired = false
	e.Eventbus.Trigger(C.eiAfterCreate, [])
	check_eq(_ready(e), true, "at creation: no time left to the event (empty = 0) counts as fired")


func test_resource_compare() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reHealth, 100.0])
	e.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 40.0])
	var c: TWelaReadyResourceCompareComponent = TWelaReadyResourceCompareComponent.new().CreateGrouped(e, [1])
	c.ComparedResource(C.reHealth).CheckNotFull()
	check_eq(_ready(e), true, "40 % < 100 %")
	c.SetComparator(C.coLower).ReferenceValue(0.4)
	check_eq(_ready(e), false, "0.4 < 0.4 is false")
	c.SetComparator(C.coGreaterEqual).ReferenceValue(40).ReferenceIsAbsolute()
	check_eq(_ready(e), true, "absolute: 40 >= 40")


func test_resource_compare_int_and_additional() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reCharge, 3])
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 1])
	e.Eventbus.Write(C.eiResourceCap, [C.reMana, 5])
	e.Eventbus.Write(C.eiResourceBalance, [C.reMana, 2])
	var c: TWelaReadyResourceCompareComponent = TWelaReadyResourceCompareComponent.new().CreateGrouped(e, [1])
	c.ComparedResource(C.reCharge).ComparedResource(C.reMana).SetComparator(C.coEqual).ReferenceValue(2.5).ReferenceIsAbsolute()
	check_eq(_ready(e), false, "1 + 2 = 3, reference Round(2.5) = 2")
	c.ReferenceValue(3.4)
	check_eq(_ready(e), true, "reference Round(3.4) = 3")
	c.FReferenceIsAbsolute = false
	c.SetComparator(C.coEqual).ReferenceValue(0.375)
	check_eq(_ready(e), true, "fill 3 / 8")


func test_unit_property() -> void:
	var e := _entity()
	e.Blackboard.SetValue(C.eiUnitProperties, [], DSet.Make([C.upUnit, C.upGround]))
	var c: TWelaReadyUnitPropertyComponent = TWelaReadyUnitPropertyComponent.new().CreateGrouped(e, [1])
	c.MustHave([C.upUnit, C.upGround])
	check_eq(_ready(e), true, "has all")
	c.MustHaveAny([C.upBuilding, C.upGround])
	check_eq(_ready(e), true, "has one of")
	c.MustNotHaveAll([C.upUnit, C.upGround])
	check_eq(_ready(e), false, "has all of MustNotHaveAll")
	c.MustNotHaveAll([C.upUnit, C.upBuilding])
	check_eq(_ready(e), true, "not all of them")


func test_unit_property_commander() -> void:
	var game := F.FakeGame.new()
	var e := _entity(C.nsServer, game)
	TWelaReadyUnitPropertyComponent.new().CreateGrouped(e, [1]).MustHave([C.upBlessed]).ChecksCommander()
	check_eq(_ready(e), true, "no commander: ready")
	var commander := TEntity.new().Create(e.GlobalEventbus)
	_free.push_front(commander)
	game.EntityManager.Commander = commander
	check_eq(_ready(e), false, "commander lacks it")


func test_creator() -> void:
	var game := F.FakeGame.new()
	var e := _entity(C.nsServer, game)
	var creator := TEntity.new().Create(e.GlobalEventbus, 5)
	_free.push_front(creator)
	game.EntityManager.Entities[5] = creator
	TWelaReadyCreatorComponent.new().CreateGrouped(e, [1])
	e.Blackboard.SetValue(C.eiCreator, [1], 5)
	check_eq(_ready(e), true, "creator group empty: ready")
	e.Blackboard.SetValue(C.eiCreatorGroup, [1], [4])
	creator.Blackboard.SetValue(C.eiIsReady, [4], false)
	check_eq(_ready(e), false, "creator's group 4 not ready")
	e.Blackboard.SetValue(C.eiCreator, [1], 6)
	check_eq(_ready(e), true, "creator gone: ready")


func test_event_compare() -> void:
	var e := _entity()
	e.Blackboard.SetValue(C.eiWelaRange, [1], 5.0)
	var c: TWelaReadyEventCompareComponent = TWelaReadyEventCompareComponent.new().CreateGrouped(e, [1])
	c.ComparedEvent(C.eiWelaRange).SetComparator(C.coGreater).ReferenceValue(4.5)
	check_eq(_ready(e), true, "5 > 4.5")
	c.CheckingGroup([2])
	check_eq(_ready(e), false, "group 2 empty: 0 > 4.5 is false")


## Real script: the server SmallMeleeGolem's attack (group 1): TWelaReadyCooldownComponent ready at start,
## eiCooldown 1700 - eiWelaActionpoint 533 = 1167 ms after each fire.
func test_real_golem_attack_cooldown() -> void:
	TTimeManager.SetFakeTime(0.0)
	var bus := TEventbus.new().Create(null)
	_free.append(bus)
	var e := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", bus)
	check(e != null, "created: " + TEntity.LastScriptError)
	if e == null:
		return
	_free.push_front(e)
	check_eq(_ready(e), true, "ready at start")
	e.Eventbus.Trigger(C.eiFire, [null], [1])
	TTimeManager.SetFakeTime(1166.0)
	check_eq(_ready(e), false, "1166 ms after the attack")
	TTimeManager.SetFakeTime(1167.0)
	check_eq(_ready(e), true, "1167 ms after the attack")
